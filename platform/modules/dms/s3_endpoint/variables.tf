variable "endpoint_name" {
  type = string
  description = "Postgres Database Security Group ID"
}

variable "target_bucket_name" {
  type = string
  description = "Bucket's name to ingest airbyte data."
}

variable "dms_security_group_id" {
  type = string
  description = "Bucket's name to ingest airbyte data."
}

variable "aws_vpc_id" {
  type = string
  description = "VPC ID"
}