# Job Scheduler Platform - Terraform Deployment Guide

This guide provides step-by-step instructions to deploy the Job Scheduler Platform infrastructure on AWS using Terraform.

---

## 📋 Prerequisites

### Required Tools
| Tool | Version | Installation |
|------|---------|--------------|
| **Terraform** | >= 1.5 | [Download](https://developer.hashicorp.com/terraform/downloads) |
| **AWS CLI** | >= 2.0 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| **Git** | Any | [Download](https://git-scm.com/) |

### AWS Account Requirements
- AWS account with permissions for: VPC, RDS, ElastiCache, ECS, ECR, IAM, ALB, Secrets Manager, S3, DynamoDB, CloudWatch, SNS, Budgets, KMS
- AWS credentials configured locally (`aws configure`) or via environment variables
- **Region**: `ap-south-2` (Mumbai) — change in `variables.tf` if needed

### GitHub Repository (for CI/CD)
- Repository: `BurhaanAshraf/job-scheduler-platform` (update in `variables.tf` if different)
- GitHub Actions OIDC provider will be created automatically

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        VPC (10.x.0.0/16)                     │
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │   Public Subnets    │    │      Private Subnets        │ │
│  │  (10.x.1.0/24,      │    │  (10.x.11.0/24,             │ │
│  │   10.x.2.0/24)      │    │   10.x.12.0/24)             │ │
│  │                     │    │                             │ │
│  │  ALB (port 80/443)  │    │  ECS Tasks (API, Scheduler, │ │
│  │                     │    │  Worker)                    │ │
│  │                     │    │  RDS PostgreSQL             │ │
│  │                     │    │  ElastiCache Redis          │ │
│  └─────────────────────┘    └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Cost-lean design**: ECS tasks run in **public subnets on Fargate Spot** (no NAT Gateway, no VPC Interface Endpoints — saves ~$110/mo).

---

## 🚀 Quick Start

### 1. Clone & Navigate
```bash
git clone https://github.com/BurhaanAshraf/job-scheduler-platform.git
cd job-scheduler-platform/terraform
```

### 2. Create Backend Resources (One-time Setup)
Run **once per AWS account** before first deployment:

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket job-scheduler-terraform-state-burhaan \
  --region ap-south-2 \
  --create-bucket-configuration LocationConstraint=ap-south-2

# Enable versioning & encryption
aws s3api put-bucket-versioning \
  --bucket job-scheduler-terraform-state-burhaan \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket job-scheduler-terraform-state-burhaan \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-locks-job-scheduler \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-2
```

> **Note**: Wait ~30 seconds for DynamoDB table to become ACTIVE.

### 3. Set Database Password (Required)
```bash
# Set as environment variable (never commit to files!)
export TF_VAR_db_password='your-super-secure-password-here'
```

### 4. Initialize & Deploy

#### For Development Environment
```bash
# Initialize with dev backend
terraform init -reconfigure -backend-config=backend-dev.hcl

# Preview changes
terraform plan -var-file=dev.tfvars

# Deploy
terraform apply -var-file=dev.tfvars
```

#### For Production Environment
```bash
# Initialize with prod backend (separate state file!)
terraform init -reconfigure -backend-config=backend-prod.hcl

# Preview changes
terraform plan -var-file=prod.tfvars

# Deploy
terraform apply -var-file=prod.tfvars
```

---

## ⚙️ Configuration Reference

### Environment Variables
| Variable | Description | Required |
|----------|-------------|----------|
| `TF_VAR_db_password` | Database master password | **Yes** |
| `AWS_PROFILE` | AWS CLI profile name | No (uses default) |
| `AWS_REGION` | Override region | No (default: ap-south-2) |

### Key Terraform Variables (in `dev.tfvars` / `prod.tfvars`)

| Variable | Dev Default | Prod Default | Description |
|----------|-------------|--------------|-------------|
| `environment` | `dev` | `prod` | Environment name |
| `vpc_cidr` | `10.1.0.0/16` | `10.0.0.0/16` | VPC CIDR block |
| `db_instance_class` | `db.t4g.micro` | `db.t4g.micro` | RDS instance size |
| `db_allocated_storage` | `20` | `50` | RDS storage (GB) |
| `redis_node_type` | `cache.t4g.micro` | `cache.t4g.small` | ElastiCache node size |
| `api_desired_count` | `1` | `2` | API service tasks |
| `worker_desired_count` | `1` | `2` | Initial worker tasks |
| `worker_min_count` | `1` | `2` | Worker autoscaling min |
| `worker_max_count` | `2` | `6` | Worker autoscaling max |
| `image_tag` | `dev-latest` | `latest` | Docker image tag |
| `monthly_budget_limit_usd` | `15` | `40` | Budget alarm threshold |

### Optional Variables
```hcl
# In tfvars file or via -var flags
acm_certificate_arn = "arn:aws:acm:ap-south-2:123456789012:certificate/..."  # For HTTPS
# sns_topic_arn = "arn:aws:sns:ap-south-2:123456789012:job-scheduler-alarms"  # External SNS
```

---

## 📤 Outputs (After Apply)

| Output | Description |
|--------|-------------|
| `alb_dns_name` | ALB DNS name for API access |
| `api_ecr_url` | ECR repository URL for API image |
| `scheduler_ecr_url` | ECR repository URL for Scheduler image |
| `worker_ecr_url` | ECR repository URL for Worker image |
| `db_endpoint` | RDS endpoint (sensitive) |
| `redis_endpoint` | ElastiCache Redis endpoint (sensitive) |
| `deploy_role_arn` | GitHub Actions OIDC role ARN (add to GitHub secrets) |
| `sns_topic_arn` | SNS topic for alarm notifications |

---

## 🔐 Secrets Management

The database connection string is stored in **AWS Secrets Manager** as a ready-to-use DSN:

```
Secret Name:  <environment>/job-scheduler/db-password
Secret Value: postgres://user:pass@host:5432/db?sslmode=require
```

ECS task definitions reference it via `valueFrom` (secret ARN) — **no plaintext credentials** in task definitions or Docker images.

---

## 🔄 CI/CD Integration (GitHub Actions)

### 1. Add OIDC Role to GitHub Secrets
After first deploy, copy the `deploy_role_arn` output and add to GitHub repository secrets:
- **Name**: `AWS_DEPLOY_ROLE_ARN`
- **Value**: `arn:aws:iam::<account-id>:role/<environment>-github-deploy`

### 2. Workflow Permissions
The GitHub Actions workflow (`.github/workflows/deploy.yml`) needs:
- `id-token: write` permission for OIDC
- `contents: read` permission for checkout

### 3. Deploy on Push to Main
The workflow automatically:
1. Runs `terraform plan` on PRs
2. On merge to `main`: builds Docker images, pushes to ECR, runs `terraform apply`

---

## 📊 Monitoring & Alerts

### CloudWatch Alarms (Created Automatically)
| Alarm | Threshold | Action |
|-------|-----------|--------|
| Job Failure Rate | >5 failures/5min | SNS → Email/PagerDuty |
| API 5xx Rate | >5 errors/5min | SNS |
| Queue Depth | >100 for 5min | SNS |
| Task Crash | Any non-zero exit | SNS (EventBridge) |
| Monthly Cost | >80% actual, >100% forecast | SNS |

### Subscribe to Alerts
```bash
# Replace with your email
aws sns subscribe \
  --topic-arn <sns_topic_arn_from_outputs> \
  --protocol email \
  --notification-endpoint you@example.com
```

Then confirm the subscription via email.

---

## 🧪 Testing the Deployment

### 1. Verify ALB Health
```bash
curl -f http://<alb_dns_name>/healthz
# Should return 200 OK
```

### 2. Check ECS Services
```bash
aws ecs describe-services \
  --cluster <environment>-job-scheduler \
  --services <environment>-job-scheduler-api \
  --region ap-south-2
```

### 3. View Logs
```bash
# API logs
aws logs tail /ecs/<environment>-job-scheduler-api --follow --region ap-south-2

# Scheduler logs
aws logs tail /ecs/<environment>-job-scheduler-scheduler --follow --region ap-south-2

# Worker logs
aws logs tail /ecs/<environment>-job-scheduler-worker --follow --region ap-south-2
```

---

## 💰 Cost Estimation

| Service | Dev (~$) | Prod (~$) | Notes |
|---------|----------|-----------|-------|
| ALB | 18 | 18 | ~$0.025/hr |
| Fargate Spot (3× 0.25vCPU/0.5GB) | 9 | 18 | ~70% cheaper than On-Demand |
| ElastiCache | 16 | 25 | Single node; cluster mode not used |
| RDS (db.t4g.micro) | 17* | 17* | *Free tier Year 1: ~$0 |
| KMS, Secrets, ECR, Logs | 3 | 5 | |
| **Total/Month** | **~$63** | **~$83** | |

> **First-year AWS accounts**: RDS `db.t4g.micro` is free (~$15/mo savings).

---

## 🗑️ Destroy Infrastructure

```bash
# Development
terraform destroy -var-file=dev.tfvars

# Production
terraform init -reconfigure -backend-config=backend-prod.hcl
terraform destroy -var-file=prod.tfvars
```

⚠️ **Warning**: This destroys ALL resources including RDS data. Ensure you have backups!

---

## 🔧 Troubleshooting

### Common Issues

| Error | Solution |
|-------|----------|
| `S3 bucket does not exist` | Run backend creation commands (Step 2) |
| `DynamoDB table not found` | Wait for table to become ACTIVE, or re-run create-table |
| `Invalid DB password` | Ensure `TF_VAR_db_password` is set and meets RDS requirements |
| `OIDC provider already exists` | Set `create_oidc_provider = false` in `github-oidc` module call |
| `ECS tasks cannot pull images` | Verify ECR lifecycle policy allows images; check IAM execution role |
| `Tasks stuck in PENDING` | Check CloudWatch Logs for container startup errors |

### Debug Commands
```bash
# View Terraform state
terraform state list

# Show specific resource
terraform state show module.rds.aws_db_instance.main

# Refresh state
terraform refresh -var-file=dev.tfvars

# Force unlock (if stuck)
terraform force-unlock <LOCK_ID>
```

---

## 📁 Project Structure

```
terraform/
├── main.tf                 # Root module, providers, module composition
├── variables.tf            # Input variables with defaults
├── outputs.tf              # Output values
├── versions.tf             # Provider versions & S3 backend config
├── dev.tfvars              # Development environment variables
├── prod.tfvars             # Production environment variables
├── backend-dev.hcl         # Dev backend config (state key: dev/)
├── backend-prod.hcl        # Prod backend config (state key: prod/)
├── README.md               # This file
└── modules/
    ├── kms/                # KMS keys for RDS & Redis encryption
    ├── networking/         # VPC, subnets, SGs, IGW, S3 endpoint
    ├── rds/                # PostgreSQL RDS instance
    ├── elasticache/        # Redis ElastiCache cluster
    ├── ecr-iam/            # ECR repos + IAM roles (execution, task)
    ├── github-oidc/        # GitHub Actions OIDC deploy role
    └── ecs-alb/            # ECS cluster, Fargate services, ALB, autoscaling, alarms
```

---

## 🤝 Contributing

1. Make changes to Terraform files
2. Run `terraform fmt` to format
3. Run `terraform validate` to check syntax
4. Create PR — GitHub Actions will run `terraform plan`
5. On merge, deployment runs automatically

---

## 📄 License

MIT License — feel free to use and modify for your own projects.

---

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/BurhaanAshraf/job-scheduler-platform/issues)
- **AWS Docs**: [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- **Terraform Docs**: [Terraform CLI](https://developer.hashicorp.com/terraform/cli)