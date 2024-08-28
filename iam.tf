terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}


provider "aws" {
  region = "us-west-2"
}

locals {
  hcp_terraform_url = "https://app.terraform.io"
  hcp_audience = "aws.workload.identity" # Default audience in HCP Terraform for AWS.
}

data "tls_certificate" "provider" {
  url = local.hcp_terraform_url
}

resource "aws_iam_openid_connect_provider" "hcp_terraform" {
  url = local.hcp_terraform_url

  client_id_list = [
    local.hcp_audience,
  ]

  thumbprint_list = [
    data.tls_certificate.provider.certificates[0].sha1_fingerprint,
  ]
}

data "aws_iam_policy_document" "example_oidc_assume_role_policy" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.hcp_terraform.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.hcp_terraform_url}:aud"
      values   = [local.hcp_audience]
    }

    condition {
      test     = "StringLike"
      variable = "${local.hcp_terraform_url}:sub"
      # it's possible to use wildcards (*) to allow any PROJECT_NAME, WORKSPACE_NAME, or RUN_PHASE.
      values   = ["organization:ORG_NAME:project:PROJECT_NAME:workspace:WORKSPACE_NAME:run_phase:RUN_PHASE"]
    }
  }
}

resource "aws_iam_role" "example" {
  name               = "example"
  assume_role_policy = data.aws_iam_policy_document.example_oidc_assume_role_policy.json
}

