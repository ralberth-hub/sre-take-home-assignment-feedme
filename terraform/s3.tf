# S3 bucket for frontend hosting - FeedMe dev deployment

# Random ID for unique bucket naming
resource "random_id" "frontend_bucket_suffix" {
  byte_length = 4
}

# S3 Bucket for Frontend Hosting
resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name_prefix}-frontend-${local.env.frontend.bucket_suffix}-${random_id.frontend_bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-frontend"
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Website Configuration
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# S3 Bucket Public Access Block (Allow public read for static website)
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 Bucket Policy for Public Read Access
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# S3 Bucket CORS Configuration
resource "aws_s3_bucket_cors_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    id     = "cleanup_old_versions"
    status = "Enabled"

    filter {
      prefix = "" # Apply to all objects
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Upload frontend files to S3 (initial deployment)
resource "aws_s3_object" "frontend_index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "${path.module}/../frontend/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../frontend/index.html")

  tags = merge(local.common_tags, {
    Name = "frontend-index"
  })
}

# Upload error page
resource "aws_s3_object" "frontend_error" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "error.html"
  content      = <<-EOF
<!DOCTYPE html>
<html>
<head>
    <title>Error - FeedMe</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; }
        .error { color: #da291c; }
    </style>
</head>
<body>
    <h1 class="error">Oops! Something went wrong</h1>
    <p>We're experiencing some technical difficulties. Please try again later.</p>
    <a href="/">Return to Home</a>
</body>
</html>
EOF
  content_type = "text/html"

  tags = merge(local.common_tags, {
    Name = "frontend-error"
  })
}

# CloudWatch Alarms for S3 Bucket
resource "aws_cloudwatch_metric_alarm" "s3_4xx_errors" {
  alarm_name          = "${local.name_prefix}-s3-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors S3 4XX errors"
  alarm_actions       = [] # Add SNS topic ARN for notifications

  dimensions = {
    BucketName = aws_s3_bucket.frontend.bucket
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-4xx-errors-alarm"
  })
}

# S3 Bucket Notification (optional - for CI/CD integration)
resource "aws_s3_bucket_notification" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  # CloudWatch Events for object creation
  eventbridge = true

  # Optional: Lambda function trigger for cache invalidation
  # lambda_function {
  #   lambda_function_arn = aws_lambda_function.cache_invalidation.arn
  #   events              = ["s3:ObjectCreated:*"]
  #   filter_prefix       = ""
  #   filter_suffix       = ".html"
  # }
}

# IAM Role for S3 deployment (for CI/CD pipelines)
resource "aws_iam_role" "s3_deploy" {
  name = "${local.name_prefix}-s3-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["codebuild.amazonaws.com", "codepipeline.amazonaws.com"]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-deploy-role"
  })
}

# IAM Policy for S3 deployment
resource "aws_iam_role_policy" "s3_deploy" {
  name = "${local.name_prefix}-s3-deploy-policy"
  role = aws_iam_role.s3_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.frontend.arn,
          "${aws_s3_bucket.frontend.arn}/*"
        ]
      }
    ]
  })
}

# Local file to update frontend configuration with backend URL
resource "local_file" "frontend_config" {
  content = templatefile("${path.module}/../frontend/index.html", {
    backend_url = "http://${aws_lb.main.dns_name}"
  })
  filename = "${path.module}/temp_index.html"
}

# Upload the configured frontend file
resource "aws_s3_object" "frontend_configured" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = local_file.frontend_config.filename
  content_type = "text/html"
  etag         = local_file.frontend_config.content_md5

  tags = merge(local.common_tags, {
    Name = "frontend-configured"
  })

  depends_on = [local_file.frontend_config]
}