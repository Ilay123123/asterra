# variables.tf - ASTERRA DevOps Assignment
# Clean variable definitions (removing duplicates)

# ==============================================================================
# GENERAL CONFIGURATION VARIABLES
# ==============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "asterra-assignment"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "assignment"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# ==============================================================================
# NETWORKING VARIABLES (not defined elsewhere)
# ==============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Note: ssh_allowed_cidr, rdp_allowed_cidr, availability_zones are in networking.tf

# ==============================================================================
# DATABASE VARIABLES (not defined elsewhere)
# ==============================================================================

# Note: db_username, db_password, db_name are in database.tf

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"  # Free tier eligible
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS instance (GB)"
  type        = number
  default     = 20  # Free tier limit
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for auto-scaling (GB)"
  type        = number
  default     = 100
}

# ==============================================================================
# STORAGE VARIABLES (not defined elsewhere)
# ==============================================================================

# Note: s3_force_destroy is in storage.tf

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management"
  type        = bool
  default     = true
}

# ==============================================================================
# COMPUTE VARIABLES (not defined elsewhere)
# ==============================================================================

# Note: instance_type, windows_instance_type, key_pair_name, enable_detailed_monitoring are in compute.tf

# ==============================================================================
# AUTO SCALING VARIABLES
# ==============================================================================

variable "asg_min_size" {
  description = "Minimum size of Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum size of Auto Scaling Group"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired capacity of Auto Scaling Group"
  type        = number
  default     = 1
}

variable "cpu_threshold_high" {
  description = "CPU threshold for scaling up"
  type        = number
  default     = 70
}

variable "cpu_threshold_low" {
  description = "CPU threshold for scaling down"
  type        = number
  default     = 30
}

# ==============================================================================
# ECS VARIABLES
# ==============================================================================

variable "ecs_cpu" {
  description = "CPU units for ECS tasks (256, 512, 1024, etc.)"
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Memory for ECS tasks (MB)"
  type        = number
  default     = 512
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

# ==============================================================================
# MONITORING VARIABLES
# ==============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
}

variable "enable_performance_insights" {
  description = "Enable RDS Performance Insights"
  type        = bool
  default     = true
}

# ==============================================================================
# APPLICATION VARIABLES
# ==============================================================================

variable "app_port" {
  description = "Port for the application"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Health check path for load balancer"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 2
}

# ==============================================================================
# SECURITY VARIABLES
# ==============================================================================

variable "enable_encryption" {
  description = "Enable encryption for storage resources"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false  # Set to true in production
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

# ==============================================================================
# CONTAINER VARIABLES
# ==============================================================================

variable "container_image_tag" {
  description = "Tag for container images"
  type        = string
  default     = "latest"
}

variable "ecr_scan_on_push" {
  description = "Enable vulnerability scanning on image push"
  type        = bool
  default     = true
}

# ==============================================================================
# DEVELOPMENT VARIABLES
# ==============================================================================

variable "enable_development_tools" {
  description = "Enable development tools and services"
  type        = bool
  default     = true
}

variable "windows_admin_password" {
  description = "Windows administrator password"
  type        = string
  sensitive   = true
  default     = "AsterraAssignment2024!"  # Change this
}

# ==============================================================================
# TAGS
# ==============================================================================

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "asterra-assignment"
    Environment = "assignment"
    Owner       = "devops-candidate"
    ManagedBy   = "terraform"
  }
}

# ==============================================================================
# FEATURE FLAGS
# ==============================================================================

variable "enable_public_service" {
  description = "Enable public service deployment (ODK Central)"
  type        = bool
  default     = true
}

variable "enable_private_service" {
  description = "Enable private GIS processing service"
  type        = bool
  default     = true
}

variable "enable_windows_workspace" {
  description = "Enable Windows development workspace"
  type        = bool
  default     = true
}

variable "enable_container_service" {
  description = "Enable containerized ECS service"
  type        = bool
  default     = true
}

variable "enable_auto_scaling" {
  description = "Enable auto scaling for public services"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and logging"
  type        = bool
  default     = true
}