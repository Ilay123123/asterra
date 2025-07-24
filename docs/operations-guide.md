# ASTERRA Infrastructure Operations Guide

## Quick Reference
```bash
# Project Structure
├── terraform/          # Infrastructure as Code
├── docker/            # Container definitions
├── docs/              # Documentation
├── deploy.sh          # Main deployment script
└── .github/workflows/ # CI/CD pipelines
```

## Essential Commands & Access Points

git clone https://github.com/your-username/asterra.git


### AWS Resources
```bash
# S3 Bucket (Data Ingestion) - Dynamically find bucket with random suffix
INGESTION_BUCKET=$(aws s3 ls | grep asterra-data-ingestion | awk '{print $3}')
echo "Ingestion Bucket: $INGESTION_BUCKET"

# Alternative method using Terraform output
cd terraform
INGESTION_BUCKET=$(terraform output -raw data_ingestion_bucket_name 2>/dev/null || aws s3 ls | grep asterra-data-ingestion | awk '{print $3}')
cd ..

# ALB URL
ALB_URL=$(aws elbv2 describe-load-balancers --names asterra-public-alb --query 'LoadBalancers[0].DNSName' --output text)
echo "ALB URL: http://$ALB_URL"

# RDP Instance
RDP_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=asterra-windows-workspace" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "RDP: $RDP_IP:3389"

# ECR Repository
ECR_REPO=$(aws ecr describe-repositories --repository-names asterra-app --query 'repositories[0].repositoryUri' --output text)
echo "ECR: $ECR_REPO"

# All S3 Buckets
echo "All Project Buckets:"
aws s3 ls | grep asterra
```

## System Health Checks

### 1. Infrastructure Status
```bash
# Check all Terraform resources
cd terraform
terraform show | grep -E "resource|id|status|endpoint"

# Verify core services
aws ecs describe-services --cluster asterra-cluster --services asterra-geojson-processor --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'

# RDS Status
aws rds describe-db-instances --db-instance-identifier asterra-postgres-gis --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}'
```

### 2. Application Health
```bash
# ECS Task Status
aws ecs list-tasks --cluster asterra-cluster --service-name asterra-geojson-processor

# Recent Lambda Invocations
aws logs tail /aws/lambda/asterra-assignment-assignment-s3-geojson-processor --since 1h

# Container Logs
aws logs tail /ecs/asterra-geojson-processor --since 30m
```

## GeoJSON Processing Workflow

### Upload and Process File
```bash
# 1. Create test GeoJSON
cat > test-geojson.json << 'EOF'
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "Point",
        "coordinates": [34.7818, 32.0853]
      },
      "properties": {
        "name": "Test Location",
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      }
    }
  ]
}
EOF

# 2. Upload to S3 (use the dynamically found bucket name)
aws s3 cp test-geojson.json s3://$INGESTION_BUCKET/incoming/

# 3. Monitor Processing
# Watch Lambda logs
aws logs tail /aws/lambda/asterra-assignment-assignment-s3-geojson-processor --follow &

# Watch ECS logs
aws logs tail /ecs/asterra-geojson-processor --follow &
```

### Verify Processing Results
```bash
# Check if file was processed
aws s3 ls s3://$INGESTION_BUCKET/incoming/

# Connect to database (from private instance or through bastion)
PGPASSWORD=$(aws secretsmanager get-secret-value --secret-id asterra-db-credentials --query SecretString --output text | jq -r .password)
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier asterra-postgres-gis --query 'DBInstances[0].Endpoint.Address' --output text)
psql -h $DB_ENDPOINT -U postgres -d asterra_gis -c "\dt"
```

## Troubleshooting Guide

### Issue: File Not Processing

#### Step 1: Verify S3 Upload
```bash
# List files in bucket
aws s3 ls s3://$INGESTION_BUCKET/incoming/ --recursive

# Check S3 event configuration
aws s3api get-bucket-notification-configuration --bucket $INGESTION_BUCKET
```

#### Step 2: Check Lambda Execution
```bash
# View Lambda metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=asterra-assignment-assignment-s3-geojson-processor \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Check for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/asterra-assignment-assignment-s3-geojson-processor \
  --filter-pattern "ERROR"
```

