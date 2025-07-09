# networking.tf - ASTERRA DevOps Assignment
# Complete networking infrastructure for the assignment

# Variables
variable "rdp_allowed_cidr" {
  description = "CIDR block allowed for RDP access"
  type        = string
  default     = "0.0.0.0/0" # Change to your specific IP for security
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "0.0.0.0/0" # Change to your specific IP for security
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "asterra-main-vpc"
    Environment = "assignment"
    Project     = "asterra-devops"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "asterra-main-igw"
    Environment = "assignment"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name        = "asterra-nat-eip"
    Environment = "assignment"
  }
}

# Public Subnets (Multi-AZ for high availability)
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "asterra-public-subnet-${count.index + 1}"
    Type        = "Public"
    Environment = "assignment"
  }
}

# Private Subnets (Multi-AZ for RDS requirement)
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "asterra-private-subnet-${count.index + 1}"
    Type        = "Private"
    Environment = "assignment"
  }
}

# Database Subnets (for RDS subnet group)
resource "aws_subnet" "database" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 20}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "asterra-database-subnet-${count.index + 1}"
    Type        = "Database"
    Environment = "assignment"
  }
}

# NAT Gateway (in first public subnet)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name        = "asterra-nat-gateway"
    Environment = "assignment"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "asterra-public-rt"
    Type        = "Public"
    Environment = "assignment"
  }
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name        = "asterra-private-rt"
    Type        = "Private"
    Environment = "assignment"
  }
}

# Route Table for Database Subnets (no internet access)
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "asterra-database-rt"
    Type        = "Database"
    Environment = "assignment"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Associate Database Subnets with Database Route Table
resource "aws_route_table_association" "database" {
  count = length(aws_subnet.database)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# Security Group for Public Services (Web servers, Load Balancers)
resource "aws_security_group" "public_sg" {
  name        = "asterra-public-sg"
  description = "Security group for public-facing services"
  vpc_id      = aws_vpc.main.id

  # SSH access (restrict to your IP in production)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # HTTP access
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Custom application ports (for specific services like ODK Central, etc.)
  ingress {
    description = "Custom App Port 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "asterra-public-sg"
    Type        = "Public"
    Environment = "assignment"
  }
}

# Security Group for Private Services (Application servers, processing services)
resource "aws_security_group" "private_sg" {
  name        = "asterra-private-sg"
  description = "Security group for private services"
  vpc_id      = aws_vpc.main.id

  # Allow traffic from public security group
  ingress {
    description     = "From Public Services"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.public_sg.id]
  }

  # Allow internal VPC communication
  ingress {
    description = "Internal VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # SSH from public subnet (for management)
  ingress {
    description = "SSH from Public"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [for subnet in aws_subnet.public : subnet.cidr_block]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "asterra-private-sg"
    Type        = "Private"
    Environment = "assignment"
  }
}

# Security Group for Database (RDS PostgreSQL with PostGIS)
resource "aws_security_group" "database_sg" {
  name        = "asterra-database-sg"
  description = "Security group for PostgreSQL database"
  vpc_id      = aws_vpc.main.id

  # PostgreSQL access from private services
  ingress {
    description     = "PostgreSQL from Private Services"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.private_sg.id]
  }

  # PostgreSQL access from public services (if needed for direct access)
  ingress {
    description     = "PostgreSQL from Public Services"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.public_sg.id]
  }

  # PostgreSQL access from within VPC
  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name        = "asterra-database-sg"
    Type        = "Database"
    Environment = "assignment"
  }
}

# Security Group for RDP Access (Development workspace)
resource "aws_security_group" "rdp_sg" {
  name        = "asterra-rdp-sg"
  description = "Security group for RDP access to development workspace"
  vpc_id      = aws_vpc.main.id

  # RDP access
  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.rdp_allowed_cidr]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "asterra-rdp-sg"
    Type        = "RDP"
    Environment = "assignment"
  }
}

# Security Group for Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "asterra-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "asterra-alb-sg"
    Type        = "LoadBalancer"
    Environment = "assignment"
  }
}

# DB Subnet Group for RDS
resource "aws_db_subnet_group" "main" {
  name       = "asterra-db-subnet-group"
  subnet_ids = [for subnet in aws_subnet.database : subnet.id]

  tags = {
    Name        = "asterra-db-subnet-group"
    Environment = "assignment"
  }
}

# Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "database_subnet_ids" {
  description = "IDs of the database subnets"
  value       = [for subnet in aws_subnet.database : subnet.id]
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}

output "security_group_ids" {
  description = "Map of security group IDs"
  value = {
    public   = aws_security_group.public_sg.id
    private  = aws_security_group.private_sg.id
    database = aws_security_group.database_sg.id
    rdp      = aws_security_group.rdp_sg.id
    alb      = aws_security_group.alb_sg.id
  }
}

output "nat_gateway_ip" {
  description = "Public IP of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}