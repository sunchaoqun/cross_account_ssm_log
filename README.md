# Cross Account SSM Log

```bash
aws ssm update-document --name "SSM-SessionManagerRunShell" --content "file://SessionManagerRunShell.json"     --document-version '$LATEST'
```

SessionManagerRunShell.json

```json
"kmsKeyId": "arn:aws:kms:ap-southeast-1:ACCOUNT_ID:key/mrk-0655ff186bbf46e2a511d52ce7c4399c",
```

Suggest to create and assign the other account can access permission


"ACCOUNT_ID": Center log account id
"billysun-sub": Center log bucket name

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::ACCOUNT_ID:root"
            },
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::billysun-sub",
                "arn:aws:s3:::billysun-sub/*"
            ]
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "logs.amazonaws.com"
            },
            "Action": [
                "s3:GetBucketAcl",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::billysun-sub",
                "arn:aws:s3:::billysun-sub/*"
            ]
        }
    ]
}
```

lambda_function.py 

require S3 permissions and add S3 "PUT" event
