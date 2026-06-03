terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" {
  region = var.region
}

locals {
  loki_chunks = "${var.prefix}-loki-chunks"
  loki_ruler  = "${var.prefix}-loki-ruler"
  loki_admin  = "${var.prefix}-loki-admin"
  tempo       = "${var.prefix}-tempo-traces"
  thanos      = "${var.prefix}-thanos-metrics"
  buckets     = [local.loki_chunks, local.loki_ruler, local.loki_admin, local.tempo, local.thanos]
}

resource "aws_s3_bucket" "b" {
  for_each = toset(local.buckets)
  bucket   = each.value
}

resource "aws_s3_bucket_versioning" "v" {
  for_each = aws_s3_bucket.b
  bucket   = each.value.id
  versioning_configuration { status = var.enable_versioning ? "Enabled" : "Suspended" }
}

resource "aws_s3_bucket_lifecycle_configuration" "lc" {
  for_each = aws_s3_bucket.b
  bucket   = each.value.id

  rule {
    id     = "expire"
    status = "Enabled"

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.retention_days
    }
  }
}

# Example IAM policy (attach to IRSA role used by Loki/Tempo/Thanos)
data "aws_iam_policy_document" "objstore" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [for b in aws_s3_bucket.b : b.arn]
  }
  statement {
    actions   = ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:AbortMultipartUpload","s3:ListMultipartUploadParts"]
    resources = [for b in aws_s3_bucket.b : "${b.arn}/*"]
  }
}

output "iam_policy_json" {
  value = data.aws_iam_policy_document.objstore.json
}

output "bucket_names" {
  value = {
    loki_chunks = local.loki_chunks
    loki_ruler  = local.loki_ruler
    loki_admin  = local.loki_admin
    tempo       = local.tempo
    thanos      = local.thanos
  }
}


# -----------------------------
# IRSA role (optional, recommended)
# -----------------------------

locals {
  oidc_url_noscheme = replace(var.oidc_provider_url, "https://", "")
  irsa_subjects     = [for sa in var.service_accounts : "system:serviceaccount:${var.namespace}:${sa}"]
  irsa_role_name    = var.irsa_role_name != "" ? var.irsa_role_name : "${var.prefix}-observability-objstore"
}

data "aws_iam_policy_document" "irsa_assume" {
  count = var.create_irsa_role && var.oidc_provider_arn != "" && var.oidc_provider_url != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_noscheme}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_url_noscheme}:sub"
      values   = local.irsa_subjects
    }
  }
}

resource "aws_iam_role" "irsa" {
  count              = length(data.aws_iam_policy_document.irsa_assume) > 0 ? 1 : 0
  name               = local.irsa_role_name
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[0].json
}

resource "aws_iam_policy" "objstore" {
  count  = length(data.aws_iam_policy_document.irsa_assume) > 0 ? 1 : 0
  name   = "${local.irsa_role_name}-policy"
  policy = data.aws_iam_policy_document.objstore.json
}

resource "aws_iam_role_policy_attachment" "objstore" {
  count      = length(data.aws_iam_policy_document.irsa_assume) > 0 ? 1 : 0
  role       = aws_iam_role.irsa[0].name
  policy_arn = aws_iam_policy.objstore[0].arn
}

output "irsa_role_arn" {
  value       = length(aws_iam_role.irsa) > 0 ? aws_iam_role.irsa[0].arn : ""
  description = "IAM role ARN for IRSA (set AWS_IRSA_ROLE_ARN in your install env)."
}
