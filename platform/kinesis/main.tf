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

#### Bucket ####
resource "aws_s3_bucket" "brass-bucket" {
  bucket = "brass-bucket-defuse-kit"

  tags = {
    Name        = "Project Defuse Kit Brass Bucket"
    Environment = "Prod"
  }
}

resource "aws_s3_bucket_public_access_block" "brass-bucket" {
  bucket = aws_s3_bucket.brass-bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_vpc" "selected" {
  default = true
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

# Kinesis Data Stream
resource "aws_kinesis_stream" "test_stream" {
  name             = "terraform-kinesis-test"
  shard_count      = 1
  retention_period = 48

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Environment = "Production"
  }
}

# Lambda for Firehose
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_iam" {
  name               = "lambda_iam"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "lambda_function_payload.zip"
}

module "lambda_function_firehose_processor" {
  source = "terraform-aws-modules/lambda/aws"

  function_name  = "lambda_processor"
  runtime       = "python3.10"
  
  create_package = false
  local_existing_package = "lambda_function_payload.zip"
  handler = "lambda_function.lambda_handler"

  create_role   = false
  lambda_role   = aws_iam_role.lambda_iam.arn
  memory_size   = 3008
  timeout       = 60
  vpc_subnet_ids         = data.aws_subnets.all.ids
}

# Kinesis Firesis Delivery Stream
resource "aws_iam_role" "firehose" {
  name = "DemoFirehoseAssumeRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "firehose_s3" {
  policy      = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
            "s3:AbortMultipartUpload",
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:ListBucketMultipartUploads",
            "s3:PutObject"
        ],
        "Resource": [
            "${aws_s3_bucket.brass-bucket.arn}",
            "${aws_s3_bucket.brass-bucket.arn}/*"
        ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "firehose_s3" {
  role       = aws_iam_role.firehose.name
  policy_arn = aws_iam_policy.firehose_s3.arn
}

resource "aws_iam_policy" "put_record" {
  policy      = <<-EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "firehose:PutRecord",
                "firehose:PutRecordBatch"
            ],
            "Resource": [
                "${aws_kinesis_firehose_delivery_stream.extended_s3_stream.arn}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "put_record" {
  role       = aws_iam_role.firehose.name
  policy_arn = aws_iam_policy.put_record.arn
}

resource "aws_iam_policy" "kinesis_firehose" {
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Sid": "",
        "Effect": "Allow",
        "Action": [
            "kinesis:DescribeStream",
            "kinesis:GetShardIterator",
            "kinesis:GetRecords",
            "kinesis:ListShards"
        ],
        "Resource": "${aws_kinesis_stream.test_stream.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "kinesis_firehose" {
  role       = aws_iam_role.firehose.name
  policy_arn = aws_iam_policy.kinesis_firehose.arn
}

resource "aws_iam_policy" "lambda_firehose" {
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowAuroraToExampleFunction",
            "Effect": "Allow",
            "Action": [
              "lambda:InvokeFunction",
              "lambda:GetFunctionConfiguration"
            ],
            "Resource": "${module.lambda_function_firehose_processor.lambda_function_arn}:$LATEST"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_firehose" {
  role       = aws_iam_role.firehose.name
  policy_arn = aws_iam_policy.lambda_firehose.arn
}

resource "aws_kinesis_firehose_delivery_stream" "extended_s3_stream" {
  name        = "terraform-kinesis-firehose-extended-s3-test-stream"
  destination = "extended_s3"

  kinesis_source_configuration {
    role_arn           = aws_iam_role.firehose.arn
    kinesis_stream_arn = aws_kinesis_stream.test_stream.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.brass-bucket.arn

    prefix              = "kinesis_ingestor/data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "kinesis_ingestor/errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/!{firehose:error-output-type}/"
    
    processing_configuration {
      enabled = "true"

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${module.lambda_function_firehose_processor.lambda_function_arn}:$LATEST"
        }
      }
    }
  }

  depends_on = [aws_iam_role.firehose]
}