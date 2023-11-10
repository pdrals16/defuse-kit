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

# Configure state.tfstate backend
terraform {
  backend "s3" {
    bucket                  = "terraform-backend-defuse-kit"
    key                     = "state.tfstate"
    region                  = "us-east-2"
  }
}

# VPC 
data "aws_vpc" "selected" {
  default = true
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

# S3 Buckets
module "brass_bucket" {
  source = "./modules/s3"
  bucket_name = "brass"
}

module "bronze_bucket" {
  source = "./modules/s3"
  bucket_name = "bronze"
}

# ECR - WebCrawler e FakeData
data "aws_ecr_authorization_token" "token" {
}

provider "docker" {
  registry_auth {
    address  = "${local.aws_account_id}.dkr.ecr.us-east-2.amazonaws.com"
    username = data.aws_ecr_authorization_token.token.user_name
    password = data.aws_ecr_authorization_token.token.password
  }
}

module "docker_image_webcrawler_condor" {
  source = "terraform-aws-modules/lambda/aws//modules/docker-build"
  version = "~> 6.0.0"

  create_ecr_repo = true
  ecr_repo        = "repo_webcrawler_condor"
  image_tag       = "1.0"
  source_path     = "../src/crawler/"
}

module "docker_image_insert_fake_data" {
  source  = "terraform-aws-modules/lambda/aws//modules/docker-build"
  version = "~> 6.0.0"

  create_ecr_repo = true
  ecr_repo        = "repo_insert_fake_data"
  image_tag       = "1.0"
  source_path     = "../src/transactional_database/"
}

# Lambda Web Crawler
resource "aws_iam_role" "webcrawler_condor_role" {
  name = "webcrawler_condor_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
  "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
  "arn:aws:iam::aws:policy/AmazonS3FullAccess",
  "arn:aws:iam::aws:policy/CloudWatchFullAccess"]
}

module "lambda_function_webcrawler_condor" {
  source = "terraform-aws-modules/lambda/aws"

  function_name  = "webcrawler_condor"
  create_package = false

  image_uri     = module.docker_image_webcrawler_condor.image_uri
  package_type  = "Image"
  create_role   = false
  lambda_role   = aws_iam_role.webcrawler_condor_role.arn
  memory_size   = 3008
  timeout       = 60
  vpc_subnet_ids         = data.aws_subnets.all.ids
}


# Airbyte 
module "airbyte_google_sheets" {
  source = "./modules/airbyte"
  target_bucket_name = module.brass_bucket.bucket_name
}

# RDS Postgres Transactional
resource "random_password" "postgres_transactional_root_password" {
  length           = 16
  special          = true
  override_special = "!$-<>:"
}

resource "random_password" "postgres_transactional_fake_data_password" {
  length           = 16
  special          = true
  override_special = "!$-<>:"
}

data "http" "my_public_ip" {
  url = "http://ipv4.icanhazip.com"
}

locals {
  my_public_ip                     = sensitive(chomp(data.http.my_public_ip.response_body))
  transactional_database           = "transactional"
  transactional_root_user          = "postgres"
  transactional_root_password      = random_password.postgres_transactional_root_password.result
  transactional_fake_data_user     = "fake_data_app"
  transactional_fake_data_password = random_password.postgres_transactional_fake_data_password.result
  module_path                      = abspath(path.module)
}

module "rds_postgres_transaction" {
  source = "./modules/rds/postgres"
  my_public_ip = local.my_public_ip
  postgres_database = local.transactional_database
  postgres_root_user = local.transactional_root_user
  postgres_root_password = local.transactional_root_password
  postgres_first_user = local.transactional_fake_data_user
  postgres_first_user_password = local.transactional_fake_data_password
}

# Lambda Fake Data
resource "aws_iam_role" "execute_fake_data_app_lambda" {
  name = "execute_fake_data_app_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
  "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"]
}

resource "aws_security_group" "insert_fake_data_sg" {
  name        = "insert_fake_data_sg"
  description = "Allow Access to Transactional Database"
}

resource "aws_vpc_security_group_egress_rule" "lambda_insert_fake_data_egress" {
  security_group_id            = aws_security_group.insert_fake_data_sg.id
  description                  = "Access Transactional Postgres Database"
  ip_protocol                  = "-1"
  referenced_security_group_id = module.rds_postgres_transaction.rds_database_sg_id
}

