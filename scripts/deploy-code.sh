#!/bin/bash

#############################################################################
# Deploy Lambda Code to S3 and Update Function
# 
# Usage: ./scripts/deploy-code.sh
# 
# This script:
# 1. Packages Lambda function code
# 2. Uploads to S3 bucket
# 3. Updates Lambda function to use new S3 version
#############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
LAMBDA_CODE_DIR="../function"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
}

check_zip() {
    if ! command -v zip &> /dev/null; then
        print_error "zip command not found. Please install: sudo apt install zip"
        exit 1
    fi
}

check_lambda_code() {
    if [ ! -f "$LAMBDA_CODE_DIR/main.py" ]; then
        print_error "Lambda code not found: $LAMBDA_CODE_DIR/main.py"
        exit 1
    fi
    print_success "Lambda code found"
}

package_lambda() {
    print_info "Packaging Lambda function..."
    
    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    
    # Copy Lambda code
    cp "$LAMBDA_CODE_DIR/main.py" "$TEMP_DIR/"
    
    # Create zip file
    cd "$TEMP_DIR"
    zip -q lambda.zip main.py
    
    LAMBDA_ZIP_PATH="$TEMP_DIR/lambda.zip"
    PACKAGE_SIZE=$(du -h "$LAMBDA_ZIP_PATH" | cut -f1)
    print_success "Lambda packaged: $PACKAGE_SIZE"
    
    cd - > /dev/null
}

deploy_lambda_code() {
    local function_name=$1
    local region=$2
    local s3_bucket=$3
    local s3_key=$4
    
    print_info "Uploading code to S3: s3://$s3_bucket/$s3_key"
    
    # Upload to S3
    aws s3 cp "$LAMBDA_ZIP_PATH" "s3://$s3_bucket/$s3_key" --region "$region"
    
    print_success "Code uploaded to S3"
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$function_name" --region "$region" &>/dev/null; then
        print_error "Lambda function '$function_name' not found in region '$region'"
        echo "Make sure CloudFormation stack is deployed first!"
        exit 1
    fi
    
    print_info "Updating Lambda function to use new S3 code..."
    
    # Update function code from S3
    aws lambda update-function-code \
        --function-name "$function_name" \
        --s3-bucket "$s3_bucket" \
        --s3-key "$s3_key" \
        --region "$region" \
        --output table
    
    print_success "Lambda function updated successfully!"
}

cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "Cleaned up temporary files"
    fi
}

#############################################################################
# Main
#############################################################################

main() {
    cd "$SCRIPT_DIR"
    
    print_header "Deploy Lambda Code Only"
    
    # Validation
    print_header "Step 1: Validation"
    check_aws_cli
    check_zip
    check_lambda_code
    
    # Get Lambda function name
    print_header "Step 2: Configuration"
    
    echo -e "${BLUE}Available Lambda functions:${NC}"
    aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `autorestart`) || contains(FunctionName, `monitor`)].FunctionName' \
        --output table 2>/dev/null || echo "  (Unable to list functions)"
    echo ""
    
    prompt_input "Enter Lambda function name" "ecs-autorestart-sandbox-monitor" FUNCTION_NAME
    prompt_input "Enter AWS region" "ap-southeast-1" REGION
    
    echo ""
    prompt_input "Enter S3 bucket for Lambda code" "" S3_BUCKET
    while [ -z "$S3_BUCKET" ]; do
        print_error "S3 bucket cannot be empty"
        prompt_input "Enter S3 bucket for Lambda code" "" S3_BUCKET
    done
    
    prompt_input "Enter S3 key for Lambda code" "ecs-auto-restart/lambda.zip" S3_KEY
    
    # Confirm
    print_header "Step 3: Review"
    echo -e "${YELLOW}Configuration:${NC}\n"
    echo "  Function Name: $FUNCTION_NAME"
    echo "  Region:        $REGION"
    echo "  S3 Bucket:     $S3_BUCKET"
    echo "  S3 Key:        $S3_KEY"
    echo ""
    
    read -p "$(echo -e ${YELLOW}Deploy code to S3 and update Lambda? [y/N]: ${NC})" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Package and deploy
    print_header "Step 4: Package Lambda Code"
    package_lambda
    
    print_header "Step 5: Upload to S3 and Update Lambda"
    deploy_lambda_code "$FUNCTION_NAME" "$REGION" "$S3_BUCKET" "$S3_KEY"
    
    # Summary
    print_header "Deployment Complete"
    
    echo -e "${GREEN}Lambda Code Deployment Summary:${NC}\n"
    echo "  📦 Packaged:  function/main.py"
    echo "  ☁️  S3 Location: s3://$S3_BUCKET/$S3_KEY"
    echo "  🔄 Updated:   $FUNCTION_NAME"
    echo ""
    
    echo -e "${GREEN}Next Steps:${NC}\n"
    echo "1. Test the Lambda function:"
    echo "   aws lambda invoke --function-name $FUNCTION_NAME --region $REGION response.json"
    echo ""
    echo "2. View logs:"
    echo "   aws logs tail /aws/lambda/$FUNCTION_NAME --region $REGION --follow"
    echo ""
    
    print_success "Lambda code deployment completed! 🎉"
    
    # Cleanup
    cleanup
}

# Trap for cleanup
trap cleanup EXIT

# Run
main

exit 0