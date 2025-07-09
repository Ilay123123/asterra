# Architecture Diagram

## Network Architecture

```
Internet Gateway
       |
   Public Subnets (Multi-AZ)
   - Application Load Balancer
   - NAT Gateway
   - Windows Development Workspace
       |
   Private Subnets (Multi-AZ)
   - ECS Services
   - EC2 Processing Servers
       |
   Database Subnets (Multi-AZ)
   - PostgreSQL RDS with PostGIS
```

## Data Flow

1. GeoJSON files uploaded to S3 bucket
2. S3 event triggers ECS task
3. ECS task processes file and validates format
4. Valid data stored in PostgreSQL with PostGIS
5. Processing logs sent to CloudWatch

## Security Layers

- Network: VPC, Security Groups, NACLs
- Compute: IAM roles, encrypted storage
- Data: Encrypted S3, RDS encryption, Secrets Manager
- Access: RDP for development, SSH key-based access
