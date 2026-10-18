variable "aws_region" {
  type    = default
  default = "eu-west-1"
}

variable "project_name" {
  type    = default
  default = "backup-system"
}

variable "notification_email" {
  description = "email notification"
  type        = string
  sensitive   = true
}

variable "buckets" {
  type = map(string)
  default = {
    documents = "Documents and files backup"
    database  = "Database exports backup"
    media     = "Images and media backup"
    logs      = "Application logs backup"
  }
}


