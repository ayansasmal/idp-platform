#!/bin/bash

# Configure Docker to work with LocalStack ECR
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Create ECR repository if it doesn't exist
aws ecr create-repository \
    --repository-name idp/web-app \
    --endpoint-url $AWS_ENDPOINT_URL \
    --region $AWS_DEFAULT_REGION || true

# Get ECR login token and configure Docker
ECR_TOKEN=$(aws ecr get-login-password --endpoint-url $AWS_ENDPOINT_URL --region $AWS_DEFAULT_REGION)
echo $ECR_TOKEN | docker login --username AWS --password-stdin localhost:4566

echo "LocalStack ECR registry configured at: localhost:4566"
echo "To push images, use: docker tag <image> localhost:4566/idp/web-app:<tag>"
echo "Then: docker push localhost:4566/idp/web-app:<tag>"