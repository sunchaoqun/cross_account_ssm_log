#!/bin/bash
# check_log_group.sh

LOG_GROUP_NAME=$1

# 使用AWS CLI检查日志组是否存在
if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" | grep -q "$LOG_GROUP_NAME"; then
  echo '{"exists": "true"}'
else
  echo '{"exists": "false"}'
fi
