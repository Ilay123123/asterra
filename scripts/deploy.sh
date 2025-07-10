#!/bin/bash
# scripts/deploy.sh - Enhanced with change detection

set -e

echo "🚀 ASTERRA DevOps - Enhanced Deployment Script"

# Check for changes
TERRAFORM_CHANGED=$(git diff --name-only HEAD~1 HEAD | grep -E '^terraform/|\.tf$' | wc -l)
APP_CHANGED=$(git diff --name-only HEAD~1 HEAD | grep -E '^docker/|^src/' | wc -l)

echo "📊 Change Detection:"
echo "   Terraform files: $TERRAFORM_CHANGED changed"
echo "   Application files: $APP_CHANGED changed"

# Terraform operations
if [ "$TERRAFORM_CHANGED" -gt 0 ]; then
    echo "🏗️  Deploying infrastructure changes..."
    cd terraform
    terraform init

    # Check for actual changes
    if terraform plan -detailed-exitcode -out=tfplan; then
        echo "✅ No infrastructure changes needed"
    else
        exit_code=$?
        if [ $exit_code -eq 2 ]; then
            echo "📋 Applying infrastructure changes..."
            terraform apply -auto-approve tfplan
        else
            echo "❌ Terraform plan failed"
            exit 1
        fi
    fi
    cd ..
else
    echo "⏩ Skipping infrastructure (no changes)"
fi

# Application deployment
if [ "$APP_CHANGED" -gt 0 ]; then
    echo "🐳 Building and deploying application..."
    # Your existing Docker build and ECS deployment logic here
else
    echo "⏩ Skipping application build (no changes)"
fi

echo "🎉 Deployment completed successfully!"