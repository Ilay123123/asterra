# compute.tf - ASTERRA DevOps Assignment
# Compute infrastructure - EC2, ECS, Auto Scaling

# ==============================================================================
# VARIABLES (only unique to compute)
# ==============================================================================

variable "instance_type" {
  description = "EC2 instance type for general compute"
  type        = string
  default     = "t3.micro"  # Free tier eligible
}

variable "windows_instance_type" {
  description = "EC2 instance type for Windows development workspace"
  type        = string
  default     = "t3.small"  # Minimum for Windows
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access"
  type        = string
  default     = "asterra-assignment-key"
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

# ==============================================================================
# DATA SOURCES FOR AMIs
# ==============================================================================

# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Data source for latest Windows Server AMI
data "aws_ami" "windows_server" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Data source for latest Ubuntu AMI (for Docker workloads)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ==============================================================================
# EC2 KEY PAIR
# ==============================================================================

resource "aws_key_pair" "main" {
  key_name   = var.key_pair_name
  public_key = file("~/.ssh/id_rsa.pub") # Make sure to generate this first

  tags = {
    Name        = "asterra-assignment-key"
    Environment = "assignment"
  }
}

# ==============================================================================
# IAM ROLES FOR EC2
# ==============================================================================

resource "aws_iam_role" "ec2_role" {
  name = "asterra-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "asterra-ec2-role"
    Environment = "assignment"
  }
}

# IAM Policy for S3 and CloudWatch access
resource "aws_iam_policy" "ec2_policy" {
  name        = "asterra-ec2-policy"
  description = "Policy for EC2 instances to access S3 and CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_ingestion.arn,
          "${aws_s3_bucket.data_ingestion.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "ec2_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

# Instance profile for EC2 role
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "asterra-ec2-profile"
  role = aws_iam_role.ec2_role.name

  tags = {
    Name        = "asterra-ec2-profile"
    Environment = "assignment"
  }
}

# ==============================================================================
# USER DATA SCRIPTS
# ==============================================================================

locals {
  public_server_user_data = base64encode(templatefile("${path.module}/scripts/public-server-init.sh", {
    db_endpoint = aws_db_instance.postgres.endpoint
    db_name     = aws_db_instance.postgres.db_name
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }))

  private_server_user_data = base64encode(templatefile("${path.module}/scripts/private-server-init.sh", {
    s3_bucket   = aws_s3_bucket.data_ingestion.bucket
    db_endpoint = aws_db_instance.postgres.endpoint
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }))

  windows_user_data = base64encode(templatefile("${path.module}/scripts/windows-init.ps1", {}))
}

# ==============================================================================
# APPLICATION LOAD BALANCER
# ==============================================================================

resource "aws_lb" "public_alb" {
  name               = "asterra-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets           = aws_subnet.public[*].id

  enable_deletion_protection = false # Set to true in production

  tags = {
    Name        = "asterra-public-alb"
    Environment = "assignment"
  }
}

# Target Group for public services
resource "aws_lb_target_group" "public_tg" {
  name     = "asterra-public-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name        = "asterra-public-tg"
    Environment = "assignment"
  }
}

# ALB Listener
resource "aws_lb_listener" "public_listener" {
  load_balancer_arn = aws_lb.public_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_tg.arn
  }

  tags = {
    Name        = "asterra-public-listener"
    Environment = "assignment"
  }
}

# ==============================================================================
# LAUNCH TEMPLATE & AUTO SCALING
# ==============================================================================

resource "aws_launch_template" "public_server" {
  name_prefix   = "asterra-public-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.main.key_name

  vpc_security_group_ids = [aws_security_group.public_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = local.public_server_user_data

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = var.enable_encryption
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "asterra-public-server"
      Type        = "Public"
      Environment = "assignment"
    }
  }

  tags = {
    Name        = "asterra-public-launch-template"
    Environment = "assignment"
  }
}

# Auto Scaling Group for Public Servers
resource "aws_autoscaling_group" "public_asg" {
  name                = "asterra-public-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.public_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.public_server.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "asterra-public-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "Environment"
    value               = "assignment"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy for Scale Up
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "asterra-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown              = 300
  autoscaling_group_name = aws_autoscaling_group.public_asg.name
}

