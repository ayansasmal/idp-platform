#!/bin/bash

# Deploy Argo Workflows Templates
# This script handles deployment of custom workflow templates after Argo Workflows is ready

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${YELLOW}[WORKFLOWS]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="$ROOT_DIR/platform/workflows"

print_status "Deploying Argo Workflows templates..."

# Check if Argo Workflows is running
if ! kubectl get namespace argo-workflows &> /dev/null; then
    print_error "Argo Workflows namespace not found. Run platform setup first."
    exit 1
fi

# Wait for Argo Workflows server to be ready
print_status "Waiting for Argo Workflows server to be ready..."
kubectl wait --for=condition=Available deployment/argo-workflows-server -n argo-workflows --timeout=120s || {
    print_error "Argo Workflows server not ready"
    exit 1
}

# Deploy workflow templates with error handling
if [ -d "$WORKFLOWS_DIR" ]; then
    print_status "Applying workflow templates from $WORKFLOWS_DIR..."
    
    # Apply each file individually for better error handling
    for file in "$WORKFLOWS_DIR"/*.yaml; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            print_status "Applying $filename..."
            
            if kubectl apply -f "$file"; then
                print_success "Applied $filename"
            else
                print_error "Failed to apply $filename (continuing...)"
            fi
        fi
    done
    
    print_success "Workflow templates deployment completed"
    
    # Display summary
    echo ""
    print_status "Deployed resources summary:"
    kubectl get workflowtemplates -n argo-workflows --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  • WorkflowTemplates: {}"
    kubectl get workflows -n argo-workflows --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  • Workflows: {}"
    kubectl get secrets -n argo-workflows --no-headers 2>/dev/null | grep -E "(ecr-credentials|kubeconfig)" | wc -l | xargs -I {} echo "  • Workflow Secrets: {}"
    
else
    print_error "Workflows directory not found: $WORKFLOWS_DIR"
    exit 1
fi

print_success "Workflow templates are ready for use in Argo Workflows UI"