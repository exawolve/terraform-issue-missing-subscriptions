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

module "sqs" {
  source = "./module"
  event_names = var.event_names
  queue-name = "test-event-queue"
}

