#!/bin/bash

#############################################################################
# ECS Auto-Restart Deployment Script (Infrastructure Only)
# 
# Usage: ./scripts/deploy.sh
# 
# This script:
# 1. Deploys CloudFormation stack (infrastructure)
# 2. Creates Lambda function shell (no code)
# 3. Sets up EventBridge, SNS, CloudWatch
# 
# After deployment, run ./scripts/deploy-code.sh to add Lambda code
#############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_STACK_NAME="ecs-autorestart-prod"
DEFAULT_REGION="ap-southeast-1"
DEFAULT_DESIRED_COUNT="1"
DEFAULT_SCHEDULE="rate(30 minutes)"
DEFAULT_ENVIRONMENT="production"
LAMBDA_CODE_DIR="../function"
TEMPLATE_FILE="../infrastructure/ecs_auto_restart.yaml"

#############################################################################
# Helper Functions
#############################################################################

print_header() {
    echo -e "\n${BLUE}================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

prompt_input() {
    local prompt=$1
    local default=$2
    local var_name=$3
    
    if [ -n "$default" ]; then
        read -p "$(echo -e ${BLUE}$prompt ${NC}[default: $default]: )" input
        eval $var_name="${input:-$default}"
    else
        read -p "$(echo -e ${BLUE}$prompt: ${NC})" input
        eval $var_name="$input"
    fi
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    print_success "AWS CLI is installed"
}

check_files() {
    if [ ! -f "$LAMBDA_CODE_DIR/main.py" ]; then
        print_error "Lambda code not found: $LAMBDA_CODE_DIR/main.py"
        exit 1
    fi
    print_success "Lambda code found"
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_error "CloudFormation template not found: $TEMPLATE_FILE"
        exit 1
    fi
    print_success "CloudFormation template found"
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS credentials valid (Account: $ACCOUNT_ID)"
}

list_ecs_clusters() {
    print_info "Fetching available ECS clusters..."
    CLUSTERS=$(aws ecs list-clusters --region $REGION --query 'clusterArns[*]' --output text 2>/dev/null || echo "")
    
    if [ -n "$CLUSTERS" ]; then
        echo -e "\n${GREEN}Available clusters:${NC}"
        for cluster in $CLUSTERS; do
            cluster_name=$(echo $cluster | awk -F/ '{print $NF}')
            echo "  - $cluster_name"
        done
        echo ""
    fi
}

list_ecs_services() {
    local cluster=$1
    print_info "Fetching services in cluster: $cluster..."
    SERVICES=$(aws ecs list-services --cluster $cluster --region $REGION --query 'serviceArns[*]' --output text 2>/dev/null || echo "")
    
    if [ -n "$SERVICES" ]; then
        echo -e "\n${GREEN}Available services in $cluster:${NC}"
        for service in $SERVICES; do
            service_name=$(echo $service | awk -F/ '{print $NF}')
            echo "  - $service_name"
        done
        echo ""
    fi
}

package_lambda() {
    print_info "Packaging Lambda function..."
    
    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    
    # Copy Lambda code
    cp $LAMBDA_CODE_DIR/main.py $TEMP_DIR/
    
    # Create zip file
    cd $TEMP_DIR
    zip -q lambda.zip main.py
    
    LAMBDA_ZIP_PATH="$TEMP_DIR/lambda.zip"
    print_success "Lambda packaged: $(du -h $LAMBDA_ZIP_PATH | cut -f1)"
    
    cd - > /dev/null
}

upload_to_s3() {
    local s3_bucket=$1
    local s3_key=$2
    
    print_info "Uploading Lambda to S3..."
    
    # Check if bucket exists, create if not
    if ! aws s3 ls "s3://$s3_bucket" --region $REGION &> /dev/null; then
        print_warning "S3 bucket doesn't exist. Creating..."
        aws s3 mb "s3://$s3_bucket" --region $REGION
        print_success "S3 bucket created: $s3_bucket"
    fi
    
    # Upload Lambda package
    aws s3 cp $LAMBDA_ZIP_PATH "s3://$s3_bucket/$s3_key" --region $REGION
    
    print_success "Lambda uploaded to s3://$s3_bucket/$s3_key"
}

cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf $TEMP_DIR
        print_info "Cleaned up temporary files"
    fi
}

