# main.tf - ASTERRA DevOps Assignment
# Main orchestration file - connects all modules together

# ==============================================================================
# TERRAFORM CONFIGURATION
# ==============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Backend configuration for state storage
  # Uncomment after first deployment when S3 bucket is created
  # backend "s3" {
  #   bucket         = "asterra-terraform-state-XXXXXXXX"  # Replace with actual bucket name
  #   key            = "terraform/asterra-assignment.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "asterra-terraform-locks"  # Optional: for state locking
  # }
}

# ==============================================================================
# PROVIDERS
# ==============================================================================

provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = local.common_tags
  }
}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# ==============================================================================
# LOCAL VALUES
# ==============================================================================

locals {
  # Common tags applied to all resources
  common_tags = merge(var.common_tags, {
    Timestamp   = timestamp()
    Region      = data.aws_region.current.name
    AccountId   = data.aws_caller_identity.current.account_id
    DeployedBy  = "terraform"
  })

  # Resource naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  # Application configuration
  app_name = "${local.name_prefix}-app"

  # Availability zones (limit to first 2 for cost optimization)
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# ==============================================================================
# RANDOM ID FOR UNIQUE NAMING
# ==============================================================================

resource "random_id" "deployment" {
  byte_length = 4

  keepers = {
    project     = var.project_name
    environment = var.environment
  }
}

# ==============================================================================
# LAMBDA FUNCTION FOR S3 PROCESSING TRIGGER
# ==============================================================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_s3_processor" {
  name = "${local.name_prefix}-lambda-s3-processor"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Lambda to trigger ECS tasks
resource "aws_iam_policy" "lambda_s3_processor_policy" {
  name = "${local.name_prefix}-lambda-s3-processor-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.data_ingestion.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_s3_processor_policy" {
  role       = aws_iam_role.lambda_s3_processor.name
  policy_arn = aws_iam_policy.lambda_s3_processor_policy.arn
}

# Attach basic execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_s3_processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function to trigger ECS task when GeoJSON files are uploaded
resource "aws_lambda_function" "s3_geojson_processor" {
  filename         = "lambda_function.zip"
  function_name    = "${local.name_prefix}-s3-geojson-processor"
  role            = aws_iam_role.lambda_s3_processor.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER_NAME = aws_ecs_cluster.main.name
      ECS_TASK_DEFINITION = aws_ecs_task_definition.geojson_processor.arn
      ECS_SUBNETS = join(",", aws_subnet.private[*].id)
      ECS_SECURITY_GROUPS = aws_security_group.private_sg.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_s3_processor_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = local.common_tags
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"

  source {
    content = templatefile("${path.module}/lambda/s3_processor.py", {
      ecs_cluster_name = aws_ecs_cluster.main.name
    })
    filename = "index.py"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-s3-geojson-processor"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# S3 bucket notification to trigger Lambda
resource "aws_s3_bucket_notification" "geojson_processor_trigger" {
  bucket = aws_s3_bucket.data_ingestion.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_geojson_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".geojson"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_geojson_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_ingestion.arn
}

# ==============================================================================
# CLOUDWATCH DASHBOARDS AND ALARMS
# ==============================================================================

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "asterra_dashboard" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.public_alb.arn_suffix],
            [".", "TargetResponseTime", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Application Load Balancer Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.geojson_processor.name, "ClusterName", aws_ecs_cluster.main.name],
            [".", "MemoryUtilization", ".", ".", ".", "."],
            [".", "RunningTaskCount", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "ECS Service Metrics"
          period  = 300
        }
      }
    ]
  })
}

# ==============================================================================
# OUTPUTS - Only main orchestration outputs
# ==============================================================================

# Deployment Information
output "deployment_info" {
  description = "Information about this deployment"
  value = {
    project_name    = var.project_name
    environment     = var.environment
    aws_region      = data.aws_region.current.name
    aws_account_id  = data.aws_caller_identity.current.account_id
    deployment_id   = random_id.deployment.hex
    deployed_at     = timestamp()
  }
}

# Lambda Function
output "lambda_function_name" {
  description = "Name of the Lambda function for S3 processing"
  value       = aws_lambda_function.s3_geojson_processor.function_name
}

# Monitoring
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.asterra_dashboard.dashboard_name}"
}

# Access Instructions - Consolidated from all modules
output "access_instructions" {
  description = "Instructions for accessing deployed services"
  value = {
    public_service       = "Access ODK Central at: http://${aws_lb.public_alb.dns_name}"
    windows_workspace    = "RDP to: ${aws_instance.windows_workspace.public_ip}:3389"
    documentation       = "View docs at: http://${aws_s3_bucket.public_docs.bucket}.s3-website-${data.aws_region.current.name}.amazonaws.com"
    monitoring          = "CloudWatch Dashboard: https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.asterra_dashboard.dashboard_name}"
    s3_upload_bucket    = "Upload GeoJSON files to: s3://${aws_s3_bucket.data_ingestion.bucket}"
  }
}