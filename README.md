# Asterra
# ASTERRA DevOps Technical Assignment

## Project Overview

This project implements a complete cloud infrastructure for processing GeoJSON geospatial data files using AWS services. Think of it as building a smart factory that automatically processes geographic data - when you drop a file in one end, it comes out validated and stored in a spatial database on the other end.

## What This System Does

The infrastructure creates a **data processing pipeline** that works like an assembly line:

1. **Input**: Upload GeoJSON files to an S3 bucket (like dropping mail in a mailbox)
2. **Processing**: Automatic validation and format checking (quality control)
3. **Storage**: Valid data gets stored in PostgreSQL with PostGIS (organized filing system)
4. **Access**: Web interface and development tools for managing the data

## Architecture Components

### Core Infrastructure (The Foundation)
- **VPC with Multi-AZ setup**: Your private cloud network with backup zones
- **Public/Private Subnets**: Separate areas for public-facing and internal services
- **Security Groups**: Smart firewalls that control access between components
- **Internet Gateway & NAT**: Controlled internet access for services

### Data Processing (The Engine)
- **S3 Buckets**: File storage for incoming GeoJSON files and documentation
- **ECS Fargate**: Containerized processing service that scales automatically
- **Lambda Functions**: Event-driven processors triggered by file uploads
- **ECR Repository**: Storage for Docker container images

### Database Layer (The Memory)
- **PostgreSQL RDS**: Managed database with automatic backups
- **PostGIS Extension**: Geographic data types and spatial functions
- **Multi-AZ deployment**: High availability with automatic failover

### Development Environment (The Workshop)
- **Windows Server EC2**: Development workspace with GIS tools
- **RDP Access**: Remote desktop for development work
- **Pre-installed Tools**: QGIS, Git, Docker, Python, AWS CLI, Terraform

### Monitoring & Security (The Watchdog)
- **CloudWatch**: Logging and monitoring for all services
- **Secrets Manager**: Secure credential storage
- **IAM Roles**: Fine-grained permissions for each service
- **Encrypted Storage**: All data encrypted at rest and in transit

## Quick Start Guide

### Prerequisites
```bash
# Check if you have the required tools
aws --version        # AWS CLI
terraform --version  # Terraform
docker --version     # Docker
```

### One-Command Deployment
```bash
# This script does everything for you
./deploy.sh
```

The deployment script handles:
- Infrastructure creation via Terraform
- Docker image building and pushing
- Service deployment and configuration
- Documentation upload to S3
- Health checks and validation

### Manual Step-by-Step (If You Want to Understand Each Part)

1. **Initialize Terraform**
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

2. **Build and Push Docker Image**
   ```bash
   # Get ECR login
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ecr-url>
   
   # Build and push
   cd docker/geojson-processor
   docker build -t <ecr-url>:latest .
   docker push <ecr-url>:latest
   ```

3. **Upload Documentation**
   ```bash
   aws s3 cp docs/half-pager.html s3://<bucket-name>/index.html
   ```

## How to Use the System

### Accessing Your Development Environment
1. Get the Windows Server IP from Terraform output:
   ```bash
   cd terraform
   terraform output windows_workspace_ip
   ```
2. Connect via RDP using your favorite RDP client
3. Use the pre-installed tools for development work

### Processing GeoJSON Files
1. Upload files to the S3 ingestion bucket
2. Watch CloudWatch logs for processing status
3. Query the PostgreSQL database for processed data

### Monitoring and Management
- **Health Endpoint**: `http://<alb-dns>/health`
- **CloudWatch Logs**: Monitor processing in real-time
- **ECS Console**: Scale services up or down as needed

## Project Structure Explained

```
asterra-assignment/
├── terraform/              # Infrastructure as Code
│   ├── main.tf             # Main configuration
│   ├── networking.tf       # VPC, subnets, security groups
│   ├── compute.tf          # EC2, ECS, scaling configurations
│   ├── database.tf         # RDS PostgreSQL with PostGIS
│   └── scripts/            # Initialization scripts
├── docker/                 # Application containers
│   └── geojson-processor/  # GeoJSON validation service
├── docs/                   # Documentation and reports
│   ├── README.md           # This file
│   ├── half-pager.html     # Technical summary
│   └── ARCHITECTURE.md     # Detailed architecture
└── deploy.sh               # Single-command deployment
```