# CloudWatch Alarm for Scale Up
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "asterra-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = var.cpu_threshold_high
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.public_asg.name
  }
}

# ==============================================================================
# PRIVATE SERVER FOR GIS PROCESSING
# ==============================================================================

resource "aws_instance" "private_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name              = aws_key_pair.main.key_name
  subnet_id             = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = local.private_server_user_data

  monitoring = var.enable_detailed_monitoring

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = var.enable_encryption
  }

  tags = {
    Name        = "asterra-private-server"
    Type        = "Private"
    Environment = "assignment"
    Purpose     = "GIS Processing"
  }
}

# ==============================================================================
# WINDOWS DEVELOPMENT WORKSPACE
# ==============================================================================

resource "aws_instance" "windows_workspace" {
  ami                    = data.aws_ami.windows_server.id
  instance_type          = var.windows_instance_type
  key_name              = aws_key_pair.main.key_name
  subnet_id             = aws_subnet.public[0].id
  vpc_security_group_ids = [
    aws_security_group.public_sg.id,
    aws_security_group.rdp_sg.id
  ]

  user_data = local.windows_user_data

  monitoring = var.enable_detailed_monitoring

  root_block_device {
    volume_type = "gp3"
    volume_size = 50  # Windows needs more space
    encrypted   = var.enable_encryption
  }

  tags = {
    Name        = "asterra-windows-workspace"
    Type        = "Development"
    Environment = "assignment"
    Purpose     = "Development Workspace"
  }
}

# ==============================================================================
# ECR REPOSITORY
# ==============================================================================

resource "aws_ecr_repository" "app_repo" {
  name                 = "asterra-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "asterra-app-repo"
    Environment = "assignment"
  }
}

# ==============================================================================
# ECS CLUSTER
# ==============================================================================

resource "aws_ecs_cluster" "main" {
  name = "asterra-cluster"

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs_logs.name
      }
    }
  }

  tags = {
    Name        = "asterra-ecs-cluster"
    Environment = "assignment"
  }
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/asterra-app"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "asterra-ecs-logs"
    Environment = "assignment"
  }
}

# ==============================================================================
# ECS TASK DEFINITION
# ==============================================================================

resource "aws_ecs_task_definition" "geojson_processor" {
  family                   = "asterra-geojson-processor"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "geojson-processor"
      image = "${aws_ecr_repository.app_repo.repository_url}:${var.container_image_tag}"

      essential = true

      environment = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = data.aws_region.current.name
        },
        {
          name  = "S3_BUCKET"
          value = aws_s3_bucket.data_ingestion.bucket
        },
        {
          name  = "DB_SECRET_ARN"
          value = aws_secretsmanager_secret.db_credentials.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name        = "asterra-geojson-processor"
    Environment = "assignment"
  }
}

# ECS Service for GeoJSON processor
resource "aws_ecs_service" "geojson_processor" {
  name            = "asterra-geojson-processor"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.geojson_processor.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.private_sg.id]
  }

  tags = {
    Name        = "asterra-geojson-processor-service"
    Environment = "assignment"
  }
}

# ==============================================================================
# IAM ROLES FOR ECS
# ==============================================================================

resource "aws_iam_role" "ecs_execution_role" {
  name = "asterra-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "asterra-ecs-execution-role"
    Environment = "assignment"
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name = "asterra-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "asterra-ecs-task-role"
    Environment = "assignment"
  }
}

# Attach policies to ECS roles
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

# Data source for current region (needed for container definitions)
data "aws_region" "current" {}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "public_alb_dns" {
  description = "DNS name of the public Application Load Balancer"
  value       = aws_lb.public_alb.dns_name
}

output "public_alb_zone_id" {
  description = "Zone ID of the public Application Load Balancer"
  value       = aws_lb.public_alb.zone_id
}

output "private_server_ip" {
  description = "Private IP of the private server"
  value       = aws_instance.private_server.private_ip
}

output "windows_workspace_ip" {
  description = "Public IP of the Windows workspace"
  value       = aws_instance.windows_workspace.public_ip
}

output "windows_workspace_id" {
  description = "Instance ID of the Windows workspace"
  value       = aws_instance.windows_workspace.id
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.geojson_processor.name
}