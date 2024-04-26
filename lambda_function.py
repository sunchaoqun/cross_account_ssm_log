import boto3
import re
import urllib.parse

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    # 获取事件中的存储桶和对象键值
    bucket_name = event['Records'][0]['s3']['bucket']['name']
    object_key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
    
    print(f"Bucket: {bucket_name}")
    print(f"Key: {object_key}")

    try:
        # 尝试获取文件来验证是否存在
        s3_client.head_object(Bucket=bucket_name, Key=object_key)
    except s3_client.exceptions.NoSuchKey:
        print(f"No such key: {object_key}")
        return f"No such key: {object_key}"

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
        new_object_key = f"{path_parts[0]}/{original_prefix}-{instance_id}.log"
        s3_client.copy_object(Bucket=bucket_name, CopySource={'Bucket': bucket_name, 'Key': object_key}, Key=new_object_key)
        s3_client.delete_object(Bucket=bucket_name, Key=object_key)
        return f"Renamed file to {new_object_key}"
    else:
        return "Instance ID not found in the log file"
