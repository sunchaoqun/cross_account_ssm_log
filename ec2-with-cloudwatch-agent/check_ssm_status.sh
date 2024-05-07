#!/bin/bash

# 从命令行参数接收实例ID
INSTANCE_ID=$1
ASSOCIATION_ID=$2  # 假设你也想从Terraform传递关联ID

# 检查SSM执行状态
STATUS="{}"
while [ "$STATUS" != "{Success=1}" ]; do
    STATUS=$(aws ssm describe-association-executions --association-id "$ASSOCIATION_ID" --query 'AssociationExecutions[0].ResourceCountByStatus' --output text)
    echo "Current status: $STATUS"
    if [[ "$STATUS" == "{Failed=1}" ]]; then
      echo "SSM Association execution failed."
      exit 1
    fi
    sleep 5
done

echo "SSM Association executed successfully."

