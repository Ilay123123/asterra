#!/bin/bash

# deploy.sh - ASTERRA DevOps Assignment Clean Deployment Script
# This script deploys infrastructure without overwriting existing application files

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGION=${AWS_DEFAULT_REGION:-"us-east-1"}
PROJECT_NAME="asterra-assignment"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi

    # Check if SSH key exists
    if [ ! -f ~/.ssh/id_rsa.pub ]; then
        print_warning "SSH public key not found. Generating one..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
        print_success "SSH key pair generated"
    fi

    print_success "All prerequisites met"
}

# Function to initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."

    cd terraform

    # Initialize Terraform
    terraform init

    # Format Terraform files
    terraform fmt

    # Validate configuration
    if terraform validate; then
        print_success "Terraform configuration is valid"
    else
        print_error "Terraform configuration is invalid"
        exit 1
    fi

    cd ..
}

# Function to deploy infrastructure
deploy_infrastructure() {
    print_status "Deploying infrastructure..."

    cd terraform

    # Plan deployment
    print_status "Creating deployment plan..."
    terraform plan -out=tfplan

    # Ask for confirmation
    echo
    read -p "Do you want to apply this plan? (yes/no): " confirm

    if [[ $confirm == "yes" ]]; then
        print_status "Applying Terraform configuration..."
        terraform apply tfplan

        if [ $? -eq 0 ]; then
            print_success "Infrastructure deployed successfully"

            # Show outputs
            print_status "Infrastructure outputs:"
            terraform output
        else
            print_error "Infrastructure deployment failed"
            exit 1
        fi
    else
        print_warning "Deployment cancelled"
        exit 0
    fi

    cd ..
}

# Function to build and push Docker image
build_and_push_image() {
    print_status "Building and pushing Docker image..."

    # Get ECR repository URL from Terraform output
    cd terraform
    ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
    cd ..

    if [ -z "$ECR_URL" ]; then
        print_warning "ECR repository URL not found. Skipping Docker build."
        return
    fi

    # Login to ECR
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL

    # Build and push image
    cd docker/geojson-processor
    docker build -t $ECR_URL:latest .
    docker push $ECR_URL:latest
    cd ../..

    print_success "Docker image built and pushed"
}

# Function to run post-deployment tests
run_tests() {
    print_status "Running post-deployment tests..."

    cd terraform

    # Get outputs
    ALB_DNS=$(terraform output -raw public_alb_dns 2>/dev/null || echo "")
    WINDOWS_IP=$(terraform output -raw windows_workspace_ip 2>/dev/null || echo "")

    cd ..

    if [ -n "$ALB_DNS" ]; then
        print_status "Testing ALB health endpoint..."
        if curl -f "http://$ALB_DNS/health" > /dev/null 2>&1; then
            print_success "ALB health check passed"
        else
            print_warning "ALB health check failed (services may still be starting)"
        fi
    fi

    if [ -n "$WINDOWS_IP" ]; then
        print_status "Testing Windows workspace connectivity..."
        if nc -z -w5 "$WINDOWS_IP" 3389 2>/dev/null; then
            print_success "Windows workspace RDP port is accessible"
        else
            print_warning "Windows workspace RDP port not accessible (may still be booting)"
        fi
    fi

    print_success "Post-deployment tests completed"
}

# Function to upload half-pager to S3
upload_half_pager() {
    print_status "Uploading half-pager to public S3 bucket..."

    cd terraform
    BUCKET_NAME=$(terraform output -raw public_docs_bucket_name 2>/dev/null || echo "")
    BUCKET_URL=$(terraform output -raw public_docs_bucket_url 2>/dev/null || echo "")
    cd ..

    if [ -n "$BUCKET_NAME" ]; then
        aws s3 cp docs/half-pager.html "s3://$BUCKET_NAME/index.html"
        aws s3 cp docs/README.md "s3://$BUCKET_NAME/README.md"
        aws s3 cp docs/ARCHITECTURE.md "s3://$BUCKET_NAME/ARCHITECTURE.md"

        print_success "Documentation uploaded to S3"
        if [ -n "$BUCKET_URL" ]; then
            print_success "Half-pager available at: $BUCKET_URL"
        fi
    else
        print_warning "Could not find S3 bucket for documentation upload"
    fi
}

# Function to display summary
display_summary() {
    print_status "Deployment Summary"
    echo "===================="

    cd terraform

    echo
    print_success "Infrastructure Deployed Successfully!"
    echo
    echo "📋 Key Resources:"
    echo "  • VPC with public/private/database subnets"
    echo "  • PostgreSQL RDS with PostGIS extension"
    echo "  • S3 buckets for data ingestion and state storage"
    echo "  • ECS cluster with Fargate services"
    echo "  • Application Load Balancer with auto-scaling"
    echo "  • Windows development workspace"
    echo "  • ECR repository for container images"
    echo

    echo "🌐 Access Information:"
    ALB_DNS=$(terraform output -raw public_alb_dns 2>/dev/null)
    WINDOWS_IP=$(terraform output -raw windows_workspace_ip 2>/dev/null)
    BUCKET_URL=$(terraform output -raw public_docs_bucket_url 2>/dev/null)

    if [ -n "$ALB_DNS" ]; then
        echo "  • Public Service (ODK Central): http://$ALB_DNS"
    fi

    if [ -n "$WINDOWS_IP" ]; then
        echo "  • Development Workspace (RDP): $WINDOWS_IP:3389"
    fi

    if [ -n "$BUCKET_URL" ]; then
        echo "  • Documentation: $BUCKET_URL"
    fi

    echo
    echo "📚 Next Steps:"
    echo "  1. Access the Windows workspace via RDP for GIS development"
    echo "  2. Upload GeoJSON files to the S3 ingestion bucket"
    echo "  3. Monitor processing through CloudWatch logs"
    echo "  4. Scale services as needed through AWS console"
    echo

    echo "🔧 Management Commands:"
    echo "  • View all outputs: cd terraform && terraform output"
    echo "  • Destroy infrastructure: cd terraform && terraform destroy"
    echo "  • Check service status: aws ecs describe-services --cluster asterra-cluster --services asterra-geojson-processor-service"
    echo

    cd ..

    print_success "ASTERRA DevOps Assignment deployment completed! 🎉"
}

# Main execution flow
main() {
    echo "=================================="
    echo "🚀 ASTERRA DevOps Assignment Deployment"
    echo "=================================="
    echo

    # Check prerequisites
    check_prerequisites

    # Initialize Terraform
    init_terraform

    # Deploy infrastructure
    deploy_infrastructure

    # Build and push Docker image
    build_and_push_image

    # Run tests
    run_tests

    # Upload documentation
    upload_half_pager

    # Display summary
    display_summary
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "ASTERRA DevOps Assignment Deployment Script"
        echo
        echo "Usage: $0 [OPTION]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --check        Check prerequisites only"
        echo "  --plan         Show Terraform plan without applying"
        echo "  --destroy      Destroy all infrastructure"
        echo
        echo "Default: Deploy complete infrastructure"
        exit 0
        ;;
    --check)
        check_prerequisites
        exit 0
        ;;
    --plan)
        check_prerequisites
        init_terraform
        cd terraform
        terraform plan
        cd ..
        exit 0
        ;;
    --destroy)
        print_warning "This will destroy ALL infrastructure!"
        read -p "Are you sure? Type 'yes' to confirm: " confirm
        if [[ $confirm == "yes" ]]; then
            cd terraform
            terraform destroy
            cd ..
            print_success "Infrastructure destroyed"
        else
            print_warning "Destruction cancelled"
        fi
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac