# ECS Auto-Restart Lambda

Automated monitoring and restart solution for AWS ECS services using Lambda, EventBridge, and CloudFormation.

## Overview

This solution automatically monitors ECS services and restarts them if they have zero running tasks. Perfect for preventing extended downtime from accidentally stopped services.

## Architecture

```
EventBridge (Schedule) 
    ↓
Lambda Function (Python 3.11)
    ↓
ECS API (Monitor & Restart)
    ↓
SNS (Email Alerts)
    ↓
CloudWatch (Logs & Alarms)
```

## Project Structure

```
ecs-auto-restart/
├── function/
│   └── main.py                          # Lambda function code
├── infrastructure/
│   └── ecs_auto_restart.yaml            # CloudFormation template
├── scripts/
│   └── deploy.sh                        # Deployment script
├── docs/
│   ├── DEPLOYMENT.md                    # Detailed deployment guide
│   └── COMMANDS.md                      # CLI commands reference
├── .gitignore                           # Git ignore rules
└── README.md                            # This file
```

## Quick Start

### Prerequisites

- AWS CLI configured
- Python 3.11+
- IAM role for Lambda with ECS permissions
- S3 bucket for Lambda deployment packages

### Deploy

```bash
# Make script executable
chmod +x scripts/deploy.sh

# Run deployment
./scripts/deploy.sh
```

The script will:
1. ✅ Package Lambda code
2. ✅ Upload to S3
3. ✅ Deploy CloudFormation stack
4. ✅ Configure EventBridge schedule
5. ✅ Set up SNS alerts (optional)

## Features

- **Multi-Service Monitoring**: Monitor multiple ECS services in one deployment
- **Automated Restart**: Detects services with 0 tasks and restarts them
- **Email Alerts**: Get notified when services are restarted
- **Configurable Schedule**: 15min, 30min, 1hr, or 2hr intervals
- **Debug Logging**: Comprehensive logs for troubleshooting
- **CloudWatch Alarms**: Alert on Lambda function errors
- **Production Ready**: Proper separation of code and infrastructure

## Configuration

Edit these parameters during deployment:

| Parameter | Description | Default |
|-----------|-------------|---------|
| Stack Name | CloudFormation stack name | `ecs-autorestart-prod` |
| Region | AWS region | `ap-southeast-1` |
| S3 Bucket | Bucket for Lambda code | `{stack}-lambda-{account}` |
| IAM Role ARN | Lambda execution role | (required) |
| ECS Cluster | Cluster to monitor | (required) |
| Service Names | Comma-separated services | (required) |
| Desired Count | Tasks to start on restart | `1` |
| Schedule | Check frequency | `rate(30 minutes)` |
| Alert Email | Email for notifications | (optional) |
| Environment | Environment tag | `production` |

## Monitoring

### View Lambda Logs

```bash
aws logs tail /aws/lambda/{stack-name}-monitor \
  --region {region} \
  --follow
```

### Test Lambda Manually

```bash
aws lambda invoke \
  --function-name {stack-name}-monitor \
  --region {region} \
  response.json
```

### Check Service Status

```bash
aws ecs describe-services \
  --cluster {cluster-name} \
  --services {service-name} \
  --region {region}
```

## Cost

Approximately **$0.14/month** for 3 services:
- Lambda: ~$0.01
- CloudWatch Logs: ~$0.03
- CloudWatch Alarms: ~$0.10
- SNS: Free tier
- EventBridge: Free tier

## 🔄 Updates

To update Lambda code:

```bash
# 1. Modify function/main.py
# 2. Run deployment script
./scripts/deploy.sh

# Or update stack manually
aws cloudformation update-stack \
  --stack-name {stack-name} \
  --template-body file://infrastructure/ecs_auto_restart.yaml \
  --parameters ParameterKey=LambdaS3Bucket,UsePreviousValue=true ...
```

## Cleanup

```bash
# Delete CloudFormation stack
aws cloudformation delete-stack \
  --stack-name {stack-name} \
  --region {region}

# Delete S3 bucket (optional)
aws s3 rb s3://{bucket-name} --force
```

## Documentation

- [Deployment Guide](docs/DEPLOYMENT.md) - Detailed deployment instructions
- [Commands Reference](docs/COMMANDS.md) - All CLI commands

## Security

- ✅ Least-privilege IAM permissions
- ✅ Resource-based Lambda policies
- ✅ No hardcoded credentials
- ✅ Encrypted CloudWatch Logs
- ✅ SNS encryption in transit

## Troubleshooting

### Lambda Can't Find Service
- Verify cluster and service names are correct
- Check IAM role has ECS permissions

### Not Receiving Emails
- Confirm SNS subscription in email
- Check spam folder
- Verify email address in parameters

### Service Not Restarting
- Check Lambda execution logs
- Verify service has 0 running AND 0 desired count
- Ensure IAM role has `ecs:UpdateService` permission

## Author

Vin Lonje

---

**Last Updated:** January 2026  
**Version:** 2.0 (Improved Structure)