# PostgreSQL RDS instance with PostGIS extension

# Variables
variable  "db_username" {
  description = "Database master username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Database master password"
  type = string
  sensitive = true
  default = "Aa12345678912345"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "asterra_gis"
}

# Data sources to get networking info
data "terraform_remote_state" "networking" {
  backend = "local"  # Change to "s3" if using remote state
  config = {
    path = "./terraform.tfstate"  # Path to networking state file
  }
}

# Random password generation (optional - more secure)
resource "random_password" "db_password" {
  length  = 16
  special = true
}
# RDS Subnet Group (already created in networking.tf, but referencing here)
locals {
  db_subnet_group_name = data.terraform_remote_state.networking.outputs.db_subnet_group_name
  database_sg_id       = data.terraform_remote_state.networking.outputs.security_group_ids.database
  vpc_id              = data.terraform_remote_state.networking.outputs.vpc_id
}

# Parameter Group for PostgreSQL with PostGIS
resource "aws_db_parameter_group" "postgres_postgis" {
  family = "postgres15"
  name   = "asterra-postgres-postgis"

  # Enable PostGIS extension
  parameter {
    name  = "shared_preload_libraries"
    value = "postgis"
  }

  # Performance optimization
  parameter {
    name  = "max_connections"
    value = "200"
  }

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"
  }

  tags = {
    Name        = "asterra-postgres-postgis"
    Environment = "assignment"
  }
}

# RDS Instance - PostgreSQL with PostGIS
resource "aws_db_instance" "postgres" {
  # Basic Configuration
  identifier     = "asterra-postgres-gis"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro"  # Free tier eligible

  # Database Configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password  # Use random_password.db_password.result for random password

  # Storage Configuration
  allocated_storage     = 20    # GB - Free tier limit
  max_allocated_storage = 100   # Auto-scaling limit
  storage_type          = "gp3"
  storage_encrypted     = true

  # Network Configuration
  db_subnet_group_name   = local.db_subnet_group_name
  vpc_security_group_ids = [local.database_sg_id]
  publicly_accessible    = false  # Private database

  # Parameter Group
  parameter_group_name = aws_db_parameter_group.postgres_postgis.name

  # Backup Configuration
  backup_retention_period = 7     # Days
  backup_window          = "03:00-04:00"  # UTC
  maintenance_window     = "sun:04:00-sun:05:00"  # UTC

  # Monitoring
  monitoring_interval = 60  # Seconds
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Security
  deletion_protection = false  # Set to true in production
  skip_final_snapshot = true   # Set to false in production

  # Performance Insights
  performance_insights_enabled = true

  tags = {
    Name        = "asterra-postgres-gis"
    Environment = "assignment"
    Purpose     = "GeoJSON processing and storage"
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name = "asterra-rds-monitoring-role"

  assume_role_policy = jsonencode({
    version = "2012-10-17"
    statement = [
      {
      Actions = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazon.com"
      }
    }
    ]
  })

  tags = {
     Name        = "asterra-rds-monitoring-role"
    Environment = "assignment"
  }
}
# Attach monitoring policy to role
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Log Group for PostgreSQL logs
resource "aws_cloudwatch_log_group" "postgres_logs" {
  name              = "/aws/rds/instance/asterra-postgres-gis/postgresql"
  retention_in_days = 7

  tags = {
    Name        = "asterra-postgres-logs"
    Environment = "assignment"
  }
}
# Secrets Manager for database credentials (best practice)
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "asterra/database/credentials"
  description             = "Database credentials for ASTERRA assignment"
  recovery_window_in_days = 0  # For assignment - allows immediate deletion

  tags = {
    Name        = "asterra-db-credentials"
    Environment = "assignment"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    engine   = "postgres"
    host     = aws_db_instance.postgres.endpoint
    port     = aws_db_instance.postgres.port
    dbname   = var.db_name
  })
}

# Outputs
output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.postgres.port
}

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.postgres.id
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.postgres.db_name
}

output "db_username" {
  description = "Database username"
  value       = var.db_username
  sensitive   = true
}

output "secret_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "parameter_group_name" {
  description = "Name of the DB parameter group"
  value       = aws_db_parameter_group.postgres_postgis.name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for database logs"
  value       = aws_cloudwatch_log_group.postgres_logs.name
}
