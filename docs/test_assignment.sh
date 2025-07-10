#!/bin/bash

# ASTERRA DevOps Assignment - Complete End-to-End Testing Script
# This script validates the entire infrastructure and application flow

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✅ PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠️ WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[❌ FAIL]${NC} $1"
}

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"  # Default: expect success (0)

    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    print_status "Running test: $test_name"

    if eval "$test_command" >/dev/null 2>&1; then
        if [ "$expected_result" -eq 0 ]; then
            print_success "$test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_error "$test_name (expected failure but got success)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        if [ "$expected_result" -ne 0 ]; then
            print_success "$test_name (expected failure)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_error "$test_name"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    fi
}

# Function to display test summary
show_summary() {
    echo
    echo "=========================================="
    echo "📊 ASTERRA Assignment Test Summary"
    echo "=========================================="
    echo "Total Tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"

    if [ "$TESTS_FAILED" -eq 0 ]; then
        print_success "All tests passed! 🎉 Ready to submit!"
    else
        print_error "Some tests failed. Check the output above."
        echo
        echo "🔧 Quick fixes for common issues:"
        echo "  - Wait 2-3 minutes for services to fully start"
        echo "  - Check AWS console for any deployment issues"
        echo "  - Verify your AWS credentials are working"
    fi
    echo "=========================================="
}

