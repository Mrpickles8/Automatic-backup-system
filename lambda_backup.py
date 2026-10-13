# lambda_backup.py
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')

def lambda_handler(event, context):
    source_bucket = os.environ['SOURCE_BUCKET']
    backup_buckets = {
        'documents': os.environ['DOCUMENTS_BUCKET'],
        'database':  os.environ['DATABASE_BUCKET'],
        'media':     os.environ['MEDIA_BUCKET'],
        'logs':      os.environ['LOGS_BUCKET'],
    }

    
    response = s3.list_objects_v2(Bucket=source_bucket)
    
    if 'Contents' not in response:
        return {'statusCode': 200, 'body': 'No files to backup'}

    backed_up = 0
    date_prefix = datetime.now().strftime('%Y/%m/%d')

    for obj in response['Contents']:
        key = obj['Key']
        
        
        if key.endswith(('.pdf', '.docx', '.txt', '.csv')):
            dest_bucket = backup_buckets['documents']
        elif key.endswith(('.sql', '.db', '.dump')):
            dest_bucket = backup_buckets['database']
        elif key.endswith(('.jpg', '.png', '.mp4', '.gif')):
            dest_bucket = backup_buckets['media']
        else:
            dest_bucket = backup_buckets['logs']

       
        dest_key = f"backup/{date_prefix}/{key}"
        
        s3.copy_object(
            CopySource={'Bucket': source_bucket, 'Key': key},
            Bucket=dest_bucket,
            Key=dest_key
        )
        backed_up += 1

    return {
        'statusCode': 200,
        'body': f'{backed_up} files backed up on {date_prefix}'
    }