#### Step 3: Verify ECS Task Launch
```bash
# List recent tasks
aws ecs list-tasks --cluster asterra-cluster --started-by "lambda"

# Describe task details
TASK_ARN=$(aws ecs list-tasks --cluster asterra-cluster --query 'taskArns[0]' --output text)
aws ecs describe-tasks --cluster asterra-cluster --tasks $TASK_ARN
```

#### Step 4: Database Connectivity
```bash
# Check security groups
aws ec2 describe-security-groups --group-ids $(aws rds describe-db-instances --db-instance-identifier asterra-postgres-gis --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)

# Test from ECS task subnet
aws ecs run-task \
  --cluster asterra-cluster \
  --task-definition asterra-geojson-processor \
  --overrides '{"containerOverrides":[{"name":"geojson-processor","command":["python","-c","import psycopg2; print(\"DB connection test\")"]}]}'
```

### Issue: Container Failing to Start

```bash
# Get task definition
aws ecs describe-task-definition --task-definition asterra-geojson-processor

# Check ECR image
aws ecr describe-images --repository-name asterra-app --image-ids imageTag=latest

# Pull and test locally
$(aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REPO)
docker pull $ECR_REPO:latest
docker run --rm $ECR_REPO:latest python -c "import geopandas; print('GeoPandas OK')"
```

### Issue: Network Connectivity Problems

```bash
# Verify VPC configuration
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=asterra-vpc"

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID"

# Verify NAT Gateway
aws ec2 describe-nat-gateways --filter "Name=state,Values=available"

# Test security groups
aws ec2 describe-security-groups --filters "Name=tag:Project,Values=asterra-assignment"
```

## Performance Monitoring

### CloudWatch Metrics
```bash
# ECS Service CPU/Memory
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=asterra-geojson-processor Name=ClusterName,Value=asterra-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# RDS Performance
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=asterra-postgres-gis \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### Application Logs Analysis
```bash
# Find slow queries
aws logs filter-log-events \
  --log-group-name /ecs/asterra-geojson-processor \
  --filter-pattern "[timestamp, request_id, level=ERROR || level=WARNING, message]"

# Processing time analysis
aws logs insights query \
  --log-group-name /ecs/asterra-geojson-processor \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query 'fields @timestamp, duration | stats avg(duration) by bin(5m)'
```

## Scaling Operations

### Manual Scaling
```bash
# Scale ECS Service
aws ecs update-service \
  --cluster asterra-cluster \
  --service asterra-geojson-processor \
  --desired-count 3

# Update Auto Scaling Group
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name asterra-public-asg \
  --desired-capacity 3
```

### Auto Scaling Configuration
```bash
# Create scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/asterra-cluster/asterra-geojson-processor \
  --policy-name cpu-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    }
  }'
```

## Database Operations

### Connect to PostgreSQL
```bash
# Get credentials
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id asterra-db-credentials --query SecretString --output text | jq -r .password)
DB_HOST=$(aws rds describe-db-instances --db-instance-identifier asterra-postgres-gis --query 'DBInstances[0].Endpoint.Address' --output text)

# Connect via psql
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U postgres -d asterra_gis

# Common queries
# List all tables
\dt

# Check PostGIS extension
SELECT PostGIS_full_version();

# View processed data
SELECT COUNT(*) FROM geojson_data;
SELECT * FROM geojson_data LIMIT 10;
```

### Database Maintenance
```bash
# Create backup
aws rds create-db-snapshot \
  --db-instance-identifier asterra-postgres-gis \
  --db-snapshot-identifier asterra-backup-$(date +%Y%m%d%H%M%S)

# Modify instance (e.g., scale up)
aws rds modify-db-instance \
  --db-instance-identifier asterra-postgres-gis \
  --db-instance-class db.t3.medium \
  --apply-immediately
```

## CI/CD Operations

### Manual Deployment
```bash
# Build and push Docker image
cd docker/geojson-processor
docker build -t $ECR_REPO:manual-$(date +%Y%m%d%H%M%S) .
docker push $ECR_REPO:manual-$(date +%Y%m%d%H%M%S)

