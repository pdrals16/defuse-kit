output "dms_s3_endpoint_arn" {
    description = "S3 endpoint ARN"
    value = aws_dms_s3_endpoint.s3_datalake_transactional.endpoint_arn
}