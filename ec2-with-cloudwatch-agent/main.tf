provider "aws" {
  region = "ap-southeast-1" # 更改为适合您的AWS区域
}

variable "log_group_name" {
  type        = string
  description = "The name of the instance"
  default     = "linux/auth"
}

# 数据源：获取最新的Amazon Linux 2 AMI
data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"] # Amazon官方所有者ID
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"] # 确保是EBS支持的HVM AMI
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# 创建IAM角色
resource "aws_iam_role" "ssm_role" {
  name = "SSMRoleForEC2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "decrypt_policy" {
  name        = "DecryptPolicy"
  description = "Policy to allow decryption with specific KMS key"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "kms:Decrypt",
            "Resource": "arn:aws:kms:ap-southeast-1:605852794516:key/mrk-0655ff186bbf46e2a511d52ce7c4399c"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "decrypt_policy_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.decrypt_policy.arn
}

# 附加SSM和CloudWatch的策略到角色
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# 创建IAM实例配置文件
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "SSMProfile"
  role = aws_iam_role.ssm_role.name
}

# 创建EC2实例
resource "aws_instance" "example" {
  ami           = data.aws_ami.latest_amazon_linux.id
  subnet_id     = "subnet-0df6b76f43fc06500"
  instance_type = "t2.micro"
  key_name      = "ec2-billysun" # 替换为您的SSH密钥对名称
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  tags = {
    Name = "ExampleInstance"
  }
}

resource "aws_ssm_association" "install_cw_agent" {
  name = "AWS-ConfigureAWSPackage"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.example.id]
  }

  parameters = {
    action      = "Install"
    name        = "AmazonCloudWatchAgent"
    version     = "latest"
  }

  # schedule_expression = "rate(30 minutes)"  # Optional: Schedule to check/install updates every 30 minutes

  depends_on = [aws_instance.example]
}

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name  = "CloudWatchAgentConfiguration"
  type  = "String"
  value = <<EOF
{
  "metrics": {
    "metrics_collected": {
      "statsd": {
        "metrics_collection_interval": 10,
        "service_address": ":8125"
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": [
          "swap_used_percent"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/secure",
            "log_group_name": "${var.log_group_name}",
            "timestamp_format": "%b %d %H:%M:%S",
            "timezone": "Local"
          }
        ]
      }
    }
  }
}
EOF
}

# SSM Association to manage CloudWatch agent
resource "aws_ssm_association" "cw_agent" {
  name = "AmazonCloudWatch-ManageAgent"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.example.id]
  }

  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = "CloudWatchAgentConfiguration"
  }

  depends_on = [null_resource.check_ssm]

}

resource "null_resource" "check_ssm" {
  triggers = {
    instance_id = aws_instance.example.id
  }

  provisioner "local-exec" {
    command = "bash check_ssm_status.sh ${aws_instance.example.id} ${aws_ssm_association.install_cw_agent.association_id}"
  }
}

data "external" "check_log_group" {
  program = ["bash", "check_log_group.sh", var.log_group_name]
}

resource "aws_cloudwatch_log_group" "auth_log_group" {
  name = var.log_group_name
  count = data.external.check_log_group.result["exists"] == "false" ? 1 : 0
}

resource "aws_cloudwatch_log_metric_filter" "ssh_event_filter" {
  name           = "SSHEventFilter"
  log_group_name = var.log_group_name
  pattern        = "[month, day, time, host, process, msg01=\"Accepted\", msg02=\"publickey\" , msg03=\"for\", user, msg04=\"from\", src_ip, msg05=\"port\", port]"

  metric_transformation {
    name      = "SSHEventMatchCount"
    namespace = "SSHMonitoring"
    value     = "1"
  }
}

resource "aws_sns_topic" "ssh_alerts_topic" {
  name = "ssh-alerts-topic"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.ssh_alerts_topic.arn
  protocol  = "email"
  endpoint  = "billysun@amazon.com"  # 替换为你希望接收通知的电子邮件地址
}

resource "aws_cloudwatch_metric_alarm" "ssh_event_alarm" {
  alarm_name          = "SSH Access Alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "SSHEventMatchCount"
  namespace           = "SSHMonitoring"
  period              = "10"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alarm when SSH event logs exceed threshold"
  actions_enabled     = true

  alarm_actions = [
    aws_sns_topic.ssh_alerts_topic.arn
  ]
}

output "metric_filter_name" {
  value = aws_cloudwatch_log_metric_filter.ssh_event_filter.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.ssh_alerts_topic.arn
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.ssh_event_alarm.alarm_name
}
