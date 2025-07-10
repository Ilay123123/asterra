# ASTERRA DevOps Assignment

A complete AWS infrastructure solution for processing GeoJSON files with automated deployment and CI/CD pipeline.

## 📋 Table of Contents
- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Infrastructure Components](#infrastructure-components)
- [Deployment Process](#deployment-process)
- [Access Points](#access-points)
- [Testing](#testing)
- [Security](#security)
- [Monitoring](#monitoring)
- [CI/CD Pipeline](#cicd-pipeline)

## 🏗️ Architecture Overview

This project implements a cloud-native infrastructure for processing GeoJSON files using AWS services with a focus on security, scalability, and maintainability.

### High-Level Architecture
- **Event-Driven Processing**: S3 → Lambda → ECS Fargate → PostgreSQL
- **Network Isolation**: VPC with public/private/database subnets
- **Auto-Scaling**: ALB with Auto Scaling Groups for high availability
- **Container Orchestration**: ECS Fargate for serverless container management

![Architecture Diagram](https://asterra-public-docs-94d54dba.s3.us-east-1.amazonaws.com/architecture.html)

## 📦 Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Docker (for local testing)
- SSH key pair (`~/.ssh/id_rsa.pub`)
- Git

## 🚀 Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/Ilay123123/asterra.git
   cd asterra
   ```

2. **Deploy infrastructure**
   ```bash
   ./deploy.sh
   ```
   This script will:
   - Initialize Terraform
   - Create all AWS resources
   - Build and push Docker images
   - Configure the application

3. **Verify deployment**
   ```bash
   ./docs/test_assignment.sh
   ```

## 🔧 Infrastructure Components

### Networking
- **VPC**: Custom VPC with CIDR 10.0.0.0/16
- **Subnets**: 
  - Public subnets (10.0.1.0/24) - ALB and NAT Gateway
  - Private subnets (10.0.2.0/24) - ECS tasks and processing
  - Database subnets (10.0.3.0/24) - RDS PostgreSQL

### Compute
- **ECS Cluster**: Fargate-based cluster for container orchestration
- **Auto Scaling Group**: EC2 instances for public service
- **Windows Workspace**: RDP-accessible development environment

### Storage
- **S3 Buckets**:
  - `asterra-data-ingestion-*`: GeoJSON file uploads
  - `asterra-terraform-state-*`: Terraform state (encrypted)
  - `asterra-public-docs-*`: Public documentation hosting

### Database
- **RDS PostgreSQL**: With PostGIS extension for spatial data
- **Multi-AZ**: High availability configuration
- **Automated Backups**: 7-day retention

### Processing Pipeline
1. GeoJSON file uploaded to S3
2. Lambda function triggered by S3 event
3. Lambda invokes ECS task
4. ECS task processes file using GeoPandas
5. Processed data stored in PostgreSQL

## 🔄 Deployment Process

### Infrastructure Deployment
```bash
./deploy.sh              # Complete infrastructure deployment
./deploy.sh --plan      # Preview changes without applying
./deploy.sh --destroy   # Tear down all resources
```

### Application Updates
Application updates are automated via GitHub Actions:
- Push to `main` branch triggers the pipeline
- Docker image built and pushed to ECR
- ECS service updated with new image
- Zero-downtime rolling deployment

## 🌐 Access Points

| Service | URL/Endpoint | Access Method |
|---------|--------------|---------------|
| Public ALB | http://asterra-public-alb-391303536.us-east-1.elb.amazonaws.com/ | HTTP |
| Windows RDP | `<public-ip>:3389` | RDP Client |
| Documentation | https://asterra-public-docs-94d54dba.s3.us-east-1.amazonaws.com/ | HTTPS |
| Half-Pager Report | https://asterra-public-docs-94d54dba.s3.us-east-1.amazonaws.com/half-pager.html | HTTPS |

## 🧪 Testing

Run the comprehensive test suite:
```bash
./docs/test_assignment.sh
```

Tests include:
- Infrastructure validation
- Service health checks
- End-to-end GeoJSON processing
- Security configuration verification

## 🔒 Security

### Network Security
- **Security Groups**: Restrictive rules allowing only necessary traffic
- **Private Subnets**: Sensitive services isolated from internet
- **NACLs**: Additional layer of network protection

### Data Security
- **Encryption at Rest**: All S3 buckets and RDS encrypted
- **Encryption in Transit**: TLS/SSL for all communications
- **Secrets Management**: AWS Secrets Manager for credentials

### Access Control
- **IAM Roles**: Least privilege principle
- **S3 Bucket Policies**: Restricted access
- **VPC Endpoints**: Private connectivity to AWS services

## 📊 Monitoring

- **CloudWatch Dashboards**: Real-time metrics visualization
- **Log Groups**: Centralized logging for all services
- **Alarms**: Automated alerts for critical metrics
- **X-Ray**: Distributed tracing (optional)

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow
1. **Test**: Run unit tests and linting
2. **Build**: Create Docker image with GeoPandas
3. **Push**: Upload to Amazon ECR
4. **Deploy**: Update ECS service
5. **Verify**: Health check validation

### Versioning Strategy
- Semantic versioning (vX.Y.Z)
- Automated tagging on main branch
- Image tags: `latest`, version number, and commit SHA

## 📁 Project Structure

```
├── deploy.sh                 # Main deployment script
├── terraform/               # Infrastructure as Code
│   ├── main.tf             # Main configuration
│   ├── network.tf          # VPC and networking
│   ├── compute.tf          # EC2, ECS, and compute resources
│   ├── storage.tf          # S3 buckets
│   ├── database.tf         # RDS configuration
│   └── backend.tf          # Terraform state configuration
├── docker/                  # Container configurations
│   └── geojson-processor/  # GeoPandas application
├── .github/workflows/       # CI/CD pipelines
└── docs/                   # Documentation and tests
```

## 🛠️ Terraform State Management

- **Remote State**: Stored in S3 bucket `asterra-terraform-state-*`
- **State Locking**: DynamoDB table prevents concurrent modifications
- **Versioning**: Enabled for rollback capability
- **Encryption**: Server-side encryption enabled

## 📝 Additional Resources

- [Technical Report](https://asterra-public-docs-94d54dba.s3.us-east-1.amazonaws.com/half-pager.html)
- [Architecture Diagram](https://asterra-public-docs-94d54dba.s3.us-east-1.amazonaws.com/architecture.html)
- [AWS Best Practices](https://aws.amazon.com/architecture/well-architected/)

## 🤝 Contributing

This is a technical assignment project. For questions or clarifications, please contact the development team.

## 📄 License

This project was created as part of the ASTERRA DevOps technical assignment.
