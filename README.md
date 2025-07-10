# ASTERRA DevOps Assignment

## Architecture Overview

This project implements a complete cloud infrastructure for processing GeoJSON files using AWS services.

### Components

1. **Networking**: VPC with public/private subnets, security groups
2. **Storage**: S3 buckets for data ingestion and Terraform state
3. **Database**: PostgreSQL RDS with PostGIS extension
4. **Compute**: EC2 instances, ECS cluster, Auto Scaling
5. **Processing**: Containerized GeoJSON processor

### Services Deployed

- **Public Service**: ODK Central server (accessible via ALB)
- **Private Service**: GeoJSON processing microservice
- **Development Workspace**: Windows Server with RDP access
- **Database**: PostgreSQL with PostGIS for spatial data

### Security Features

- Private subnets for sensitive services
- Security groups with least privilege access
- Encrypted storage and secure credential management
- VPC isolation and proper network segmentation

### Deployment

Run the deployment script:
```bash
./deploy.sh
```

### Access Points

- Public ALB: http://asterra-public-alb-391303536.us-east-1.elb.amazonaws.com/
- RDP Workspace: `<windows-public-ip>:3389`
- Database: Accessible only from private subnets

### Monitoring

- CloudWatch logs for all services
- Health checks and auto-scaling
- Performance monitoring enabled

