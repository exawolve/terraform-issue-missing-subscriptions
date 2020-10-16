data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

variable "queue-name" {
  default = ""
}

variable "event_names" {
  default = []
}

resource "aws_sqs_queue" "test-event-queue" {
  name = var.queue-name
}

resource "aws_sns_topic_subscription" "sns-subscriptions" {
  for_each  = toset(var.event_names)
  topic_arn = format("arn:aws:sns:%s:%d:%s", data.aws_region.current.name, data.aws_caller_identity.current.account_id, each.key)
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.test-event-queue.arn
}
