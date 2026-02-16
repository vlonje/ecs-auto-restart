# Environment Configuration Files

## 📋 Overview

This directory contains environment-specific configuration files for deploying the ECS Auto-Restart solution to different environments.

## 📁 Structure

```
config/
├── production.env    # Production environment
├── staging.env       # Staging environment
├── sandbox.env       # Sandbox/development environment
└── README.md         # This file
```

## 🚀 Usage

### Deploy to a specific environment:

```bash
# Deploy to production
./scripts/deploy-env.sh production

# Deploy to staging
./scripts/deploy-env.sh staging

# Deploy to sandbox
./scripts/deploy-env.sh sandbox
```

## 📝 Configuration Variables

Each `.env` file contains:

| Variable | Description | Example |
|----------|-------------|---------|
| `STACK_NAME` | CloudFormation stack name | `ecs-autorestart-prod` |
| `AWS_REGION` | AWS region | `ap-southeast-1` |
| `S3_BUCKET` | S3 bucket for Lambda code | `my-lambda-bucket` |
| `S3_KEY` | S3 key for Lambda zip | `ecs-auto-restart/lambda.zip` |
| `LAMBDA_ROLE_ARN` | IAM role ARN for Lambda | `arn:aws:iam::123:role/name` |
| `ECS_CLUSTER_NAME` | ECS cluster to monitor | `vin-prod` |
| `ECS_SERVICE_NAMES` | Services to monitor (comma-separated) | `service1,service2` |
| `DESIRED_TASK_COUNT` | Task count when restarting | `1` |
| `MONITORING_SCHEDULE` | Check frequency | `rate(30 minutes)` |
| `ALERT_EMAIL` | Email for notifications | `ops@company.com` |
| `ENVIRONMENT` | Environment tag | `production` |

## 🔧 Creating a New Environment

1. Copy an existing config file:
   ```bash
   cp config/production.env config/new-env.env
   ```

2. Edit the new file with your values:
   ```bash
   vim config/new-env.env
   ```

3. Deploy:
   ```bash
   ./scripts/deploy-env.sh new-env
   ```

## ⚠️ Important Notes

### **DO NOT commit sensitive data!**

Add to `.gitignore`:
```
# Sensitive configs
config/*.local.env
config/*-credentials.env
```

### **Naming Convention**

- Use lowercase: `production.env` not `Production.env`
- Use hyphens for multi-word: `pre-production.env`
- Match environment tags: File `staging.env` should have `ENVIRONMENT="staging"`

### **S3 Buckets**

- Each environment should have its own S3 bucket
- Or use different prefixes in the same bucket:
  ```
  S3_BUCKET="my-company-lambda"
  S3_KEY="ecs-autorestart/production/lambda.zip"  # production
  S3_KEY="ecs-autorestart/staging/lambda.zip"     # staging
  ```

## 🔍 Validation

The deployment script validates all required variables before deployment:

```bash
./scripts/deploy-env.sh production
```

Will check:
- ✅ Config file exists
- ✅ All required variables are set
- ✅ AWS credentials are valid
- ✅ Shows configuration summary for review

## 📊 Example Configurations

### Minimal (Single Service)

```bash
STACK_NAME="ecs-autorestart-prod"
AWS_REGION="us-east-1"
S3_BUCKET="my-lambda-bucket"
S3_KEY="lambda.zip"
LAMBDA_ROLE_ARN="arn:aws:iam::123456789012:role/lambda-role"
ECS_CLUSTER_NAME="production"
ECS_SERVICE_NAMES="api-service"
DESIRED_TASK_COUNT="2"
MONITORING_SCHEDULE="rate(30 minutes)"
ALERT_EMAIL="ops@company.com"
ENVIRONMENT="production"
```

### Multi-Service

```bash
ECS_SERVICE_NAMES="api,worker,scheduler,consumer"
DESIRED_TASK_COUNT="3"
```

### High Availability

```bash
MONITORING_SCHEDULE="rate(15 minutes)"
DESIRED_TASK_COUNT="5"
```

### Cost Optimized

```bash
MONITORING_SCHEDULE="rate(2 hours)"
DESIRED_TASK_COUNT="1"
ALERT_EMAIL=""  # Disable email alerts
```

## 🔄 Updating Configuration

### Option 1: Edit config file and redeploy

```bash
# 1. Edit config
vim config/production.env

# 2. Redeploy (will update existing stack)
./scripts/deploy-env.sh production
```

### Option 2: Direct CloudFormation update

```bash
aws cloudformation update-stack \
  --stack-name ecs-autorestart-prod \
  --use-previous-template \
  --parameters ParameterKey=ECSServiceNames,ParameterValue="new-service-list" \
  ...
```

⚠️ **Always update the config file to match!**

## 📚 Related Files

- `../scripts/deploy-env.sh` - Deployment script that uses these configs
- `../infrastructure/ecs_auto_restart.yaml` - CloudFormation template
- `../function/main.py` - Lambda function code