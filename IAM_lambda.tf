resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-backup-lambda-role"
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
      # Lire et lister les fichiers du bucket source
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

      # Lister les buckets de sauvegarde
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

      # Écrire les logs CloudWatch
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