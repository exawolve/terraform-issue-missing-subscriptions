## Missing AWS SNS subscriptions after state move

AWS SNS might result in some SNS subscriptions missing, after moving state and recreating resources.

terraform should make sure resources are deleted before recreating, but seems to end up in a race condition or something occasionally.

Strange about this, is also that an initial `terraform plan` states the infrastructure to be in sync.
When doing a follow up `terraform plan` the missing resources show up, though.

See [this git repo](https://github.com/exawolve/terraform-issue-missing-subscriptions) to reproduce this issue.

### description
Given the following SQS/SNS infrastructure:
```hcl-terraform
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
```
---
When switching to the following module based infrastructure:
```hcl-terraform
resource "aws_sns_topic" "test-topic" {
  count = length(var.event_names)
  name  = var.event_names[count.index]
}

module "sqs" {
  source = "./module"
  event_names = var.event_names
  queue-name = "test-event-queue"
}
```
with the `./module`:
```hcl-terraform
resource "aws_sqs_queue" "test-event-queue" {
  name = var.queue-name
}

resource "aws_sns_topic_subscription" "sns-subscriptions" {
  for_each  = toset(var.event_names)
  topic_arn = format("arn:aws:sns:%s:%d:%s", data.aws_region.current.name, data.aws_caller_identity.current.account_id, each.key)
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.test-event-queue.arn
}
```
---
and moving state like:
```bash
terraform state mv aws_sqs_queue.test-event-queue module.sqs.aws_sqs_queue.test-event-queue -no-color
for i in {0..2}; do terraform state mv aws_sns_topic_subscription.sns-subscriptions[$i] module.sqs.aws_sns_topic_subscription.sns-subscriptions[$i] -no-color; done
```
you will end up **occasionally** with the SNS subscriptions missing.

(another issue here as a side note:
moving state will result in new subscriptions being recreated, because `each` in `aws_sns_topic_subscription` type is changed from `list` to `map`.)

This will usually show up only, when doing a `terraform plan` for the 2nd time...

## Reproduce
See the script [run.sh](./run.sh) to reproduce.

Yet **TODO:** provide some terraform S3 backend:
```hcl-terraform
terraform {
  backend "s3" {
    [...]
  }
}
``` 

### Output from [run.sh](./run.sh) script run 
```
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
- Checking for available provider plugins...
- Downloading plugin for provider "template" (hashicorp/template) 2.2.0...
- Downloading plugin for provider "aws" (hashicorp/aws) 2.70.0...

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
data.aws_caller_identity.current: Refreshing state...
data.aws_region.current: Refreshing state...
aws_sns_topic.test-topic[1]: Creating...
aws_sqs_queue.test-event-queue: Creating...
aws_sns_topic.test-topic[2]: Creating...
aws_sns_topic.test-topic[0]: Creating...
aws_sns_topic.test-topic[1]: Creation complete after 0s id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2]
aws_sns_topic.test-topic[2]: Creation complete after 0s [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3]
aws_sns_topic.test-topic[0]: Creation complete after 0s [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1]
aws_sqs_queue.test-event-queue: Creation complete after 0s [id=https://sqs.eu-central-1.amazonaws.com/xxxxxxxxxxxx/test-event-queue]
aws_sns_topic_subscription.sns-subscriptions[0]: Creating...
aws_sns_topic_subscription.sns-subscriptions[2]: Creating...
aws_sns_topic_subscription.sns-subscriptions[1]: Creating...
aws_sns_topic_subscription.sns-subscriptions[2]: Creation complete after 1s [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3:0bb667d2-04ec-4794-a40c-7089a0a78118]
aws_sns_topic_subscription.sns-subscriptions[1]: Creation complete after 1s [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2:4ae5580d-24eb-430d-9bca-72daf8079e8b]
aws_sns_topic_subscription.sns-subscriptions[0]: Creation complete after 1s [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1:bc529eef-8bfc-404e-b846-f9677ebd9ede]

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.
```

```
Initializing modules...
- sqs in module

Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
- Checking for available provider plugins...
- Downloading plugin for provider "template" (hashicorp/template) 2.2.0...
- Downloading plugin for provider "aws" (hashicorp/aws) 2.70.0...

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
Move "aws_sqs_queue.test-event-queue" to "module.sqs.aws_sqs_queue.test-event-queue"
Successfully moved 1 object(s).
Move "aws_sns_topic_subscription.sns-subscriptions[0]" to "module.sqs.aws_sns_topic_subscription.sns-subscriptions[0]"
Successfully moved 1 object(s).
Move "aws_sns_topic_subscription.sns-subscriptions[1]" to "module.sqs.aws_sns_topic_subscription.sns-subscriptions[1]"
Successfully moved 1 object(s).
Move "aws_sns_topic_subscription.sns-subscriptions[2]" to "module.sqs.aws_sns_topic_subscription.sns-subscriptions[2]"
Successfully moved 1 object(s).
data.aws_caller_identity.current: Refreshing state...
module.sqs.data.aws_caller_identity.current: Refreshing state...
module.sqs.aws_sqs_queue.test-event-queue: Refreshing state... [id=https://sqs.eu-central-1.amazonaws.com/xxxxxxxxxxxx/test-event-queue]
module.sqs.data.aws_region.current: Refreshing state...
data.aws_region.current: Refreshing state...
aws_sns_topic.test-topic[0]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1]
aws_sns_topic.test-topic[2]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3]
aws_sns_topic.test-topic[1]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2]
module.sqs.aws_sns_topic_subscription.sns-subscriptions: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1:bc529eef-8bfc-404e-b846-f9677ebd9ede]
module.sqs.aws_sns_topic_subscription.sns-subscriptions[1]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2:4ae5580d-24eb-430d-9bca-72daf8079e8b]
module.sqs.aws_sns_topic_subscription.sns-subscriptions[2]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3:0bb667d2-04ec-4794-a40c-7089a0a78118]
module.sqs.aws_sns_topic_subscription.sns-subscriptions[2]: Destroying... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3:0bb667d2-04ec-4794-a40c-7089a0a78118]
module.sqs.aws_sns_topic_subscription.sns-subscriptions: Destroying... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1:bc529eef-8bfc-404e-b846-f9677ebd9ede]
module.sqs.aws_sns_topic_subscription.sns-subscriptions[1]: Destroying... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2:4ae5580d-24eb-430d-9bca-72daf8079e8b]
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e2"]: Creating...
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e1"]: Creating...
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e3"]: Creating...
module.sqs.aws_sns_topic_subscription.sns-subscriptions: Destruction complete after 1s
module.sqs.aws_sns_topic_subscription.sns-subscriptions[2]: Destruction complete after 1s
module.sqs.aws_sns_topic_subscription.sns-subscriptions[1]: Destruction complete after 1s
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e1"]: Creation complete after 1s [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1:bc529eef-8bfc-404e-b846-f9677ebd9ede]
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e2"]: Creation complete after 1s [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2:4ae5580d-24eb-430d-9bca-72daf8079e8b]
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e3"]: Creation complete after 1s [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3:1d42d9bd-f120-448e-ae73-a5b4345d6fa7]

Apply complete! Resources: 3 added, 0 changed, 3 destroyed.
```

```
Initializing modules...
- sqs in module

Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
- Checking for available provider plugins...
- Downloading plugin for provider "aws" (hashicorp/aws) 2.70.0...
- Downloading plugin for provider "template" (hashicorp/template) 2.2.0...

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but will not be
persisted to local or remote state storage.

data.aws_region.current: Refreshing state...
aws_sns_topic.test-topic[0]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1]
data.aws_caller_identity.current: Refreshing state...
module.sqs.data.aws_caller_identity.current: Refreshing state...
module.sqs.data.aws_region.current: Refreshing state...
aws_sns_topic.test-topic[2]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3]
aws_sns_topic.test-topic[1]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2]
module.sqs.aws_sqs_queue.test-event-queue: Refreshing state... [id=https://sqs.eu-central-1.amazonaws.com/xxxxxxxxxxxx/test-event-queue]
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e3"]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3:1d42d9bd-f120-448e-ae73-a5b4345d6fa7]
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e1"]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1:bc529eef-8bfc-404e-b846-f9677ebd9ede]
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e2"]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2:4ae5580d-24eb-430d-9bca-72daf8079e8b]

------------------------------------------------------------------------

No changes. Infrastructure is up-to-date.

This means that Terraform did not detect any differences between your
configuration and real physical resources that exist. As a result, no
actions need to be performed.
```

#### running plan one more time...
```
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but will not be
persisted to local or remote state storage.

aws_sns_topic.test-topic[1]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2]
data.aws_region.current: Refreshing state...
data.aws_caller_identity.current: Refreshing state...
aws_sns_topic.test-topic[2]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3]
aws_sns_topic.test-topic[0]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1]
module.sqs.data.aws_caller_identity.current: Refreshing state...
module.sqs.data.aws_region.current: Refreshing state...
module.sqs.aws_sqs_queue.test-event-queue: Refreshing state... [id=https://sqs.eu-central-1.amazonaws.com/xxxxxxxxxxxx/test-event-queue]
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e2"]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2:4ae5580d-24eb-430d-9bca-72daf8079e8b]
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e1"]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1:bc529eef-8bfc-404e-b846-f9677ebd9ede]
module.sqs.aws_sns_topic_subscription.sns-subscriptions["e3"]: Refreshing state... [id=arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e3:1d42d9bd-f120-448e-ae73-a5b4345d6fa7]

------------------------------------------------------------------------

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # module.sqs.aws_sns_topic_subscription.sns-subscriptions["e1"] will be created
  + resource "aws_sns_topic_subscription" "sns-subscriptions" {
      + arn                             = (known after apply)
      + confirmation_timeout_in_minutes = 1
      + endpoint                        = "arn:aws:sqs:eu-central-1:xxxxxxxxxxxx:test-event-queue"
      + endpoint_auto_confirms          = false
      + id                              = (known after apply)
      + protocol                        = "sqs"
      + raw_message_delivery            = false
      + topic_arn                       = "arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e1"
    }

  # module.sqs.aws_sns_topic_subscription.sns-subscriptions["e2"] will be created
  + resource "aws_sns_topic_subscription" "sns-subscriptions" {
      + arn                             = (known after apply)
      + confirmation_timeout_in_minutes = 1
      + endpoint                        = "arn:aws:sqs:eu-central-1:xxxxxxxxxxxx:test-event-queue"
      + endpoint_auto_confirms          = false
      + id                              = (known after apply)
      + protocol                        = "sqs"
      + raw_message_delivery            = false
      + topic_arn                       = "arn:aws:sns:eu-central-1:xxxxxxxxxxxx:e2"
    }

Plan: 2 to add, 0 to change, 0 to destroy.

------------------------------------------------------------------------

Note: You didn't specify an "-out" parameter to save this plan, so Terraform
can't guarantee that exactly these actions will be performed if
"terraform apply" is subsequently run.
```

