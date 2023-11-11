output "bucket_name" {
    description = "S3 endpoint ARN"
    value = aws_s3_bucket.s3_bucket.bucket
}