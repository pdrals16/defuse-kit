resource "aws_iam_role" "glue_role" {
  name                = "glue_role"
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
                "arn:aws:s3:::${var.bucket_name}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3.arn
}


resource "aws_glue_catalog_database" "glue_database" {
  name = var.glue_database_name
}

resource "aws_glue_crawler" "glue_transactional_crawler" {
  database_name = aws_glue_catalog_database.glue_database.name
  name          = "transactional_glue_crawler"
  role          = aws_iam_role.glue_role.arn

  configuration = <<EOF
    {
      "Version":1.0,
      "Grouping": {
        "TableGroupingPolicy": "CombineCompatibleSchemas"
      }
    }
  EOF
    

  s3_target {
    path = "s3://brass-bucket-defuse-kit/dms-transactional/transactional/address/"
  }

  s3_target {
    path = "s3://brass-bucket-defuse-kit/dms-transactional/transactional/orders/"
  }

  s3_target {
    path = "s3://brass-bucket-defuse-kit/dms-transactional/transactional/orders_status_history/"
  }

  s3_target {
    path = "s3://brass-bucket-defuse-kit/dms-transactional/transactional/supplier/"
  }
}

