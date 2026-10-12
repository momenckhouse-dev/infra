resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # Immutable subjects embed numeric IDs so a deleted-and-recreated repo with the same name can't assume these roles.
  github_repo_subject = {
    for repo in [var.app_repo, var.infra_repo] : repo => (
      var.github_owner_id != "" && lookup(var.github_repo_ids, repo, "") != ""
      ? "repo:${var.github_org}@${var.github_owner_id}/${repo}@${var.github_repo_ids[repo]}"
      : "repo:${var.github_org}/${repo}"
    )
  }
}

# Trust policy factory: one role per (repo, ref/environment) subject, never a wildcard org.
data "aws_iam_policy_document" "github_trust" {
  for_each = {
    ci_ecr_push     = "${local.github_repo_subject[var.app_repo]}:ref:refs/heads/main"
    terraform_plan  = "${local.github_repo_subject[var.infra_repo]}:pull_request"
    terraform_apply = "${local.github_repo_subject[var.infra_repo]}:environment:production-infra"
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}

# --- CI: push images to ECR only -------------------------------------------------
resource "aws_iam_role" "github_ci_ecr_push" {
  name                 = "${var.project_name}-gha-ecr-push"
  assume_role_policy   = data.aws_iam_policy_document.github_trust["ci_ecr_push"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushToServiceRepositories"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for repo in aws_ecr_repository.app : repo.arn]
  }
}

resource "aws_iam_role_policy" "github_ci_ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_ci_ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# --- Infra repo: read-only plan on pull requests ---------------------------------
resource "aws_iam_role" "github_terraform_plan" {
  name               = "${var.project_name}-gha-tf-plan"
  assume_role_policy = data.aws_iam_policy_document.github_trust["terraform_plan"].json
}

resource "aws_iam_role_policy_attachment" "terraform_plan_readonly" {
  role       = aws_iam_role.github_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "terraform_state_read" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.terraform_state_bucket}", "arn:aws:s3:::${var.terraform_state_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "terraform_plan_state" {
  name   = "terraform-state-read"
  role   = aws_iam_role.github_terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_state_read.json
}

# --- Infra repo: apply, only from the approval-gated environment -----------------
resource "aws_iam_role" "github_terraform_apply" {
  name               = "${var.project_name}-gha-tf-apply"
  assume_role_policy = data.aws_iam_policy_document.github_trust["terraform_apply"].json
}

resource "aws_iam_role_policy_attachment" "terraform_apply" {
  for_each   = toset(var.terraform_apply_policy_arns)
  role       = aws_iam_role.github_terraform_apply.name
  policy_arn = each.value
}
