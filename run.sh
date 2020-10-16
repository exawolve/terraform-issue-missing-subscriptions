#!/bin/bash

cd main
rm -rf .terraform && terraform init -no-color
terraform apply -auto-approve -no-color
cd ../module
rm -rf .terraform && terraform init -no-color
terraform state mv aws_sqs_queue.test-event-queue module.sqs.aws_sqs_queue.test-event-queue -no-color
for i in {0..2}; do terraform state mv aws_sns_topic_subscription.sns-subscriptions[$i] module.sqs.aws_sns_topic_subscription.sns-subscriptions[$i] -no-color; done
terraform apply -auto-approve -no-color
rm -rf .terraform && terraform init -no-color
terraform plan -no-color
echo "running plan one more time..."
terraform plan -no-color
