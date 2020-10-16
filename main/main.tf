terraform {
  required_version = "0.12.29"
}

variable "event_names" {
  default = ["e1","e2","e3"]
}


provider "aws" {
  version = "~> 2.0"
}

provider "template" {
  version = "~> 2.0"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "test-topic" {
  count = length(var.event_names)
  name  = var.event_names[count.index]
}

resource "aws_sqs_queue" "test-event-queue" {
  name = "test-event-queue"
}

resource "aws_sns_topic_subscription" "sns-subscriptions" {
  count = length(var.event_names)
  topic_arn = format("arn:aws:sns:%s:%s:%s", data.aws_region.current.name, data.aws_caller_identity.current.account_id, var.event_names[count.index])
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.test-event-queue.arn
}
