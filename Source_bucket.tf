resource "aws_s3_bucket" "source" {
  bucket = "${var.project_name}-source-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

