name: 'ASTERRA DevOps - Smart CI/CD Pipeline'

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: asterra-assignment
  ECS_CLUSTER: asterra-assignment-assignment
  ECS_SERVICE: assignment-private-service
  TF_VAR_environment: assignment

jobs:
  # Job 1: Detect what changed
  detect-changes:
    name: 'Detect Changes'
    runs-on: ubuntu-latest
    outputs:
      terraform-changed: ${{ steps.changes.outputs.terraform }}
      app-changed: ${{ steps.changes.outputs.app }}
      dockerfile-changed: ${{ steps.changes.outputs.dockerfile }}
      
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      with:
        fetch-depth: 0  # Get full history for change detection
        
    - name: Detect Changes
      uses: dorny/paths-filter@v2
      id: changes
      with:
        filters: |
          terraform:
            - 'terraform/**'
            - '*.tf'
            - 'terraform.tfvars'
          app:
            - 'docker/**'
            - 'src/**'
            - 'requirements*.txt'
          dockerfile:
            - '**/Dockerfile'
            - 'docker/**'

  # Job 2: Terraform Plan and Change Detection
  terraform-plan:
    name: 'Terraform Plan & Change Detection'
    runs-on: ubuntu-latest
    needs: detect-changes
    if: needs.detect-changes.outputs.terraform-changed == 'true'
    outputs:
      terraform-plan-changed: ${{ steps.plan-check.outputs.changed }}
      
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: 1.5.0
        terraform_wrapper: false
        
    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
        
    - name: Terraform Init
      run: |
        cd terraform
        terraform init
        
    - name: Generate Terraform Plan
      id: plan
      run: |
        cd terraform
        terraform plan -detailed-exitcode -out=tfplan || exit_code=$?
        echo "exit_code=$exit_code" >> $GITHUB_OUTPUT
        
        # Exit codes: 0 = no changes, 1 = error, 2 = changes
        if [ $exit_code -eq 1 ]; then
          echo "❌ Terraform plan failed"
          exit 1
        elif [ $exit_code -eq 2 ]; then
          echo "📋 Infrastructure changes detected"
          echo "changed=true" >> $GITHUB_OUTPUT
        else
          echo "✅ No infrastructure changes needed"
          echo "changed=false" >> $GITHUB_OUTPUT
        fi
        
    - name: Cache Terraform Plan
      if: steps.plan.outputs.changed == 'true'
      uses: actions/cache@v3
      with:
        path: terraform/tfplan
        key: terraform-plan-${{ github.sha }}
        
    - name: Comment Plan (PR only)
      if: github.event_name == 'pull_request'
      uses: actions/github-script@v7
      with:
        script: |
          const output = `
          ## 🏗️ Terraform Plan Results
          
          **Changes Detected:** ${{ steps.plan.outputs.changed }}
          
          \`\`\`
          ${{ steps.plan.outputs.stdout }}
          \`\`\`
          `;
          
          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: output
          });

  # Job 3: Build and Test Application
  build-and-test:
    name: 'Build & Test Application'
    runs-on: ubuntu-latest
    needs: detect-changes
    if: needs.detect-changes.outputs.app-changed == 'true' || needs.detect-changes.outputs.dockerfile-changed == 'true'
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
        
    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v2
      
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'
        cache: 'pip'
        
    - name: Install Dependencies
      run: |
        cd docker/geojson-processor
        pip install -r requirements-test.txt
        
    - name: Run Tests
      run: |
        cd docker/geojson-processor
        python -m pytest tests/ -v --tb=short
        
    - name: Build Docker Image
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        cd docker/geojson-processor
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:latest .
        
    - name: Push to ECR
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest

  # Job 4: Deploy Infrastructure (only if Terraform changed)
  deploy-infrastructure:
    name: 'Deploy Infrastructure'
    runs-on: ubuntu-latest
    needs: [terraform-plan, build-and-test]
    if: always() && needs.terraform-plan.outputs.terraform-plan-changed == 'true'
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: 1.5.0
        terraform_wrapper: false
        
    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
        
    - name: Restore Terraform Plan
      uses: actions/cache@v3
      with:
        path: terraform/tfplan
        key: terraform-plan-${{ github.sha }}
        
    - name: Terraform Apply
      run: |
        cd terraform
        terraform init
        terraform apply -auto-approve tfplan
        
    - name: Output Infrastructure Info
      run: |
        cd terraform
        echo "🚀 Infrastructure deployment complete!"
        terraform output -json > ../infrastructure-outputs.json
        
    - name: Upload Infrastructure Outputs
      uses: actions/upload-artifact@v3
      with:
        name: infrastructure-outputs
        path: infrastructure-outputs.json

  # Job 5: Deploy Application (always runs for app changes)
  deploy-application:
    name: 'Deploy Application'
    runs-on: ubuntu-latest
    needs: [detect-changes, build-and-test, deploy-infrastructure]
    if: always() && (needs.build-and-test.result == 'success' || needs.detect-changes.outputs.app-changed == 'true')
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
        
    - name: Download Infrastructure Outputs
      if: needs.deploy-infrastructure.result == 'success'
      uses: actions/download-artifact@v3
      with:
        name: infrastructure-outputs
        
    - name: Update ECS Service
      env:
        IMAGE_TAG: ${{ github.sha }}
      run: |
        # Get current task definition
        TASK_DEFINITION=$(aws ecs describe-task-definition \
          --task-definition $ECS_SERVICE \
          --query 'taskDefinition' \
          --output json)
          
        # Update image URI in task definition
        NEW_TASK_DEFINITION=$(echo $TASK_DEFINITION | jq --arg IMAGE_URI "$ECR_REPOSITORY:$IMAGE_TAG" \
          '.containerDefinitions[0].image = $IMAGE_URI | del(.taskDefinitionArn) | del(.revision) | del(.status) | del(.requiresAttributes) | del(.placementConstraints) | del(.compatibilities) | del(.registeredAt) | del(.registeredBy)')
          
        # Register new task definition
        NEW_TASK_DEFINITION_ARN=$(echo $NEW_TASK_DEFINITION | aws ecs register-task-definition \
          --cli-input-json file:///dev/stdin \
          --query 'taskDefinition.taskDefinitionArn' \
          --output text)
          
        # Update service
        aws ecs update-service \
          --cluster $ECS_CLUSTER \
          --service $ECS_SERVICE \
          --task-definition $NEW_TASK_DEFINITION_ARN
          
        echo "✅ ECS service updated with new image: $IMAGE_TAG"
        
    - name: Wait for Deployment
      run: |
        echo "⏳ Waiting for deployment to stabilize..."
        aws ecs wait services-stable \
          --cluster $ECS_CLUSTER \
          --services $ECS_SERVICE
        echo "🎉 Deployment completed successfully!"

  # Job 6: Notification and Summary
  notify-completion:
    name: 'Deployment Summary'
    runs-on: ubuntu-latest
    needs: [detect-changes, terraform-plan, deploy-infrastructure, deploy-application]
    if: always()
    
    steps:
    - name: Generate Deployment Summary
      run: |
        echo "# 🚀 ASTERRA Deployment Summary" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "## Changes Detected:" >> $GITHUB_STEP_SUMMARY
        echo "- **Terraform:** ${{ needs.detect-changes.outputs.terraform-changed }}" >> $GITHUB_STEP_SUMMARY
        echo "- **Application:** ${{ needs.detect-changes.outputs.app-changed }}" >> $GITHUB_STEP_SUMMARY
        echo "- **Dockerfile:** ${{ needs.detect-changes.outputs.dockerfile-changed }}" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "## Actions Taken:" >> $GITHUB_STEP_SUMMARY
        
        if [ "${{ needs.terraform-plan.outputs.terraform-plan-changed }}" == "true" ]; then
          echo "✅ Infrastructure updated" >> $GITHUB_STEP_SUMMARY
        else
          echo "⏩ Infrastructure skipped (no changes)" >> $GITHUB_STEP_SUMMARY
        fi
        
        if [ "${{ needs.deploy-application.result }}" == "success" ]; then
          echo "✅ Application deployed" >> $GITHUB_STEP_SUMMARY
        else
          echo "⏩ Application deployment skipped" >> $GITHUB_STEP_SUMMARY
        fi
        
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "**Deployment completed at:** $(date)" >> $GITHUB_STEP_SUMMARY