resource "aws_iam_role" "s3_dms_target_role" {
  name = "s3_dms_target_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name = "allow_s3_access"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = ["s3:PutObject",
            "s3:GetBucketLocation",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:DeleteObject",
          "s3:PutObjectTagging"]
          Resource = ["arn:aws:s3:::${var.target_bucket_name}",
          "arn:aws:s3:::${var.target_bucket_name}/*"]
        }
      ]
    })
  }
}

resource "aws_dms_s3_endpoint" "s3_datalake_transactional" {
  endpoint_id             = var.endpoint_name
  endpoint_type           = "target"
  data_format             = "csv"
  bucket_folder           = "dms-${var.endpoint_name}"
  bucket_name             = var.target_bucket_name
  compression_type        = "GZIP"
  csv_delimiter           = ","
  csv_row_delimiter       = "\n"
  rfc_4180                = true
  add_column_name         = true
  service_access_role_arn = aws_iam_role.s3_dms_target_role.arn
}

# Para não precisar usar o NAT Gateway e conseguir acessar o S3 que está fora da VPC
resource "aws_vpc_endpoint" "private_s3" {
  vpc_id            = var.aws_vpc_id
  service_name      = "com.amazonaws.us-east-2.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "s3-endpoint"
  }
}

data "aws_route_tables" "rts" {
  vpc_id = var.aws_vpc_id
  filter {
    name   = "association.main"
    values = [true]
  }
}

resource "aws_vpc_endpoint_route_table_association" "private_s3" {
  vpc_endpoint_id = aws_vpc_endpoint.private_s3.id
  route_table_id  = element(data.aws_route_tables.rts.ids, 1)
}

resource "aws_vpc_security_group_egress_rule" "dms_egress_to_s3" {
  security_group_id = var.dms_security_group_id
  description       = "Access to S3 from VPN"
  ip_protocol       = "TCP"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.private_s3.prefix_list_id
}