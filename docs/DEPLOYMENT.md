# Deployment Workflow - Best Practice

## 📋 Overview

This project follows AWS best practices by **separating infrastructure from application code**.

## 🔄 Two-Step Deployment Process

### **Step 1: Deploy Infrastructure** 
Creates Lambda function shell, EventBridge, SNS, CloudWatch, etc.

### **Step 2: Deploy Code**
Uploads actual Python code to Lambda function

---

## 🚀 Quick Start

```bash
# 1. Deploy infrastructure (one-time or when infrastructure changes)
./scripts/deploy.sh

# 2. Deploy Lambda code (every time code changes)
./scripts/deploy-code.sh
```

---

## 📝 Detailed Workflow

### **First Time Deployment**

```bash
# Step 1: Deploy infrastructure
cd ecs-auto-restart
chmod +x scripts/*.sh
./scripts/deploy.sh
```

**What happens:**
- ✅ Creates CloudFormation stack
- ✅ Creates Lambda function with **placeholder code**
- ✅ Sets up EventBridge schedule
- ✅ Creates SNS topic (if email configured)
- ✅ Configures CloudWatch logs
- ✅ Sets environment variables
- ⏱️ Takes: ~3-4 minutes

**Output:**
```
Infrastructure Created Successfully!

⚠️  IMPORTANT: Lambda function created with placeholder code

Next Steps:
1. Deploy the actual Lambda code:
   ./scripts/deploy-code.sh
```

```bash
# Step 2: Deploy Lambda code
./scripts/deploy-code.sh
```

**What happens:**
- ✅ Packages `function/main.py`
- ✅ Uploads to **S3 bucket**
- ✅ Updates Lambda to use new S3 version
- ⏱️ Takes: ~10-30 seconds

**Output:**
```
Lambda Code Deployment Summary:
  📦 Packaged:  function/main.py
  ☁️  S3 Location: s3://my-bucket/ecs-auto-restart/lambda.zip
  🔄 Updated:   ecs-autorestart-sandbox-monitor

Lambda code deployment completed! 🎉
```

---

## 🔄 Updating Code (Daily Workflow)

When you modify `function/main.py`:

```bash
# Just deploy the code (infrastructure unchanged)
./scripts/deploy-code.sh
```

**That's it!** No need to touch CloudFormation.

---

## 🏗️ Updating Infrastructure

When you need to change infrastructure (add services, change schedule, etc.):

```bash
# Update CloudFormation stack
./scripts/deploy.sh

# Code is preserved automatically
```

---

## 📊 What Goes Where

| Component | Managed By | Changed By |
|-----------|-----------|------------|
| Lambda function (shell) | CloudFormation | `deploy.sh` |
| Lambda code (in S3) | AWS CLI | `deploy-code.sh` |
| S3 bucket reference | CloudFormation | `deploy.sh` |
| EventBridge schedule | CloudFormation | `deploy.sh` |
| SNS topic | CloudFormation | `deploy.sh` |
| Environment variables | CloudFormation | `deploy.sh` |
| CloudWatch logs | CloudFormation | `deploy.sh` |

---

## ✅ Benefits of This Approach

### **1. Separation of Concerns**
- Infrastructure team manages CloudFormation
- Dev team deploys code independently
- No conflicts!

### **2. Fast Code Updates**
- Deploy code in seconds (not minutes)
- No CloudFormation stack updates needed
- Can rollback code instantly

### **3. CI/CD Friendly**
```yaml
# Example CI/CD pipeline
on:
  push:
    paths:
      - 'function/**'
jobs:
  deploy-code:
    - run: ./scripts/deploy-code.sh
```

### **4. AWS Best Practice**
- Infrastructure as Code (CloudFormation)
- Application code separate (AWS CLI)
- Industry standard approach

---

## 🎯 Common Scenarios

### **Scenario 1: Fix a Bug in Lambda Code**

```bash
# 1. Edit function/main.py
vim function/main.py

# 2. Deploy just the code (10 seconds)
./scripts/deploy-code.sh

# 3. Test
aws lambda invoke --function-name ecs-autorestart-sandbox-monitor response.json
```

### **Scenario 2: Add More Services to Monitor**

```bash
# 1. Update CloudFormation (change ECS services parameter)
./scripts/deploy.sh

# 2. Code is automatically preserved
# 3. New environment variables applied
```

### **Scenario 3: Change Monitoring Schedule**

```bash
# 1. Update CloudFormation
./scripts/deploy.sh
# Select different schedule when prompted

# 2. Lambda code unchanged
```

---

## 🔍 Verification

### **After Infrastructure Deployment:**

```bash
# Check stack status
aws cloudformation describe-stacks \
  --stack-name ecs-autorestart-sandbox \
  --query 'Stacks[0].StackStatus'

# Should show: CREATE_COMPLETE

# Check Lambda function (will have placeholder code)
aws lambda get-function \
  --function-name ecs-autorestart-sandbox-monitor
```

### **After Code Deployment:**

```bash
# Test Lambda
aws lambda invoke \
  --function-name ecs-autorestart-sandbox-monitor \
  response.json

# Should show actual service monitoring results
cat response.json
```

---

## 📁 File Structure

```
ecs-auto-restart/
├── function/
│   └── main.py                    # Lambda code (deploy with deploy-code.sh)
├── infrastructure/
│   └── ecs_auto_restart.yaml      # Infrastructure (deploy with deploy.sh)
├── scripts/
│   ├── deploy.sh                  # Deploy infrastructure
│   └── deploy-code.sh             # Deploy code only
└── docs/
    └── DEPLOYMENT_WORKFLOW.md     # This file
```

---

## 🛠️ Troubleshooting

### **Issue: Lambda returns "Placeholder" message**

**Cause:** Code not deployed yet

**Solution:**
```bash
./scripts/deploy-code.sh
```

### **Issue: Environment variables not updated**

**Cause:** Changed in CloudFormation but not redeployed

**Solution:**
```bash
./scripts/deploy.sh  # Redeploy infrastructure
```

### **Issue: Code deployment fails - function not found**

**Cause:** Infrastructure not deployed yet

**Solution:**
```bash
./scripts/deploy.sh  # Deploy infrastructure first
./scripts/deploy-code.sh  # Then deploy code
```

---

## 🎓 Why This Is Best Practice

### **AWS Recommends:**
> "Use AWS CloudFormation to manage infrastructure resources. Use separate deployment pipelines for application code."

### **Benefits:**
1. ✅ Faster deployments (code changes = seconds)
2. ✅ Cleaner separation (infra vs code)
3. ✅ Better CI/CD integration
4. ✅ Independent rollbacks
5. ✅ Industry standard approach

### **Used By:**
- Netflix
- Amazon
- Airbnb
- Most enterprises with mature DevOps

---

## 📞 Quick Reference

```bash
# Deploy everything (first time)
./scripts/deploy.sh       # Infrastructure
./scripts/deploy-code.sh  # Code

# Update code only (daily)
./scripts/deploy-code.sh

# Update infrastructure (rare)
./scripts/deploy.sh

# Test
aws lambda invoke --function-name {name} response.json

# View logs
aws logs tail /aws/lambda/{name} --follow
```

---

**Remember:** Infrastructure = `deploy.sh`, Code = `deploy-code.sh` 🎯