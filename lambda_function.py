import boto3
import re

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    # 获取事件中的存储桶和对象键值
    bucket_name = event['Records'][0]['s3']['bucket']['name']
    object_key = event['Records'][0]['s3']['object']['key']
    
    path_parts = object_key.split('/')
    filename_parts = path_parts[-1].split('-')
    
    original_prefix = filename_parts[0]
    
    # 从S3下载文件
    file_obj = s3_client.get_object(Bucket=bucket_name, Key=object_key)
    file_content = file_obj['Body'].read().decode('utf-8')
    
    # 使用正则表达式提取实例ID
    match = re.search(r'i-\w+', file_content)
    if match:
        instance_id = match.group(0)
        # 组成新文件路径和名称
        new_object_key = f"{path_parts[0]}/{original_prefix}-{instance_id}.log"
        
        # 复制对象到新的键值
        s3_client.copy_object(Bucket=bucket_name, CopySource={'Bucket': bucket_name, 'Key': object_key}, Key=new_object_key)
        
        # 删除原始对象
        s3_client.delete_object(Bucket=bucket_name, Key=object_key)
        return f"Renamed file to {new_object_key}"
    else:
        return "Instance ID not found in the log file"
