data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["dms.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "dms-access-for-endpoint" {
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  name               = "dms-access-for-endpoint"
}

resource "aws_iam_role_policy_attachment" "dms-access-for-endpoint-AmazonDMSRedshiftS3Role" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSRedshiftS3Role"
  role       = aws_iam_role.dms-access-for-endpoint.name
}

resource "aws_iam_role" "dms-cloudwatch-logs-role" {
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  name               = "dms-cloudwatch-logs-role"
}

resource "aws_iam_role_policy_attachment" "dms-cloudwatch-logs-role-AmazonDMSCloudWatchLogsRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
  role       = aws_iam_role.dms-cloudwatch-logs-role.name
}

resource "aws_iam_role" "dms-vpc-role" {
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  name               = "dms-vpc-role"
}

resource "aws_iam_role_policy_attachment" "dms-vpc-role-AmazonDMSVPCManagementRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
  role       = aws_iam_role.dms-vpc-role.name
}

resource "aws_security_group" "dms_sg" {
  name        = "dms_sg"
  description = "Allow DMS Access to Transactional Database"
  timeouts {
    delete = "2m"
  }
}

resource "aws_vpc_security_group_ingress_rule" "dms_ingress" {
  security_group_id            = var.postgres_database_sg_id
  description                  = "Access Postgres from DMS"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.dms_sg.id
}

resource "aws_vpc_security_group_egress_rule" "dms_egress_to_db" {
  security_group_id            = aws_security_group.dms_sg.id
  description                  = "Access to Transactional Postgres Database"
  ip_protocol                  = "-1"
  referenced_security_group_id = var.postgres_database_sg_id
}

resource "time_sleep" "wait_20_seconds" {
  create_duration = "20s"
}

resource "aws_dms_replication_instance" "dms_default_instance" {
  allocated_storage           = 5
  engine_version              = "3.5.1"
  multi_az                    = false
  replication_instance_class  = "dms.t2.micro"
  replication_instance_id     = var.replication_instance_name
  allow_major_version_upgrade = true

  vpc_security_group_ids = [
    aws_security_group.dms_sg.id
  ]

  depends_on = [
    aws_iam_role_policy_attachment.dms-access-for-endpoint-AmazonDMSRedshiftS3Role,
    aws_iam_role_policy_attachment.dms-cloudwatch-logs-role-AmazonDMSCloudWatchLogsRole,
    aws_iam_role_policy_attachment.dms-vpc-role-AmazonDMSVPCManagementRole,
    time_sleep.wait_20_seconds
  ]
}