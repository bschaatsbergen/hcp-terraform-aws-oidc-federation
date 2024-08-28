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
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.5"
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

# retrieve the SHA1 fingerprint of the TLS certificate protecting https://app.terraform.io.
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

# IAM policy that allows HCP Terraform to assume the IAM role at runtime.
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

# IAM role that can be assumed by HCP Terraform at runtime.
resource "aws_iam_role" "example" {
  name               = "example"
  assume_role_policy = data.aws_iam_policy_document.example_oidc_assume_role_policy.json
}

# this variable set will be shared with another HCP Terraform Workspace, so it can assume the IAM role at runtime.
resource "tfe_variable_set" "example" {
  name         = aws_iam_role.example.name
  description  = "OIDC federation configuration for ${aws_iam_role.example.arn}"
  organization = "ORG_NAME"
}

# this instructs HCP Terraform to use dynamic provider credentials for the AWS provider.
resource "tfe_variable" "tfc_aws_provider_auth" {
  key             = "TFC_AWS_PROVIDER_AUTH"
  value           = "true"
  category        = "env"
  variable_set_id = tfe_variable_set.example.id
}

# this variable will be used by the HCP Terraform Workspace to assume the IAM role at runtime.
resource "tfe_variable" "tfc_example_role_arn" {
  sensitive       = true
  key             = "TFC_AWS_RUN_ROLE_ARN"
  value           = aws_iam_role.example.arn
  category        = "env"
  variable_set_id = tfe_variable_set.example.id
}

# share the variable set with another HCP Terraform Workspace
resource "tfe_workspace_variable_set" "example" {
  variable_set_id = tfe_variable_set.example.id
  workspace_id    = "ws-XXXXXXXXXXXXXXX"
}

