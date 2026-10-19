# Terraform Infrastructure for Job Scheduler Platform

This directory contains the Terraform configuration to provision the complete AWS infrastructure for the Job Scheduler Platform.

**For detailed deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md)**

## Architecture

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

## Quick Start

### Prerequisites
- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- AWS account with permissions for VPC, RDS, ElastiCache, ECS, ECR, IAM, ALB, Secrets Manager, S3, DynamoDB, KMS, CloudWatch, SNS, Budgets

### One-time Backend Setup (per AWS account)

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket job-scheduler-terraform-state-burhaan \
  --region ap-south-2 \
  --create-bucket-configuration LocationConstraint=ap-south-2

aws s3api put-bucket-versioning --bucket job-scheduler-terraform-state-burhaan --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket job-scheduler-terraform-state-burhaan --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-locks-job-scheduler \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-2
```

### Initialize & Deploy

```bash
cd terraform

# Set required password
export TF_VAR_db_password='your-secure-password'

# Development
terraform init -reconfigure -backend-config=backend-dev.hcl
terraform apply -var-file=dev.tfvars

# Production (separate state)
terraform init -reconfigure -backend-config=backend-prod.hcl
terraform apply -var-file=prod.tfvars
```

### Required Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `db_password` | Database master password (stored in Secrets Manager as DSN) | **Yes** |

```bash
export TF_VAR_db_password='...'   # never commit this value
```

There is intentionally NO Redis password: ElastiCache runs without AUTH
(the Go client has no TLS support) and is isolated by security group in
private subnets.

### Outputs

After apply, key outputs:
- `alb_dns_name` - ALB DNS name for API access
- `api_ecr_url`, `scheduler_ecr_url`, `worker_ecr_url` - ECR repository URLs for Docker pushes
- `db_endpoint` - RDS endpoint (sensitive)
- `redis_endpoint` - ElastiCache Redis endpoint (sensitive)
- `deploy_role_arn` - GitHub Actions OIDC role ARN (add to GitHub secrets)
- `sns_topic_arn` - SNS topic for alarm notifications

## Modules

- `kms` - KMS keys for RDS & Redis encryption (created first, no dependencies)
- `networking` - VPC, subnets, IGW, route tables, security groups, S3 gateway endpoint
- `rds` - PostgreSQL RDS instance in private subnets
- `elasticache` - Redis ElastiCache cluster in private subnets
- `ecr-iam` - ECR repositories and IAM roles (execution, task roles with KMS decrypt)
- `github-oidc` - GitHub Actions OIDC deploy role for CI/CD
- `ecs-alb` - ECS cluster, Fargate services, ALB, autoscaling, CloudWatch alarms

## Cost profile (personal project, ~$60/mo dev)

Deliberately lean: ECS tasks run in **public subnets** on **Fargate Spot**,
with **no NAT gateway and no interface VPC endpoints** (those two alone would
add ~$110/mo). RDS/Redis stay in private subnets behind security groups.
First-year accounts also get the RDS `db.t4g.micro` free tier (~−$15/mo).

| Service | $/mo |
|---|---|
| ALB | ~18 |
| Fargate Spot (3× 0.25vCPU/0.5GB) | ~9 |
| ElastiCache `cache.t4g.micro` | ~16 |
| RDS `db.t4g.micro` + 20 GB | ~17 (free-tier yr 1) |
| KMS, Secrets, ECR, logs | ~3 |

## Secrets Management

The database DSN is stored in AWS Secrets Manager as a ready-to-use URL
(the app expects `JOB_SCHEDULER_DB_DSN` to be a `postgres://` URL, not JSON):

- `${environment}/job-scheduler/db-password` → `postgres://user:pass@host:5432/db?sslmode=require`

ECS task definitions reference it via `valueFrom` (secret ARN), so no
plaintext credentials appear in task definitions or Dockerfiles.

## CI/CD Integration

The GitHub Actions workflow includes a `terraform-plan` job that runs on PRs modifying `.tf` files. Requires:
- `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in GitHub secrets
- OIDC role for production deployments (configured separately)

## Destroy

```bash
terraform destroy -var-file=dev.tfvars
# or
terraform destroy -var-file=prod.tfvars
```

**Warning**: This will destroy ALL resources including RDS data. Ensure you have backups!