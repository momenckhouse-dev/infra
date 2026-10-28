output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "update_kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.app : name => repo.repository_url }
}

output "github_ci_role_arn" {
  description = "Set as the AWS_CI_ROLE_ARN variable in the secure-event-api repo."
  value       = aws_iam_role.github_ci_ecr_push.arn
}

output "github_terraform_plan_role_arn" {
  value = aws_iam_role.github_terraform_plan.arn
}

output "github_terraform_apply_role_arn" {
  value = aws_iam_role.github_terraform_apply.arn
}

output "crossplane_role_arn" {
  value = aws_iam_role.crossplane.arn
}

output "crossplane_environment_config" {
  description = "Write to gitops-config/platform/crossplane/config/environment-config.yaml."
  value = yamlencode({
    apiVersion = "apiextensions.crossplane.io/v1beta1"
    kind       = "EnvironmentConfig"
    metadata   = { name = "platform-aws-settings" }
    data = {
      accountId         = local.account_id
      region            = var.region
      oidcProvider      = local.oidc_provider
      oidcProviderArn   = module.eks.oidc_provider_arn
      boundaryPolicyArn = aws_iam_policy.secureservice_boundary.arn
      crossplaneRoleArn = aws_iam_role.crossplane.arn
      bucketPrefix      = local.secureservice_prefix
    }
  })
}
