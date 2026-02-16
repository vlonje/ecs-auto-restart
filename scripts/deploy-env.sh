#!/bin/bash

#############################################################################
# ECS Auto-Restart Deployment Script (Using Environment Config Files)
# 
# Usage: 
#   ./scripts/deploy-env.sh production
#   ./scripts/deploy-env.sh staging
#   ./scripts/deploy-env.sh sandbox
#############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"
TEMPLATE_FILE="$SCRIPT_DIR/../infrastructure/ecs_auto_restart.yaml"

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

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

show_usage() {
    echo "Usage: $0 <environment>"
    echo ""
    echo "Available environments:"
    echo "  production  - Deploy to production"
    echo "  staging     - Deploy to staging"
    echo "  sandbox     - Deploy to sandbox/dev"
    echo ""
    echo "Example:"
    echo "  $0 production"
    exit 1
}

load_config() {
    local env=$1
    local config_file="$CONFIG_DIR/${env}.env"
    
    if [ ! -f "$config_file" ]; then
        print_error "Config file not found: $config_file"
        echo ""
        echo "Available config files:"
        ls -1 "$CONFIG_DIR"/*.env 2>/dev/null | xargs -n1 basename || echo "  (none found)"
        exit 1
    fi
    
    print_info "Loading configuration from: $config_file"
    source "$config_file"
    print_success "Configuration loaded"
}

validate_config() {
    local missing=()
    
    [ -z "$STACK_NAME" ] && missing+=("STACK_NAME")
    [ -z "$AWS_REGION" ] && missing+=("AWS_REGION")
    [ -z "$S3_BUCKET" ] && missing+=("S3_BUCKET")
    [ -z "$S3_KEY" ] && missing+=("S3_KEY")
    [ -z "$LAMBDA_ROLE_ARN" ] && missing+=("LAMBDA_ROLE_ARN")
    [ -z "$ECS_CLUSTER_NAME" ] && missing+=("ECS_CLUSTER_NAME")
    [ -z "$ECS_SERVICE_NAMES" ] && missing+=("ECS_SERVICE_NAMES")
    [ -z "$DESIRED_TASK_COUNT" ] && missing+=("DESIRED_TASK_COUNT")
    [ -z "$MONITORING_SCHEDULE" ] && missing+=("MONITORING_SCHEDULE")
    [ -z "$ENVIRONMENT" ] && missing+=("ENVIRONMENT")
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing required configuration variables:"
        for var in "${missing[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
    
    print_success "Configuration validated"
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS credentials valid (Account: $ACCOUNT_ID)"
}

#############################################################################
# Main
#############################################################################

main() {
    cd "$SCRIPT_DIR"
    
    # Check arguments
    if [ $# -ne 1 ]; then
        show_usage
    fi
    
    ENV_NAME=$1
    
    print_header "ECS Auto-Restart Deployment - Environment: $ENV_NAME"
    
    # Step 1: Load and validate config
    print_header "Step 1: Load Configuration"
    load_config "$ENV_NAME"
    validate_config
    
    # Step 2: Validate AWS
    print_header "Step 2: Validate AWS Environment"
    check_aws_cli
    check_aws_credentials
    
    # Step 3: Review configuration
    print_header "Step 3: Review Configuration"
    
    echo -e "${YELLOW}Configuration Summary:${NC}\n"
    echo "  Environment:       $ENVIRONMENT"
    echo "  Stack Name:        $STACK_NAME"
    echo "  Region:            $AWS_REGION"
    echo "  S3 Bucket:         $S3_BUCKET"
    echo "  S3 Key:            $S3_KEY"
    echo "  IAM Role:          $LAMBDA_ROLE_ARN"
    echo "  Cluster:           $ECS_CLUSTER_NAME"
    echo "  Services:          $ECS_SERVICE_NAMES"
    echo "  Desired Count:     $DESIRED_TASK_COUNT"
    echo "  Schedule:          $MONITORING_SCHEDULE"
    echo "  Alert Email:       ${ALERT_EMAIL:-[Not configured]}"
    echo ""
    echo -e "${YELLOW}Note: Lambda will reference S3, but code must be uploaded separately${NC}"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Proceed with deployment? [y/N]: ${NC})" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Step 4: Deploy CloudFormation
    print_header "Step 4: Deploy CloudFormation Stack"
    
    print_info "Creating/Updating CloudFormation stack: $STACK_NAME"
    
    PARAMETERS=(
        "ParameterKey=LambdaExecutionRoleArn,ParameterValue=$LAMBDA_ROLE_ARN"
        "ParameterKey=LambdaS3Bucket,ParameterValue=$S3_BUCKET"
        "ParameterKey=LambdaS3Key,ParameterValue=$S3_KEY"
        "ParameterKey=ECSClusterName,ParameterValue=$ECS_CLUSTER_NAME"
        "ParameterKey=ECSServiceNames,ParameterValue=$ECS_SERVICE_NAMES"
        "ParameterKey=DesiredTaskCount,ParameterValue=$DESIRED_TASK_COUNT"
        "ParameterKey=MonitoringSchedule,ParameterValue=$MONITORING_SCHEDULE"
        "ParameterKey=AlertEmail,ParameterValue=${ALERT_EMAIL:-}"
        "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
    )
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_info "Stack exists. Updating..."
        OPERATION="update-stack"
        WAIT_CONDITION="stack-update-complete"
    else
        print_info "Stack does not exist. Creating..."
        OPERATION="create-stack"
        WAIT_CONDITION="stack-create-complete"
    fi
    
    # Deploy
    if aws cloudformation $OPERATION \
        --stack-name "$STACK_NAME" \
        --template-body file://"$TEMPLATE_FILE" \
        --parameters "${PARAMETERS[@]}" \
        --region "$AWS_REGION" \
        --output text > /dev/null; then
        
        print_success "Stack operation initiated"
        print_info "Waiting for stack operation to complete..."
        
        if aws cloudformation wait $WAIT_CONDITION \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION" 2>/dev/null; then
            
            print_success "Stack operation completed successfully!"
            
            # Step 5: Summary
            print_header "Step 5: Deployment Summary"
            
            aws cloudformation describe-stacks \
                --stack-name "$STACK_NAME" \
                --region "$AWS_REGION" \
                --query 'Stacks[0].Outputs' \
                --output table
            
            echo -e "\n${GREEN}Infrastructure Deployed Successfully!${NC}\n"
            echo -e "${YELLOW}⚠️  IMPORTANT: Lambda code must be uploaded to S3${NC}\n"
            
            echo -e "${GREEN}Next Steps:${NC}\n"
            echo "1. Deploy Lambda code to S3:"
            echo "   ${BLUE}./scripts/deploy-code.sh${NC}"
            echo ""
            echo "2. Test Lambda function:"
            echo "   aws lambda invoke --function-name ${STACK_NAME}-monitor --region $AWS_REGION response.json"
            echo ""
            echo "3. View logs:"
            echo "   aws logs tail /aws/lambda/${STACK_NAME}-monitor --region $AWS_REGION --follow"
            echo ""
            
            print_success "Deployment completed for $ENV_NAME environment! 🎉"
            
        else
            print_error "Stack operation failed or timed out"
            exit 1
        fi
    else
        print_error "Failed to initiate stack operation"
        exit 1
    fi
}

# Run
main "$@"

exit 0