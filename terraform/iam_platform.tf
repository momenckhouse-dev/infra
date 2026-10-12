locals {
  oidc_provider        = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  secureservice_prefix = "cp-secureservice-"
  bucket_arn_pattern   = "arn:aws:s3:::${local.secureservice_prefix}*"
  role_arn_pattern     = "arn:aws:iam::${local.account_id}:role/${local.secureservice_prefix}*"
}

# Ceiling for every workload role Crossplane creates: object access to SecureService buckets only.
data "aws_iam_policy_document" "secureservice_boundary" {
  statement {
    sid       = "ArchiveObjects"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [local.bucket_arn_pattern, "${local.bucket_arn_pattern}/*"]
  }

  statement {
    sid       = "S3ManagedKms"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "secureservice_boundary" {
  name   = "${var.project_name}-secureservice-boundary"
  policy = data.aws_iam_policy_document.secureservice_boundary.json
}

# Crossplane provider-aws-s3 / provider-aws-iam, via IRSA.
data "aws_iam_policy_document" "crossplane_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values = [
        "system:serviceaccount:crossplane-system:provider-aws-s3",
        "system:serviceaccount:crossplane-system:provider-aws-iam",
      ]
    }
  }
}

data "aws_iam_policy_document" "crossplane" {
  statement {
    sid = "ManageSecureServiceBuckets"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:GetBucket*",
      "s3:PutBucket*",
      "s3:DeleteBucketPolicy",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetAccelerateConfiguration",
      "s3:GetReplicationConfiguration",
    ]
    resources = [local.bucket_arn_pattern]
  }

  statement {
    sid       = "CreateBoundedWorkloadRoles"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = [local.role_arn_pattern]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.secureservice_boundary.arn]
    }
  }

  statement {
    sid = "ManageWorkloadRoles"
    actions = [
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = [local.role_arn_pattern]
  }

  statement {
    sid       = "NeverRemoveTheBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "crossplane" {
  name               = "${var.project_name}-crossplane-aws"
  assume_role_policy = data.aws_iam_policy_document.crossplane_trust.json
}

resource "aws_iam_role_policy" "crossplane" {
  name   = "secureservice-guardrailed"
  role   = aws_iam_role.crossplane.id
  policy = data.aws_iam_policy_document.crossplane.json
}
