variable "my_public_ip" {
  type = string
  description = "Postgres Database Security Group ID"
}

variable "postgres_database" {
  type = string
  description = "Bucket's name to ingest airbyte data."
}

variable "postgres_root_user" {
  type = string
  description = "Bucket's name to ingest airbyte data."
}

variable "postgres_root_password" {
  type = string
  description = "VPC ID"
}

variable "postgres_first_user" {
  type = string
  description = "Bucket's name to ingest airbyte data."
}

variable "postgres_first_user_password" {
  type = string
  description = "VPC ID"
}