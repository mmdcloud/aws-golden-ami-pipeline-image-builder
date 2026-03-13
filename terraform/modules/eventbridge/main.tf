# EventBridge Rule for AMI Creation Notifications
resource "aws_cloudwatch_event_rule" "rule" {
  name        = var.rule_name
  description = var.description
  event_pattern = var.event_pattern
  tags = conca({},var.tags)
}

resource "aws_cloudwatch_event_target" "target" {
  rule      = aws_cloudwatch_event_rule.rule.name
  target_id = var.target_id
  arn       = var.target_arn
}