# Update ECS service with new image
aws ecs update-service \
  --cluster asterra-cluster \
  --service asterra-geojson-processor \
  --force-new-deployment
```

### GitHub Actions Status
```bash
# Check workflow runs (requires gh CLI)
gh workflow list
gh run list --workflow=deploy.yml

# View logs
gh run view <run-id> --log
```

## Security Audit

### IAM Roles Review
```bash
# List all project roles
aws iam list-roles --query "Roles[?contains(RoleName, 'asterra')].[RoleName,CreateDate]" --output table

# Check role policies
aws iam list-attached-role-policies --role-name asterra-ecs-task-role
aws iam list-role-policies --role-name asterra-ecs-task-role
```

### Security Groups Audit
```bash
# List all security groups
aws ec2 describe-security-groups --filters "Name=tag:Project,Values=asterra-assignment" --query "SecurityGroups[*].[GroupId,GroupName,Description]" --output table

# Check specific rules
aws ec2 describe-security-groups --group-ids sg-xxxxxx --query "SecurityGroups[0].IpPermissions"
```

### Secrets Management
```bash
# List secrets
aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'asterra')].[Name,LastChangedDate]" --output table

# Rotate database password
aws secretsmanager rotate-secret --secret-id asterra-db-credentials
```

## Emergency Procedures

### Service Recovery
```bash
# Restart ECS service
aws ecs update-service --cluster asterra-cluster --service asterra-geojson-processor --force-new-deployment

# Stop all tasks
aws ecs list-tasks --cluster asterra-cluster --service-name asterra-geojson-processor | \
  jq -r '.taskArns[]' | \
  xargs -I {} aws ecs stop-task --cluster asterra-cluster --task {}
```

### Rollback Deployment
```bash
# List previous task definitions
aws ecs list-task-definitions --family-prefix asterra-geojson-processor

# Update service to previous version
aws ecs update-service \
  --cluster asterra-cluster \
  --service asterra-geojson-processor \
  --task-definition asterra-geojson-processor:PREVIOUS_VERSION
```

### Resource Cleanup
```bash
# Clean up old Docker images in ECR
aws ecr list-images --repository-name asterra-app --query 'imageIds[?imageTag!=`latest`]' | \
  jq '.[] | select(.imageTag | startswith("v"))' | \
  jq -s '.' | \
  xargs -I {} aws ecr batch-delete-image --repository-name asterra-app --image-ids '{}'

# Remove old S3 objects
aws s3 rm s3://$BUCKET_NAME/processed/ --recursive --exclude "*" --include "*.json" --older-than 30
```

## Useful Aliases
```bash
# Add to ~/.bashrc or ~/.zshrc
alias asterra-logs='aws logs tail /ecs/asterra-geojson-processor --follow'
alias asterra-tasks='aws ecs list-tasks --cluster asterra-cluster --service-name asterra-geojson-processor'
alias asterra-health='aws ecs describe-services --cluster asterra-cluster --services asterra-geojson-processor --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount}"'
alias asterra-bucket='aws s3 ls s3://$(aws s3 ls | grep asterra-data-ingestion | awk "{print \$3}")/'
alias asterra-upload='function _upload() { aws s3 cp "$1" s3://$(aws s3 ls | grep asterra-data-ingestion | awk "{print \$3}")/incoming/; }; _upload'
```

## Quick Start Commands
```bash
# Set environment variables for easy access
export INGESTION_BUCKET=$(aws s3 ls | grep asterra-data-ingestion | awk '{print $3}')
export ALB_URL=$(aws elbv2 describe-load-balancers --names asterra-public-alb --query 'LoadBalancers[0].DNSName' --output text)
export RDP_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=asterra-windows-workspace" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# Display all key resources
echo "=== ASTERRA Infrastructure ==="
echo "Ingestion Bucket: s3://$INGESTION_BUCKET"
echo "ALB URL: http://$ALB_URL"
echo "RDP Access: $RDP_IP:3389"
echo "=============================="
```
