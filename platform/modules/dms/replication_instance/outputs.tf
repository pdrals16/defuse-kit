output "dms_security_group_id" {
  description = "DMS Security Group ID"
  value       = aws_security_group.dms_sg.id
}

output "dms_replication_instance_arn" {
  description = "Replication instance arn"
  value = aws_dms_replication_instance.dms_default_instance.replication_instance_arn
}