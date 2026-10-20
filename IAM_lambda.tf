resource "aws_iam_policy" "Boundary_cost" {
  name        = "${var.project_name}-backup-lambda-boundary"
  description = "Boundary for the lambda backup projet"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "SourceBucketList"
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = aws_s3_bucket.source.arn
      },
      {
        Sid    = "SourceBucketRead"
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = "${aws_s3_bucket.source.arn}/*"
      },
      {
        Sid    = "BackupObjectsAccess"
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]

        Resource = [
          "${aws_s3_bucket.backup["documents"].arn}/*",
          "${aws_s3_bucket.backup["database"].arn}/*",
          "${aws_s3_bucket.backup["media"].arn}/*",
          "${aws_s3_bucket.backup["logs"].arn}/*"
        ]
      },
      {
        Sid    = "BackupBucketsList"
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.backup["documents"].arn,
          aws_s3_bucket.backup["database"].arn,
          aws_s3_bucket.backup["media"].arn,
          aws_s3_bucket.backup["logs"].arn
        ]
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"

        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_role" {
  name                 = "${var.project_name}-backup-lambda-role"
  permissions_boundary = aws_iam_policy.Boundary_cost.arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = aws_s3_bucket.source.arn
      },

      {
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = "${aws_s3_bucket.source.arn}/*"
      },

      # Écrire les fichiers dans les buckets de sauvegarde
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]

        Resource = [
          "${aws_s3_bucket.backup["documents"].arn}/*",
          "${aws_s3_bucket.backup["database"].arn}/*",
          "${aws_s3_bucket.backup["media"].arn}/*",
          "${aws_s3_bucket.backup["logs"].arn}/*"
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.backup["documents"].arn,
          aws_s3_bucket.backup["database"].arn,
          aws_s3_bucket.backup["media"].arn,
          aws_s3_bucket.backup["logs"].arn
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "*"
      }
    ]
  })
}