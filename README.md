# infra

Terraform foundation for the Secure GitOps Platform: multi-AZ VPC, EKS, ECR, GitHub OIDC roles for CI,
and the least-privilege IAM role + permissions boundary used by Crossplane.

Platform overview and step-by-step setup: [gitops-config](https://github.com/momenckhouse-dev/gitops-config).

## Status

Built and run in AWS `eu-central-1` in October 2026: EKS 1.33 with 3 × m7i-flex.large nodes, ECR, the
GitHub OIDC roles and the Crossplane role. The whole platform ran on it end to end (CI to ECR, Argo CD,
Crossplane, monitoring, an incident exercise and an approval-gated production release); the evidence
is linked from the [gitops-config README](https://github.com/momenckhouse-dev/gitops-config#status-built-deployed-and-exercised-october-2026).
The lab was destroyed on 2026-10-13 (`terraform destroy`: 92 resources, after Crossplane's buckets
and roles and the monitoring volumes were removed first), so the code and that evidence are what remain.

Two problems found while building it, both fixed in this repo:

- **AWS Free plan instance restriction.** The node group never launched: the Auto Scaling activity
  history showed `t3.large` is not free-tier eligible. The default is now `m7i-flex.large`.
- **GitHub's immutable OIDC subjects.** CI was denied `sts:AssumeRoleWithWebIdentity` because GitHub
  sends `repo:OWNER@OWNER_ID/REPO@REPO_ID:...`, not `repo:OWNER/REPO:...`. The trust policies build the
  immutable form when `github_owner_id` and `github_repo_ids` are set (`iam_github_oidc.tf`).

## What it creates

| File | Resources |
|---|---|
| `vpc.tf` | VPC across 3 AZs (public / private / intra subnets), NAT, S3 gateway endpoint, flow logs |
| `eks.tf` | EKS cluster (API access entries, IRSA, audit logs), managed node group, add-ons, EBS CSI role |
| `ecr.tf` | Immutable, scanned, KMS-encrypted ECR repositories with lifecycle rules |
| `iam_github_oidc.tf` | GitHub OIDC provider and roles: CI image push, Terraform plan, Terraform apply |
| `iam_platform.tf` | Crossplane IRSA role and the boundary every Crossplane-created role must carry |

## Apply (from a workstation)

```bash
cd terraform
cp backend.hcl.example backend.hcl            # your state bucket
cp terraform.tfvars.example terraform.tfvars  # github_org, your IP /32, admin ARN, GitHub IDs
terraform init -backend-config=backend.hcl
terraform plan -out tfplan && terraform apply tfplan
```

This is how the lab was built: from a workstation, with an IAM user (MFA enabled, root keys disabled).

## CI

`.github/workflows/terraform.yml` runs `terraform fmt`, `validate`, `tflint` and a Trivy IaC scan on
every PR. Accepted scanner findings and their compensating controls are documented in `.trivyignore`.

The workflow also has OIDC-based `plan` (on PRs) and `apply` (on merge, behind the `production-infra`
environment approval) jobs, but they are **not enabled yet**: they run only once `AWS_TF_PLAN_ROLE_ARN`
and `AWS_TF_APPLY_ROLE_ARN` are set, and they first need a backend configuration in CI (`backend.hcl`
is gitignored). Moving applies from the workstation to these jobs is the next step.

## Teardown

Delete the root Argo CD application first, so Crossplane removes the S3 buckets and IAM roles it
created (Terraform does not know about them), then run `terraform destroy`. The full order is in the
[gitops-config README](https://github.com/momenckhouse-dev/gitops-config#7-cost-and-teardown).
