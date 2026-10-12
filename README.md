# infra

Terraform foundation for the Secure GitOps Platform: multi-AZ VPC, EKS, ECR, GitHub OIDC roles for CI,
and the least-privilege IAM role + permissions boundary used by Crossplane.

Platform overview and step-by-step setup: [gitops-config](https://github.com/momenckhouse-dev/gitops-config).

## What it creates

| File | Resources |
|---|---|
| `vpc.tf` | VPC across 3 AZs (public / private / intra subnets), NAT, S3 gateway endpoint, flow logs |
| `eks.tf` | EKS cluster (API access entries, IRSA, audit logs), managed node group, add-ons, EBS CSI role |
| `ecr.tf` | Immutable, scanned, KMS-encrypted ECR repositories with lifecycle rules |
| `iam_github_oidc.tf` | GitHub OIDC provider and roles: CI image push, Terraform plan, Terraform apply |
| `iam_platform.tf` | Crossplane IRSA role and the boundary every Crossplane-created role must carry |

## First apply (from a workstation)

```bash
cd terraform
cp backend.hcl.example backend.hcl            # your state bucket
cp terraform.tfvars.example terraform.tfvars  # github_org, your IP /32, admin role ARN
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
```

After that, changes go through pull requests: `.github/workflows/terraform.yml` runs fmt, validate,
tflint and a Trivy IaC scan on every PR, a read-only plan once `AWS_TF_PLAN_ROLE_ARN` is set, and
applies on merge only after approval of the `production-infra` environment.

Accepted scanner findings and their compensating controls are documented in `.trivyignore`.
