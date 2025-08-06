#!/bin/bash

# Setup Argo Workflows S3 artifacts with LocalStack
# This script creates the necessary S3 bucket and secrets for Argo Workflows

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${YELLOW}[ARTIFACTS]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if LocalStack is running
if ! docker ps | grep localstack > /dev/null; then
    print_error "LocalStack is not running. Please start LocalStack first."
    exit 1
fi

print_status "Setting up Argo Workflows S3 artifacts..."

# Create S3 bucket in LocalStack
print_status "Creating S3 bucket 'argo-artifacts' in LocalStack..."
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test aws s3 mb s3://argo-artifacts --endpoint-url=http://localhost:4566 --region=us-east-1

# Create Kubernetes secret for S3 access
print_status "Creating Kubernetes secret for S3 access..."
kubectl create secret generic argo-artifacts -n argo-workflows \
  --from-literal=accesskey=test \
  --from-literal=secretkey=test \
  --dry-run=client -o yaml | kubectl apply -f -

print_success "Argo Workflows S3 artifacts setup completed"
print_status "Bucket: s3://argo-artifacts (via LocalStack at localhost:4566)"