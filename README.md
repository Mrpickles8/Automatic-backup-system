# Automatic-Backup-System
 
> 🌍 **Select your language / Choisissez votre langue / Sprache wählen**
 
[🇫🇷 Français](#français) ·
[🇬🇧 English](#english) ·
[🇩🇪 Deutsch](#deutsch)
 
---
 
## Français
 
## Objectif
 
Ce projet met en place un système de sauvegarde automatique sur AWS. Il organise les données en 4 buckets S3 selon leur type, active le versioning et le chiffrement KMS sur chacun, configure des règles de cycle de vie pour migrer automatiquement les données vers un stockage moins cher, et déclenche chaque nuit une fonction Lambda qui copie les fichiers du bucket source vers les buckets de backup avec notification email de confirmation.
 
## Problème résolu
 
La perte de données est irréversible et coûteuse. Sans backup automatique, une suppression accidentelle, une attaque ransomware ou une corruption de données peut être catastrophique. Ce projet crée une protection automatique et économique.
 
## Compétences acquises
 
- Gestion multi-buckets S3 avec `for_each` Terraform
- Activation du versioning et chiffrement KMS sur S3
- Configuration des lifecycle policies pour optimiser les coûts de stockage
- Déploiement de fonctions Lambda serverless avec Terraform
- Automatisation de tâches planifiées avec EventBridge
- Notification par email via SNS
- Principe du moindre privilège appliqué aux rôles IAM Lambda
## Outils utilisés
 
- Terraform (Infrastructure as Code)
- AWS : S3, KMS, Lambda, EventBridge, SNS, IAM
## Architecture
 
```
Bucket Source (application)
    → Lambda (chaque nuit à 2h)
        → Tri par type de fichier
            → documents-bucket (PDF, DOCX, CSV...)
            → database-bucket  (SQL, DB, JSON...)
            → media-bucket     (JPG, PNG, MP4...)
            → logs-bucket      (autres fichiers)
 
Règles de cycle de vie sur chaque bucket :
    → Standard-IA après 30 jours  (-45% de coût)
    → Glacier après 90 jours       (-83% de coût)
    → Suppression après 365 jours
 
SNS → Email de confirmation après chaque backup
```
 
## Étapes
 
### Ref 1 : Buckets S3 par type de données avec `for_each`
 
Au lieu de créer 4 ressources séparées, on utilise `for_each` pour itérer sur une map de types de données et créer un bucket pour chacun. Chaque bucket reçoit un suffixe aléatoire car les noms S3 sont uniques globalement.
 
```hcl
variable "buckets" {
  default = {
    documents = "Documents and files backup"
    database  = "Database exports backup"
    media     = "Images and media backup"
    logs      = "Application logs backup"
  }
}
 
resource "aws_s3_bucket" "backup" {
  for_each = var.buckets
  bucket   = "${var.project_name}-${each.key}-${random_id.suffix.hex}"
  tags = {
    Type    = each.key
    Purpose = each.value
  }
}
 
# Blocage accès public sur tous les buckets
resource "aws_s3_bucket_public_access_block" "backup" {
  for_each                = var.buckets
  bucket                  = aws_s3_bucket.backup[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```
 
### Ref 2 : Versioning et chiffrement KMS
 
Le versioning conserve toutes les versions de chaque fichier — protection contre les suppressions accidentelles et les ransomwares. Le chiffrement KMS avec rotation automatique protège les données au repos.
 
```hcl
resource "aws_kms_key" "backup" {
  description             = "KMS key for backup encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
 
resource "aws_s3_bucket_versioning" "backup" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id
  versioning_configuration { status = "Enabled" }
}
 
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.backup.arn
    }
  }
}
```
 
### Ref 3 : Lifecycle policies — stockage moins cher automatiquement
 
Les règles de cycle de vie migrent automatiquement les données vers des classes de stockage moins chères selon leur ancienneté, sans intervention manuelle.
 
```hcl
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id
 
  rule {
    id     = "backup-lifecycle"
    status = "Enabled"
 
    # Après 30 jours → Standard-IA (45% moins cher)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
 
    # Après 90 jours → Glacier (83% moins cher)
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
 
    # Supprimer les anciennes versions après 365 jours
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
 
  depends_on = [aws_s3_bucket_versioning.backup]
}
```
 
### Ref 4 : Lambda — backup automatique nocturne
 
Une fonction Lambda tourne chaque nuit à 2h. Elle liste les fichiers du bucket source, détermine le bucket de destination selon l'extension, copie chaque fichier avec un préfixe de date, puis envoie un rapport de confirmation par email via SNS.
 
```hcl
resource "aws_lambda_function" "backup" {
  filename      = data.archive_file.backup_lambda.output_path
  function_name = "${var.project_name}-backup-processor"
  role          = aws_iam_role.backup_lambda.arn
  handler       = "lambda_backup.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
 
  environment {
    variables = {
      SOURCE_BUCKET    = aws_s3_bucket.source.bucket
      DOCUMENTS_BUCKET = aws_s3_bucket.backup["documents"].bucket
      DATABASE_BUCKET  = aws_s3_bucket.backup["database"].bucket
      MEDIA_BUCKET     = aws_s3_bucket.backup["media"].bucket
      LOGS_BUCKET      = aws_s3_bucket.backup["logs"].bucket
      SNS_TOPIC_ARN    = aws_sns_topic.backup_notifications.arn
    }
  }
}
 
# EventBridge — chaque nuit à 2h
resource "aws_cloudwatch_event_rule" "nightly_backup" {
  name                = "${var.project_name}-nightly-backup"
  schedule_expression = "cron(0 2 * * ? *)"
}
```
 
### Ref 5 : SNS — notifications de confirmation
 
SNS envoie un email de confirmation après chaque backup avec le nombre de fichiers copiés par type. Si le backup échoue, une alerte est envoyée immédiatement.
 
```hcl
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
        Sid       = "AllowS3Publish"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.backup_notifications.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:s3:::${var.project_name}-*"
          }
        }
      }
    ]
  })
}
```
 
## Déploiement
 
```bash
terraform init
terraform plan
terraform apply
```
 
> ⚠️ Après le déploiement, confirme la souscription SNS en cliquant sur le lien reçu par email.
 
## Tester le backup manuellement
 
```bash
# Uploader un fichier de test dans le bucket source
aws s3 cp test.pdf s3://VOTRE-SOURCE-BUCKET/
 
# Invoquer la Lambda manuellement
aws lambda invoke \
  --function-name backup-system-backup-processor \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json
 
cat response.json
```
 
## Note
 
Le bucket source simule une application qui génère des fichiers. En production, ce serait remplacé par une connexion directe à l'application. GuardDuty n'est pas inclus dans ce projet. Le projet est un exercice de backup et d'optimisation des coûts de stockage, non une architecture de production.
 
[⬆️ Retour au menu](#aws-automatic-backup-system)
 
---
 
## English
 
## Objective
 
This project sets up an automatic backup system on AWS. It organizes data into 4 S3 buckets by type, enables versioning and KMS encryption on each, configures lifecycle rules to automatically migrate data to cheaper storage, and triggers a Lambda function every night to copy files from the source bucket to backup buckets with email confirmation.
 
## Problem Solved
 
Data loss is irreversible and costly. Without automatic backup, accidental deletion, a ransomware attack, or data corruption can be catastrophic. This project creates automatic and cost-effective protection.
 
## Skills Learned
 
- Multi-bucket S3 management with Terraform `for_each`
- S3 versioning and KMS encryption
- Lifecycle policy configuration for storage cost optimization
- Serverless Lambda deployment with Terraform
- Scheduled task automation with EventBridge
- Email notification via SNS
- Least-privilege principle applied to Lambda IAM roles
## Tools Used
 
- Terraform (Infrastructure as Code)
- AWS: S3, KMS, Lambda, EventBridge, SNS, IAM
## Architecture
 
```
Source Bucket (application)
    → Lambda (every night at 2am)
        → File type sorting
            → documents-bucket (PDF, DOCX, CSV...)
            → database-bucket  (SQL, DB, JSON...)
            → media-bucket     (JPG, PNG, MP4...)
            → logs-bucket      (other files)
 
Lifecycle rules on each bucket:
    → Standard-IA after 30 days  (-45% cost)
    → Glacier after 90 days       (-83% cost)
    → Deletion after 365 days
 
SNS → Confirmation email after each backup
```
 
## Steps
 
### Ref 1: S3 buckets by data type with `for_each`
 
Instead of creating 4 separate resources, `for_each` iterates over a map of data types to create one bucket each. Each bucket gets a random suffix since S3 names are globally unique.
 
```hcl
variable "buckets" {
  default = {
    documents = "Documents and files backup"
    database  = "Database exports backup"
    media     = "Images and media backup"
    logs      = "Application logs backup"
  }
}
 
resource "aws_s3_bucket" "backup" {
  for_each = var.buckets
  bucket   = "${var.project_name}-${each.key}-${random_id.suffix.hex}"
  tags = {
    Type    = each.key
    Purpose = each.value
  }
}
 
resource "aws_s3_bucket_public_access_block" "backup" {
  for_each                = var.buckets
  bucket                  = aws_s3_bucket.backup[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```
 
### Ref 2: Versioning and KMS encryption
 
Versioning keeps all versions of each file — protection against accidental deletions and ransomware. KMS encryption with automatic rotation protects data at rest.
 
```hcl
resource "aws_kms_key" "backup" {
  description             = "KMS key for backup encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
 
resource "aws_s3_bucket_versioning" "backup" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id
  versioning_configuration { status = "Enabled" }
}
 
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.backup.arn
    }
  }
}
```
 
### Ref 3: Lifecycle policies — automatically cheaper storage
 
Lifecycle rules automatically migrate data to cheaper storage classes based on age, without manual intervention.
 
```hcl
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id
 
  rule {
    id     = "backup-lifecycle"
    status = "Enabled"
 
    # After 30 days → Standard-IA (45% cheaper)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
 
    # After 90 days → Glacier (83% cheaper)
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
 
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
 
  depends_on = [aws_s3_bucket_versioning.backup]
}
```
 
### Ref 4: Lambda — automated nightly backup
 
A Lambda function runs every night at 2am. It lists files in the source bucket, determines the destination bucket by file extension, copies each file with a date prefix, then sends a confirmation report by email via SNS.
 
```hcl
resource "aws_lambda_function" "backup" {
  filename      = data.archive_file.backup_lambda.output_path
  function_name = "${var.project_name}-backup-processor"
  role          = aws_iam_role.backup_lambda.arn
  handler       = "lambda_backup.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
 
  environment {
    variables = {
      SOURCE_BUCKET    = aws_s3_bucket.source.bucket
      DOCUMENTS_BUCKET = aws_s3_bucket.backup["documents"].bucket
      DATABASE_BUCKET  = aws_s3_bucket.backup["database"].bucket
      MEDIA_BUCKET     = aws_s3_bucket.backup["media"].bucket
      LOGS_BUCKET      = aws_s3_bucket.backup["logs"].bucket
      SNS_TOPIC_ARN    = aws_sns_topic.backup_notifications.arn
    }
  }
}
 
resource "aws_cloudwatch_event_rule" "nightly_backup" {
  name                = "${var.project_name}-nightly-backup"
  schedule_expression = "cron(0 2 * * ? *)"
}
```
 
### Ref 5: SNS — confirmation notifications
 
SNS sends a confirmation email after each backup with the number of files copied by type. If the backup fails, an alert is sent immediately.
 
```hcl
resource "aws_sns_topic" "backup_notifications" {
  name = "${var.project_name}-backup-notifications"
}
 
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.backup_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
```
 
## Deployment
 
```bash
terraform init
terraform plan
terraform apply
```
 
> ⚠️ After deployment, confirm the SNS subscription by clicking the link received by email.
 
## Test the backup manually
 
```bash
# Upload a test file to the source bucket
aws s3 cp test.pdf s3://YOUR-SOURCE-BUCKET/
 
# Invoke the Lambda manually
aws lambda invoke \
  --function-name backup-system-backup-processor \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json
 
cat response.json
```
 
## Note
 
The source bucket simulates an application that generates files. In production, this would be replaced by a direct connection to the application. GuardDuty is not included in this project. This project is a backup and storage cost optimization exercise, not a production architecture.
 
[⬆️ Back to menu](#aws-automatic-backup-system)
 
---
 
## Deutsch
 
## Ziel
 
Dieses Projekt richtet ein automatisches Backup-System auf AWS ein. Es organisiert Daten in 4 S3-Buckets nach Typ, aktiviert Versionierung und KMS-Verschlüsselung auf jedem Bucket, konfiguriert Lifecycle-Regeln zur automatischen Migration in günstigeren Speicher und löst jede Nacht eine Lambda-Funktion aus, die Dateien vom Quell-Bucket in Backup-Buckets kopiert und eine E-Mail-Bestätigung sendet.
 
## Gelöstes Problem
 
Datenverlust ist irreversibel und kostspielig. Ohne automatisches Backup kann eine versehentliche Löschung, ein Ransomware-Angriff oder eine Datenbeschädigung katastrophal sein. Dieses Projekt schafft einen automatischen und kosteneffizienten Schutz.
 
## Erworbene Kompetenzen
 
- Multi-Bucket S3-Verwaltung mit Terraform `for_each`
- S3-Versionierung und KMS-Verschlüsselung
- Konfiguration von Lifecycle-Richtlinien zur Speicherkostenoptimierung
- Serverlose Lambda-Bereitstellung mit Terraform
- Automatisierung geplanter Aufgaben mit EventBridge
- E-Mail-Benachrichtigung über SNS
- Least-Privilege-Prinzip für Lambda-IAM-Rollen
## Verwendete Werkzeuge
 
- Terraform (Infrastructure as Code)
- AWS: S3, KMS, Lambda, EventBridge, SNS, IAM
## Architektur
 
```
Quell-Bucket (Anwendung)
    → Lambda (jede Nacht um 2 Uhr)
        → Sortierung nach Dateityp
            → documents-bucket (PDF, DOCX, CSV...)
            → database-bucket  (SQL, DB, JSON...)
            → media-bucket     (JPG, PNG, MP4...)
            → logs-bucket      (andere Dateien)
 
Lifecycle-Regeln auf jedem Bucket:
    → Standard-IA nach 30 Tagen  (-45% Kosten)
    → Glacier nach 90 Tagen       (-83% Kosten)
    → Löschung nach 365 Tagen
 
SNS → Bestätigungs-E-Mail nach jedem Backup
```
 
## Schritte
 
### Ref 1: S3-Buckets nach Datentyp mit `for_each`
 
Anstatt 4 separate Ressourcen zu erstellen, iteriert `for_each` über eine Map von Datentypen und erstellt für jeden einen Bucket. Jeder Bucket erhält ein zufälliges Suffix, da S3-Namen global eindeutig sind.
 
```hcl
variable "buckets" {
  default = {
    documents = "Documents and files backup"
    database  = "Database exports backup"
    media     = "Images and media backup"
    logs      = "Application logs backup"
  }
}
 
resource "aws_s3_bucket" "backup" {
  for_each = var.buckets
  bucket   = "${var.project_name}-${each.key}-${random_id.suffix.hex}"
  tags = {
    Type    = each.key
    Purpose = each.value
  }
}
```
 
### Ref 2: Versionierung und KMS-Verschlüsselung
 
Die Versionierung bewahrt alle Versionen jeder Datei — Schutz vor versehentlichen Löschungen und Ransomware. KMS-Verschlüsselung mit automatischer Rotation schützt Daten im Ruhezustand.
 
```hcl
resource "aws_kms_key" "backup" {
  description             = "KMS key for backup encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
 
resource "aws_s3_bucket_versioning" "backup" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id
  versioning_configuration { status = "Enabled" }
}
```
 
### Ref 3: Lifecycle-Richtlinien — automatisch günstigerer Speicher
 
Lifecycle-Regeln migrieren Daten automatisch in günstigere Speicherklassen je nach Alter, ohne manuellen Eingriff.
 
```hcl
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  for_each = var.buckets
  bucket   = aws_s3_bucket.backup[each.key].id
 
  rule {
    id     = "backup-lifecycle"
    status = "Enabled"
 
    # Nach 30 Tagen → Standard-IA (45% günstiger)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
 
    # Nach 90 Tagen → Glacier (83% günstiger)
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
 
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
 
  depends_on = [aws_s3_bucket_versioning.backup]
}
```
 
### Ref 4: Lambda — automatisches nächtliches Backup
 
Eine Lambda-Funktion läuft jede Nacht um 2 Uhr. Sie listet Dateien im Quell-Bucket auf, bestimmt den Ziel-Bucket anhand der Dateiendung, kopiert jede Datei mit einem Datumspräfix und sendet dann einen Bestätigungsbericht per E-Mail über SNS.
 
```hcl
resource "aws_lambda_function" "backup" {
  filename      = data.archive_file.backup_lambda.output_path
  function_name = "${var.project_name}-backup-processor"
  role          = aws_iam_role.backup_lambda.arn
  handler       = "lambda_backup.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
}
 
resource "aws_cloudwatch_event_rule" "nightly_backup" {
  name                = "${var.project_name}-nightly-backup"
  schedule_expression = "cron(0 2 * * ? *)"
}
```
 
### Ref 5: SNS — Bestätigungsbenachrichtigungen
 
SNS sendet nach jedem Backup eine Bestätigungs-E-Mail mit der Anzahl der kopierten Dateien nach Typ. Bei einem Backup-Fehler wird sofort eine Warnung gesendet.
 
```hcl
resource "aws_sns_topic" "backup_notifications" {
  name = "${var.project_name}-backup-notifications"
}
 
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.backup_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
```
 
## Bereitstellung
 
```bash
terraform init
terraform plan
terraform apply
```
 
> ⚠️ Bestätige nach der Bereitstellung das SNS-Abonnement, indem du auf den per E-Mail erhaltenen Link klickst.
 
## Backup manuell testen
 
```bash
# Testdatei in den Quell-Bucket hochladen
aws s3 cp test.pdf s3://DEIN-QUELL-BUCKET/
 
# Lambda manuell aufrufen
aws lambda invoke \
  --function-name backup-system-backup-processor \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json
 
cat response.json
```
 
## Hinweis
 
Der Quell-Bucket simuliert eine Anwendung, die Dateien generiert. In der Produktion würde dieser durch eine direkte Verbindung zur Anwendung ersetzt. GuardDuty ist in diesem Projekt nicht enthalten. Das Projekt ist eine Backup- und Speicherkostenoptimierungsübung, keine Produktionsarchitektur.
 
[⬆️ Zurück zum Menü](#aws-automatic-backup-system)
 
