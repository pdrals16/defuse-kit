terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Owner = "geral"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  aws_account_id                   = data.aws_caller_identity.current.account_id
}

resource "aws_iam_role" "glue_transactional_role" {
  name                = "glue_transactional_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })
  
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"]
}

resource "aws_iam_policy" "glue_s3" {
  policy      = <<-EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::brass-bucket-defuse-kit/dms/transactional/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  role       = aws_iam_role.glue_transactional_role.name
  policy_arn = aws_iam_policy.glue_s3.arn
}


resource "aws_glue_catalog_database" "transactional_glue_database" {
  name = "brass_transactional"
}

resource "aws_glue_crawler" "transactional_glue_crawler" {
  database_name = aws_glue_catalog_database.transactional_glue_database.name
  name          = "transactional_glue_crawler"
  role          = aws_iam_role.glue_transactional_role.arn

  configuration = <<EOF
    {
      "Version":1.0,
      "Grouping": {
        "TableGroupingPolicy": "CombineCompatibleSchemas"
      }
    }
  EOF
    

  s3_target {
    path = "s3://brass-bucket-defuse-kit/dms/transactional/address/"
  }

  s3_target {
    path = "s3://brass-bucket-defuse-kit/dms/transactional/orders/"
  }

  s3_target {
    path = "s3://brass-bucket-defuse-kit/dms/transactional/orders_status_history/"
  }

  s3_target {
    path = "s3://brass-bucket-defuse-kit/dms/transactional/supplier/"
  }
}

