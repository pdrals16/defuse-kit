output "rds_database_sg_id" {
    description = "S3 endpoint ARN"
    value = aws_security_group.postgres_database_sg.id
}

output "rds_database_instance_address" {
  description = "value"
  value = aws_db_instance.rds_postgres.address
}

output "rds_database_instance_port" {
  description = "value"
  value = aws_db_instance.rds_postgres.port
}