#############################################################################
# Main Deployment Flow
#############################################################################

main() {
    # Change to script directory
    cd "$(dirname "$0")"
    
    print_header "ECS Auto-Restart Deployment (Improved Structure)"
    
    # Step 1: Validation
    print_header "Step 1: Validation"
    check_aws_cli
    check_files
    check_aws_credentials
    
    # Step 2: Configuration
    print_header "Step 2: Configuration"
    
    prompt_input "Enter stack name" "$DEFAULT_STACK_NAME" STACK_NAME
    prompt_input "Enter AWS region" "$DEFAULT_REGION" REGION
    
    # S3 Configuration
    DEFAULT_S3_BUCKET="${STACK_NAME}-lambda-${ACCOUNT_ID}"
    echo ""
    prompt_input "Enter S3 bucket for Lambda code" "$DEFAULT_S3_BUCKET" S3_BUCKET
    prompt_input "Enter S3 key for Lambda code" "ecs-auto-restart/lambda.zip" S3_KEY
    
    print_info "Note: You will upload Lambda code to S3 separately using deploy-code.sh"
    
    # IAM Role
    echo -e "\n${BLUE}Available Lambda roles:${NC}"
    aws iam list-roles --query 'Roles[?contains(RoleName, `lambda`) || contains(RoleName, `Lambda`)].RoleName' --output table 2>/dev/null || echo "  (Unable to list roles)"
    echo ""
    
    prompt_input "Enter Lambda IAM Role ARN" "" ROLE_ARN
    while [ -z "$ROLE_ARN" ]; do
        print_error "Role ARN cannot be empty"
        prompt_input "Enter Lambda IAM Role ARN" "" ROLE_ARN
    done
    
    # ECS Configuration
    list_ecs_clusters
    prompt_input "Enter ECS cluster name" "" CLUSTER_NAME
    while [ -z "$CLUSTER_NAME" ]; do
        print_error "Cluster name cannot be empty"
        prompt_input "Enter ECS cluster name" "" CLUSTER_NAME
    done
    
    list_ecs_services "$CLUSTER_NAME"
    echo -e "${BLUE}Enter ECS service names (comma-separated):${NC}"
    read -p "> " SERVICE_NAMES
    while [ -z "$SERVICE_NAMES" ]; do
        print_error "Service names cannot be empty"
        read -p "> " SERVICE_NAMES
    done
    
    prompt_input "Enter desired task count when restarting" "$DEFAULT_DESIRED_COUNT" DESIRED_COUNT
    
    # Schedule
    echo -e "\n${BLUE}Select monitoring schedule:${NC}"
    echo "  1) rate(15 minutes)"
    echo "  2) rate(30 minutes)"
    echo "  3) rate(1 hour)"
    echo "  4) rate(2 hours)"
    read -p "Enter choice [1-4]: " schedule_choice
    
    case $schedule_choice in
        1) SCHEDULE="rate(15 minutes)" ;;
        2) SCHEDULE="rate(30 minutes)" ;;
        3) SCHEDULE="rate(1 hour)" ;;
        4) SCHEDULE="rate(2 hours)" ;;
        *) SCHEDULE="$DEFAULT_SCHEDULE" ;;
    esac
    
    # Email
    echo -e "\n${BLUE}Enter email for alerts (leave empty to disable):${NC}"
    read -p "> " ALERT_EMAIL
    
    # Environment
    echo -e "\n${BLUE}Select environment:${NC}"
    echo "  1) production"
    echo "  2) staging"
    echo "  3) development"
    read -p "Enter choice [1-3]: " env_choice
    
    case $env_choice in
        1) ENVIRONMENT="production" ;;
        2) ENVIRONMENT="staging" ;;
        3) ENVIRONMENT="development" ;;
        *) ENVIRONMENT="$DEFAULT_ENVIRONMENT" ;;
    esac
    
    # Step 3: Review
    print_header "Step 3: Review Configuration"
    
    echo -e "${YELLOW}Please review your configuration:${NC}\n"
    echo "  Stack Name:        $STACK_NAME"
    echo "  Region:            $REGION"
    echo "  S3 Bucket:         $S3_BUCKET"
    echo "  S3 Key:            $S3_KEY"
    echo "  IAM Role:          $ROLE_ARN"
    echo "  Cluster:           $CLUSTER_NAME"
    echo "  Services:          $SERVICE_NAMES"
    echo "  Desired Count:     $DESIRED_COUNT"
    echo "  Schedule:          $SCHEDULE"
    echo "  Alert Email:       ${ALERT_EMAIL:-[Disabled]}"
    echo "  Environment:       $ENVIRONMENT"
    echo ""
    echo -e "${YELLOW}Note: Lambda will reference S3, but code must be uploaded separately${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Proceed with deployment? [y/N]: ${NC})" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled"
        exit 0
    fi
    
    # Step 4: Deploy CloudFormation
    print_header "Step 4: Deploy CloudFormation Stack (Infrastructure Only)"
    
    print_info "Creating CloudFormation stack: $STACK_NAME"
    print_info "Lambda function will reference S3: s3://$S3_BUCKET/$S3_KEY"
    
    PARAMETERS=(
        "ParameterKey=LambdaExecutionRoleArn,ParameterValue=$ROLE_ARN"
        "ParameterKey=LambdaS3Bucket,ParameterValue=$S3_BUCKET"
        "ParameterKey=LambdaS3Key,ParameterValue=$S3_KEY"
        "ParameterKey=ECSClusterName,ParameterValue=$CLUSTER_NAME"
        "ParameterKey=ECSServiceNames,ParameterValue=$SERVICE_NAMES"
        "ParameterKey=DesiredTaskCount,ParameterValue=$DESIRED_COUNT"
        "ParameterKey=MonitoringSchedule,ParameterValue=$SCHEDULE"
        "ParameterKey=AlertEmail,ParameterValue=$ALERT_EMAIL"
        "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
    )
    
    if aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body file://"$TEMPLATE_FILE" \
        --parameters "${PARAMETERS[@]}" \
        --region "$REGION" \
        --output text > /dev/null; then
        
        print_success "Stack creation initiated"
        print_info "Waiting for stack creation to complete..."
        
        if aws cloudformation wait stack-create-complete \
            --stack-name "$STACK_NAME" \
            --region "$REGION" 2>/dev/null; then
            
            print_success "Stack created successfully!"
            
            # Step 5: Summary
            print_header "Step 5: Deployment Summary"
            
            aws cloudformation describe-stacks \
                --stack-name "$STACK_NAME" \
                --region "$REGION" \
                --query 'Stacks[0].Outputs' \
                --output table
            
            echo -e "\n${GREEN}Infrastructure Created Successfully!${NC}\n"
            echo -e "${YELLOW}⚠️  IMPORTANT: Lambda code must be uploaded to S3${NC}\n"
            
            echo -e "${GREEN}Next Steps:${NC}\n"
            
            echo "1. Deploy Lambda code to S3:"
            echo "   ${BLUE}./scripts/deploy-code.sh${NC}"
            echo ""
            echo "   Or manually:"
            echo "   cd function && zip lambda.zip main.py"
            echo "   aws s3 cp lambda.zip s3://$S3_BUCKET/$S3_KEY"
            echo "   aws lambda update-function-code --function-name ${STACK_NAME}-monitor --s3-bucket $S3_BUCKET --s3-key $S3_KEY --region $REGION"
            echo ""
            
            if [ -n "$ALERT_EMAIL" ]; then
                echo "2. Check email ($ALERT_EMAIL) and confirm SNS subscription"
                echo ""
                echo "3. After deploying code, test Lambda:"
            else
                echo "2. After deploying code, test Lambda:"
            fi
            
            echo "   aws lambda invoke --function-name ${STACK_NAME}-monitor --region $REGION response.json"
            echo ""
            echo "4. View logs:"
            echo "   aws logs tail /aws/lambda/${STACK_NAME}-monitor --region $REGION --follow"
            echo ""
            
            print_success "Infrastructure deployment completed! 🎉"
            print_info "Remember: Lambda code is stored in S3 at s3://$S3_BUCKET/$S3_KEY"
            print_info "Run ./scripts/deploy-code.sh to upload code"
            
        else
            print_error "Stack creation failed or timed out"
            exit 1
        fi
    else
        print_error "Failed to create stack"
        exit 1
    fi
}

# Trap to ensure cleanup on exit
# (No cleanup needed - not packaging Lambda)

# Run main function
main

exit 0