resource "aws_vpc_security_group_ingress_rule" "lambda_insert_fake_data" {
  security_group_id            = module.rds_postgres_transaction.rds_database_sg_id
  description                  = "Access Postgres from Lambda Insert Fake Data"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.insert_fake_data_sg.id
}

module "lambda_function_insert_fake_data" {
  source     = "terraform-aws-modules/lambda/aws"
  version    = "~> 6.0.0"
  depends_on = [module.rds_postgres_transaction]

  function_name  = "insert_fake_data"
  create_package = false

  image_uri     = module.docker_image_insert_fake_data.image_uri
  package_type  = "Image"
  create_role   = false
  lambda_role   = aws_iam_role.execute_fake_data_app_lambda.arn
  memory_size   = 256
  timeout       = 60
  environment_variables = {
    postgres_app_username = local.transactional_fake_data_user
    postgres_app_password = local.transactional_fake_data_password
    postgres_host         = module.rds_postgres_transaction.rds_database_instance_address
    postgres_database     = local.transactional_database
    postgres_port         = module.rds_postgres_transaction.rds_database_instance_port
  }

  vpc_subnet_ids         = data.aws_subnets.all.ids
  vpc_security_group_ids = [aws_security_group.insert_fake_data_sg.id]
}

# CDC DMS
module "aws_dms_replication_instance" {
  source = "./modules/dms/replication_instance"
  replication_instance_name = "replication-instance-defuse-kit"
  postgres_database_sg_id = module.rds_postgres_transaction.rds_database_sg_id
}

resource "aws_dms_endpoint" "rds_transactional" {
  endpoint_id                 = "rds-postgres"
  endpoint_type               = "source"
  engine_name                 = "postgres"
  # extra_connection_attributes = "PluginName=PGLOGICAL"
  server_name                 = module.rds_postgres_transaction.rds_database_instance_address
  database_name               = local.transactional_database
  port                        = module.rds_postgres_transaction.rds_database_instance_port
  username                    = local.transactional_root_user
  password                    = local.transactional_root_password
}

module "dms_transaction_endpoint_s3" {
  source = "./modules/dms/s3_endpoint"
  endpoint_name = "transaction"
  target_bucket_name = module.brass_bucket.bucket_name
  dms_security_group_id = module.aws_dms_replication_instance.dms_security_group_id
  aws_vpc_id = data.aws_vpc.selected.id
}

# DMS Tasks
resource "aws_dms_replication_task" "transactional_database_to_datalake" {
  migration_type           = "full-load-and-cdc"
  replication_instance_arn = module.aws_dms_replication_instance.dms_replication_instance_arn
  replication_task_id      = "transactional-database-to-datalake"
  replication_task_settings = jsonencode({
    Logging : {
      EnableLogging : true
      LogComponents : [
        {
          Id : "TRANSFORMATION"
          Severity : "LOGGER_SEVERITY_DEBUG"
        },
        {
          Id : "SOURCE_UNLOAD"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "IO"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "TARGET_LOAD"
          Severity : "LOGGER_SEVERITY_INFO"
        },
        {
          Id : "PERFORMANCE"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "SOURCE_CAPTURE"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "SORTER"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "REST_SERVER"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "VALIDATOR_EXT"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "TARGET_APPLY"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "TASK_MANAGER"
          Severity : "LOGGER_SEVERITY_DEBUG"
        },
        {
          Id : "TABLES_MANAGER"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "METADATA_MANAGER"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "FILE_FACTORY"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "COMMON"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "ADDONS"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "DATA_STRUCTURE"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "COMMUNICATION"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        },
        {
          Id : "FILE_TRANSFER"
          Severity : "LOGGER_SEVERITY_DEFAULT"
        }
      ]
    },
  })
  source_endpoint_arn = aws_dms_endpoint.rds_transactional.endpoint_arn
  table_mappings = jsonencode({
    "rules" = [{
      "rule-name" = "1"
      "rule-type" = "selection"
      "rule-id"   = "1"
      "object-locator" = {
        "schema-name" = "transactional"
        "table-name"  = "%"
      }
      "rule-action" = "include"
    }] }
  )
  target_endpoint_arn = module.dms_transaction_endpoint_s3.dms_s3_endpoint_arn
  
  lifecycle {
    ignore_changes = [replication_task_settings]
  }
}