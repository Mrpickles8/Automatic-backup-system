terraform {
  required_version = "1.16.5"
  cloud {
    organization = "Dominionorg"
    workspaces {
      name = "automatic-backup-system"
    }
  }
}

required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"
  }
}


provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "backup" {
  for_each = var.buckets
  bucket   = "${var.project_name}-${each.key}-${random_id.suffix.hex}"
  tags = {
    Type    = each.key
    Purpose = each.value
    Project = var.project_name
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_public_access_block" "backup" {
  for_each                = var.buckets
  bucket                  = aws_s3_bucket.backup[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backup" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

#we create the kms key
resource "aws_kms_key" "backup" {
  description             = "kms key encryption for backup"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

#We encrypt all the buckets
resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.backup.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# We create the bucket lifecycle config
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  for_each = var.buckets

  bucket = aws_s3_bucket.backup[each.key].id

  rule {
    id     = "backup-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.backup
  ]
}



data "archive_file" "backup_lambda" {
  type        = "zip"
  source_file = "lambda_backup.py"
  output_path = "lambda_backup.zip"
}


resource "aws_lambda_function" "backup_lambda" {
  filename         = data.archive_file.backup_lambda.output_path
  function_name    = "${var.project_name}-backup-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_backup.lambda_handler"
  source_code_hash = data.archive_file.backup_lambda.output_base64sha256

  runtime = "python3.13"

  environment {
    variables = {
      SOURCE_BUCKET    = aws_s3_bucket.source.bucket
      DOCUMENTS_BUCKET = aws_s3_bucket.backup["documents"].bucket
      DATABASE_BUCKET  = aws_s3_bucket.backup["database"].bucket
      MEDIA_BUCKET     = aws_s3_bucket.backup["media"].bucket
      LOGS_BUCKET      = aws_s3_bucket.backup["logs"].bucket
    }
  }
}

resource "aws_cloudwatch_event_rule" "backup_eventbridge_at_night" {
  name                = "${var.project_name}-backup-at-night"
  description         = "The backup will occurd at 2am each day"
  schedule_expression = "cron(0 2 * * ? *)"
}


resource "aws_cloudwatch_event_target" "backup_at_night" {
  rule = aws_cloudwatch_event_rule.backup_eventbridge_at_night.name
  arn  = aws_lambda_function.backup_lambda.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_eventbridge_at_night.arn
}

resource "aws_sns_topic" "backup_notifications" {
  name = "${var.project_name}-backup-notifications"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.backup_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_sns_topic_policy" "s3_publish" {
  arn = aws_sns_topic.backup_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Allows3Publish"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.backup_notifications.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:s3:::${var.project_name}-*"
          }
        }
      },
      {
        Sid       = "AllowLambdaPublish"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.backup_notifications.arn
      }
    ]
  })
}


resource "aws_s3_bucket_notification" "backup" {
  for_each = var.buckets

  bucket = aws_s3_bucket.backup[each.key].id

  topic {
    topic_arn = aws_sns_topic.backup_notifications.arn
    events    = ["s3:ObjectCreated:*"]

    filter_suffix = ".backup"
  }
  depends_on = [aws_sns_topic_policy.s3_publish]
}

