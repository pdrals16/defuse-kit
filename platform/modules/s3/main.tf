resource "aws_s3_bucket" "s3_bucket" {
  bucket = "${var.bucket_name}-bucket-defuse-kit"

  tags = {
    Name        = "Project Defuse Kit Bucket"
    Environment = "Prod"
  }
}

resource "aws_s3_bucket_public_access_block" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}