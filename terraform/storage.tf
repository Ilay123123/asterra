# S3 buckets for file ingestion and infrastructure state

# Variables
variable "s3_force_destroy" {
  description = "Allow bucket to be destroyed even if it contains objects"
  type        = bool
  default     = true # For assignment - allows easy cleanup
}

# RandomID for unique bucket names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}


# Data ingestion bucket - where GeoJSON files are uploaded
resource "aws_s3_bucket" "data_ingestion" {
  bucket        = "asterra-data-ingestion-${random_id.bucket_suffix.hex}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name        = "asterra-data-ingestion"
    Purpose     = "GeoJSON file uploads and processing triggers"
    Environment = "assignment"
  }
}

# Versioning for data ingestion bucket
resource "aws_s3_bucket_versioning" "data_ingestion" {
  bucket = aws_s3_bucket.data_ingestion.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for data ingestion bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "data_ingestion" {
  bucket = aws_s3_bucket.data_ingestion.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access for data ingestion bucket
resource "aws_s3_bucket_public_access_block" "data_ingestion" {
  bucket = aws_s3_bucket.data_ingestion.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration for data ingestion bucket
resource "aws_s3_bucket_lifecycle_configuration" "data_ingestion" {
  bucket = aws_s3_bucket.data_ingestion.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365 # Delete files after 1 year
    }

    noncurrent_version_expiration {
      noncurrent_days = 30 # Delete old versions after 30 days
    }
  }

  rule {
    id     = "delete_incomplete_uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Notification configuration for triggering processing
resource "aws_s3_bucket_notification" "data_ingestion_notification" {
  bucket = aws_s3_bucket.data_ingestion.id

  # This will be connected to Lambda/SQS later for processing triggers
  # For now, we'll create the configuration structure

  depends_on = [aws_s3_bucket_public_access_block.data_ingestion]
}


# Infrastructure state bucket - stores Terraform state files
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "asterra-terraform-state-${random_id.bucket_suffix.hex}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name        = "asterra-terraform-state"
    Purpose     = "Terraform state storage"
    Environment = "assignment"
  }
}

# Versioning for state bucket (critical for state management)
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for state bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}


# Block public access for state bucket (very important!)
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}



# Public bucket for serving documentation and reports
resource "aws_s3_bucket" "public_docs" {
  bucket        = "asterra-public-docs-${random_id.bucket_suffix.hex}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name        = "asterra-public-docs"
    Purpose     = "Public documentation and half-pager report"
    Environment = "assignment"
  }
}

# Website configuration for public docs bucket
resource "aws_s3_bucket_website_configuration" "public_docs" {
  bucket = aws_s3_bucket.public_docs.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# # Public read access for docs bucket
# resource "aws_s3_bucket_policy" "public_docs_policy" {
#   bucket = aws_s3_bucket.public_docs.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect    = "Allow"
#         Principal = "*"
#         Action    = "s3:GetObject"
#         Resource  = "${aws_s3_bucket.public_docs.arn}/*"
#       }
#     ]
#   })
# }

# Server-side encryption for public docs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "public_docs" {
  bucket = aws_s3_bucket.public_docs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# CloudWatch log group for S3 access logs (optional)
resource "aws_cloudwatch_log_group" "s3_access_logs" {
  name              = "/aws/s3/access-logs"
  retention_in_days = 7

  tags = {
    Name        = "asterra-s3-access-logs"
    Environment = "assignment"
  }
}

# Sample GeoJSON file for testing
resource "aws_s3_object" "sample_geojson" {
  bucket = aws_s3_bucket.data_ingestion.id
  key    = "samples/tel-aviv-sample.geojson"
  content = jsonencode({
    type = "FeatureCollection"
    features = [
      {
        type = "Feature"
        geometry = {
          type        = "Point"
          coordinates = [34.7818, 32.0853] # Tel Aviv coordinates
        }
        properties = {
          name        = "Tel Aviv Sample Point"
          description = "Sample GeoJSON for ASTERRA assignment"
          timestamp   = timestamp()
        }
      }
    ]
  })
  content_type = "application/geo+json"

  tags = {
    Name        = "sample-geojson"
    Environment = "assignment"
  }
}


# Outputs
output "data_ingestion_bucket_name" {
  description = "Name of the data ingestion S3 bucket"
  value       = aws_s3_bucket.data_ingestion.bucket
}

output "data_ingestion_bucket_arn" {
  description = "ARN of the data ingestion S3 bucket"
  value       = aws_s3_bucket.data_ingestion.arn
}

output "terraform_state_bucket_name" {
  description = "Name of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "terraform_state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "public_docs_bucket_name" {
  description = "Name of the public documentation S3 bucket"
  value       = aws_s3_bucket.public_docs.bucket
}

output "public_docs_bucket_url" {
  description = "Website URL of the public documentation bucket"
  value       = "http://${aws_s3_bucket.public_docs.bucket}.s3-website-${data.aws_region.current.name}.amazonaws.com"
}

output "sample_geojson_url" {
  description = "URL of the sample GeoJSON file"
  value       = "s3://${aws_s3_bucket.data_ingestion.bucket}/${aws_s3_object.sample_geojson.key}"
}