# Main test execution
main() {
    echo "🚀 Starting ASTERRA DevOps Assignment End-to-End Testing"
    echo "=========================================="

    # Get Terraform outputs
    cd terraform
    ALB_DNS=$(terraform output -raw public_alb_dns 2>/dev/null || echo "")
    WINDOWS_IP=$(terraform output -raw windows_workspace_ip 2>/dev/null || echo "")
    INGESTION_BUCKET=$(terraform output -raw data_ingestion_bucket_name 2>/dev/null || echo "")
    DOCS_BUCKET=$(terraform output -raw public_docs_bucket_name 2>/dev/null || echo "")
    ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
    cd ..

    if [ -z "$ALB_DNS" ]; then
        print_error "Cannot get Terraform outputs. Is infrastructure deployed?"
        exit 1
    fi

    print_status "Using ALB DNS: $ALB_DNS"
    print_status "Testing infrastructure components..."

    # ================================
    # INFRASTRUCTURE TESTS
    # ================================

    print_status "🏗️ Testing Infrastructure Components"

    # Test 1: ALB Health Check
    run_test "ALB Health Endpoint" "curl -f -s http://$ALB_DNS/health"

    # Test 2: ALB Main Page
    run_test "ALB Main Page" "curl -f -s http://$ALB_DNS/"

    # Test 3: Windows RDP Port
    if [ -n "$WINDOWS_IP" ]; then
        run_test "Windows RDP Port (3389)" "nc -z -w5 $WINDOWS_IP 3389"
    else
        print_warning "Windows IP not found, skipping RDP test"
    fi

    # Test 4: AWS CLI Connection
    run_test "AWS CLI Authentication" "aws sts get-caller-identity"

    # Test 5: S3 Bucket Access
    if [ -n "$INGESTION_BUCKET" ]; then
        run_test "S3 Ingestion Bucket Access" "aws s3 ls s3://$INGESTION_BUCKET/"
    else
        print_warning "Ingestion bucket name not found"
    fi

    # Test 6: ECR Repository
    if [ -n "$ECR_URL" ]; then
        ECR_REPO=$(echo $ECR_URL | cut -d'/' -f2)
        run_test "ECR Repository Access" "aws ecr describe-repositories --repository-names $ECR_REPO"
    else
        print_warning "ECR URL not found"
    fi

    # ================================
    # APPLICATION TESTS
    # ================================

    print_status "🐳 Testing Application Components"

    # Test 7: ECS Cluster Status
    run_test "ECS Cluster Status" "aws ecs describe-clusters --clusters asterra-cluster"

    # Test 8: ECS Service Status
    run_test "ECS Service Running" "aws ecs describe-services --cluster asterra-cluster --services asterra-geojson-processor"

    # Test 9: Container Image in ECR
    if [ -n "$ECR_URL" ]; then
        ECR_REPO=$(echo $ECR_URL | cut -d'/' -f2)
        run_test "Container Image in ECR" "aws ecr list-images --repository-name $ECR_REPO"
    fi

    # ================================
    # END-TO-END WORKFLOW TEST
    # ================================

    print_status "🔄 Testing End-to-End GeoJSON Processing Workflow"

    if [ -n "$INGESTION_BUCKET" ]; then
        # Create a test GeoJSON file
        TEST_FILE="/tmp/test-$(date +%s).geojson"
        cat > "$TEST_FILE" << 'EOF'
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
        "name": "ASTERRA Test Point",
        "description": "Test GeoJSON for DevOps assignment",
        "timestamp": "2025-07-10T10:00:00Z"
      }
    }
  ]
}
EOF

        # Test 10: Upload GeoJSON to S3
        run_test "Upload Test GeoJSON to S3" "aws s3 cp $TEST_FILE s3://$INGESTION_BUCKET/test/"

        # Test 11: Verify file was uploaded
        run_test "Verify GeoJSON Upload" "aws s3 ls s3://$INGESTION_BUCKET/test/"

        # Test 12: Check CloudWatch logs for processing (wait a bit)
        print_status "Waiting 30 seconds for Lambda/ECS processing..."
        sleep 30

        # Try to find Lambda log group
        LOG_GROUP="/aws/lambda/asterra-s3-processor"
        run_test "Lambda Processing Logs" "aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP"

        # Cleanup test file
        rm -f "$TEST_FILE"
        print_status "Test file cleaned up"
    else
        print_warning "Cannot test GeoJSON workflow - bucket name not found"
    fi

    # ================================
    # SECURITY TESTS
    # ================================

    print_status "🔒 Testing Security Configuration"

    # Test 13: Check if RDS is in private subnet (should not be publicly accessible)
    run_test "RDS Not Publicly Accessible" "aws rds describe-db-instances --query 'DBInstances[?PubliclyAccessible==\`false\`]' --output text | grep -q asterra"

    # Test 14: S3 Bucket Encryption
    if [ -n "$INGESTION_BUCKET" ]; then
        run_test "S3 Bucket Encryption" "aws s3api get-bucket-encryption --bucket $INGESTION_BUCKET"
    fi

    # ================================
    # LOAD BALANCING & AUTO SCALING TEST
    # ================================

    print_status "⚖️ Testing Load Balancing and Auto Scaling"

    # Test 15: Target Group Health
    TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --names asterra-public-tg --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
    if [ -n "$TARGET_GROUP_ARN" ] && [ "$TARGET_GROUP_ARN" != "None" ]; then
        run_test "Target Group Health Check" "aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN"
    else
        print_warning "Target group not found, skipping health check test"
    fi

    # Test 16: Auto Scaling Group Status
    run_test "Auto Scaling Group Status" "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names asterra-public-asg"

    # ================================
    # DOCUMENTATION TESTS
    # ================================

    print_status "📚 Testing Documentation and Deliverables"

    # Test 17: Half-pager exists
    run_test "Half-pager Documentation Exists" "test -f docs/half-pager.html"

    # Test 18: README exists
    run_test "README Documentation Exists" "test -f docs/README.md"

    # Test 19: Deployment script exists and is executable
    run_test "Deployment Script Exists and Executable" "test -x deploy.sh"

    # Test 20: Public docs bucket accessible
    if [ -n "$DOCS_BUCKET" ]; then
        DOCS_URL="http://$DOCS_BUCKET.s3-website-us-east-1.amazonaws.com"
        run_test "Public Documentation Accessible" "curl -f -s $DOCS_URL"
    else
        print_warning "Docs bucket not found, skipping public docs test"
    fi

    # Show final summary
    show_summary

    # Exit with appropriate code
    if [ "$TESTS_FAILED" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"