## Security Features

**Network Security** (Like Building Security)
- Private subnets for sensitive services (employees-only areas)
- Security groups with least privilege (smart door locks)
- VPC isolation (private building with controlled access)

**Data Security** (Like a Bank Vault)
- Encrypted storage for databases and S3 (locked safes)
- Secrets Manager for credentials (secure key management)
- IAM roles with minimal permissions (employee badges)

**Access Security** (Like ID Checks)
- RDP access from configurable IP ranges
- Database access only from within VPC
- SSH key-based authentication for Linux instances

## DevOps Best Practices Implemented

### Infrastructure as Code
- **Terraform**: All infrastructure defined in code
- **Version Control**: Track changes and rollback capabilities
- **Reproducible**: Deploy identical environments anywhere

### Containerization
- **Docker**: Application packaged with all dependencies
- **ECR**: Managed container registry
- **ECS Fargate**: Serverless container orchestration

### Monitoring and Logging
- **CloudWatch**: Centralized logging and metrics
- **Health Checks**: Automatic service monitoring
- **Alerts**: Notification when things go wrong

### Security
- **Least Privilege**: Each service gets only needed permissions
- **Encryption**: Data protected at rest and in transit
- **Secret Management**: Credentials stored securely

## Troubleshooting Common Issues

### Deployment Fails
```bash
# Check AWS credentials
aws sts get-caller-identity

# Validate Terraform
cd terraform && terraform validate

# Check for conflicting resources
terraform plan
```

### Can't Connect to Windows Server
```bash
# Verify security group allows your IP
terraform output rdp_security_group_id

# Check instance status
aws ec2 describe-instances --filters "Name=tag:Name,Values=asterra-windows-workspace"
```

### Services Not Starting
```bash
# Check ECS service status
aws ecs describe-services --cluster asterra-cluster --services asterra-geojson-processor-service

# View logs
aws logs describe-log-groups --log-group-name-prefix "/ecs/asterra"
```

## Understanding the Assignment Requirements

This implementation addresses all the key requirements:

✅ **Public/Private Service Separation**: ALB in public subnet, processing in private  
✅ **VPC Network Design**: Multi-AZ with proper subnet architecture  
✅ **RDP Development Workspace**: Windows Server with GIS tools  
✅ **Container with GeoPandas**: Docker image with spatial data libraries  
✅ **ECR Registry**: Automated image building and pushing  
✅ **Single Script Deployment**: `./deploy.sh` handles everything  
✅ **Infrastructure as Code**: Complete Terraform implementation  
✅ **Security Best Practices**: Encryption, IAM, network isolation  
✅ **Documentation**: Half-pager and technical documentation  

## Learning Notes (DevOps Concepts)

### Why This Architecture?
Think of this like building a restaurant:
- **Public Subnet** = Dining area (customers can access)
- **Private Subnet** = Kitchen (only staff can access)
- **Database Subnet** = Storage room (only specific staff can access)
- **Security Groups** = Different staff uniforms with different access levels

### Key DevOps Patterns Used
1. **Infrastructure as Code**: Recipe that anyone can follow to build the same restaurant
2. **Microservices**: Each service does one thing well (like having a dedicated chef for each dish)
3. **Container Orchestration**: Like having a restaurant manager who automatically assigns chefs based on how busy it gets
4. **Monitoring**: Like having cameras and sensors to know when something goes wrong

### Why These Tools?
- **Terraform**: Industry standard for infrastructure automation
- **Docker**: Ensures your app runs the same everywhere
- **ECS Fargate**: No servers to manage, just run your containers
- **PostgreSQL + PostGIS**: The gold standard for spatial databases
- **CloudWatch**: AWS-native monitoring that integrates with everything

## Next Steps After Deployment

1. **Test the System**: Upload a sample GeoJSON file
2. **Explore the Database**: Connect and query spatial data
3. **Monitor Performance**: Watch CloudWatch metrics
4. **Scale Services**: Adjust ECS service desired count
5. **Secure Access**: Restrict RDP to your specific IP range

## Cleanup

When you're done:
```bash
./deploy.sh --destroy
```

This removes all AWS resources to avoid ongoing charges.

---

**Implementation completed as part of ASTERRA DevOps Technical Assignment**  
*This documentation serves as both a deployment guide and learning resource for understanding modern DevOps practices.*