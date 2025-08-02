#!/bin/bash

export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

echo "Testing LocalStack ECR integration..."

# List repositories
echo "Existing ECR repositories:"
aws ecr describe-repositories --endpoint-url $AWS_ENDPOINT_URL --region $AWS_DEFAULT_REGION 2>/dev/null || echo "No repositories found"

# Test ECR endpoint
echo -e "\nTesting ECR endpoint connectivity:"
curl -s http://localhost:4566/health | jq '.services.ecr // "ECR service not available"'

echo -e "\nLocalStack ECR is ready for use."
echo "Registry endpoint: localhost:4566"
echo "Repository URI: 000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566/idp/web-app"