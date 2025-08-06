#!/bin/bash

# External Backstage Setup Script
# Clones, builds, and integrates external Backstage repository with IDP platform

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
# Update this URL to point to your actual GitHub repository for the Backstage app
BACKSTAGE_REPO_URL="${BACKSTAGE_REPO_URL:-https://github.com/ayansasmal/idp-backstage-app.git}"
BACKSTAGE_BRANCH="${BACKSTAGE_BRANCH:-main}"
BACKSTAGE_DIR="$ROOT_DIR/../idp-backstage-app"
IMAGE_NAME="idp/backstage-app"
IMAGE_TAG="${BACKSTAGE_IMAGE_TAG:-latest}"
REGISTRY="000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              External Backstage Setup & Integration         ║"
echo "║                                                              ║"
echo "║  🏗️  Setting up Backstage app for IDP Platform...          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print status
print_status() {
    echo -e "${PURPLE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Step 1: Clone or update Backstage repository
echo -e "${PURPLE}[1/6]${NC} ${BLUE}Setting up Backstage repository...${NC}"

if [ -d "$BACKSTAGE_DIR" ]; then
    print_status "Backstage directory exists, updating..."
    cd "$BACKSTAGE_DIR"
    git fetch origin
    git checkout "$BACKSTAGE_BRANCH"
    git pull origin "$BACKSTAGE_BRANCH"
    print_success "Backstage repository updated"
else
    print_status "Cloning Backstage repository..."
    git clone "$BACKSTAGE_REPO_URL" "$BACKSTAGE_DIR"
    cd "$BACKSTAGE_DIR"
    git checkout "$BACKSTAGE_BRANCH"
    print_success "Backstage repository cloned"
fi

# Step 2: Verify Backstage structure
echo -e "${PURPLE}[2/6]${NC} ${BLUE}Verifying Backstage project structure...${NC}"

if [ ! -f "$BACKSTAGE_DIR/package.json" ]; then
    print_error "package.json not found in Backstage repository"
    exit 1
fi

if [ ! -f "$BACKSTAGE_DIR/Dockerfile" ]; then
    print_warning "Dockerfile not found, checking for Dockerfile.multistage..."
    if [ ! -f "$BACKSTAGE_DIR/Dockerfile.multistage" ]; then
        print_error "No suitable Dockerfile found in Backstage repository"
        exit 1
    fi
    DOCKERFILE="Dockerfile.multistage"
else
    DOCKERFILE="Dockerfile"
fi

print_success "Backstage project structure verified"

# Step 3: Install dependencies and build
echo -e "${PURPLE}[3/6]${NC} ${BLUE}Installing dependencies and building Backstage...${NC}"

cd "$BACKSTAGE_DIR"

# Check if yarn is available
if ! command -v yarn &> /dev/null; then
    print_error "Yarn is required but not installed. Please install yarn first."
    exit 1
fi

print_status "Installing dependencies..."
yarn install --frozen-lockfile

print_status "Building Backstage application..."
yarn build:all

print_success "Backstage build completed"

# Step 4: Build container image
echo -e "${PURPLE}[4/6]${NC} ${BLUE}Building Backstage container image...${NC}"

# Check if docker is available
if ! command -v docker &> /dev/null; then
    print_error "Docker is required but not installed."
    exit 1
fi

print_status "Building container image: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"

# Build the image
docker build -f "$DOCKERFILE" -t "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG" .

# Also tag as latest for consistency
docker tag "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG" "$REGISTRY/$IMAGE_NAME:latest"

print_success "Container image built successfully"

# Step 5: Push to registry
echo -e "${PURPLE}[5/6]${NC} ${BLUE}Pushing image to registry...${NC}"

print_status "Pushing to LocalStack ECR..."
docker push "$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
docker push "$REGISTRY/$IMAGE_NAME:latest"

print_success "Image pushed to registry"

# Step 6: Update IDP platform deployment
echo -e "${PURPLE}[6/6]${NC} ${BLUE}Updating IDP platform deployment...${NC}"

cd "$ROOT_DIR"

# Update Backstage deployment with new image
DEPLOYMENT_FILE="applications/backstage/backstage-deployment.yaml"
if [ -f "$DEPLOYMENT_FILE" ]; then
    print_status "Updating Backstage deployment manifest..."
    
    # Create backup
    cp "$DEPLOYMENT_FILE" "$DEPLOYMENT_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update image reference
    sed -i.tmp "s|image: .*idp/backstage-app.*|image: $REGISTRY/$IMAGE_NAME:$IMAGE_TAG|g" "$DEPLOYMENT_FILE"
    rm "$DEPLOYMENT_FILE.tmp"
    
    print_success "Deployment manifest updated"
else
    print_warning "Backstage deployment file not found at $DEPLOYMENT_FILE"
fi

# Trigger ArgoCD sync if available
if command -v kubectl &> /dev/null; then
    if kubectl get application backstage-platform -n argocd &> /dev/null; then
        print_status "Triggering ArgoCD sync for Backstage..."
        kubectl patch application backstage-platform -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge || true
        print_success "ArgoCD sync triggered"
    else
        print_warning "ArgoCD application 'backstage-platform' not found"
    fi
else
    print_warning "kubectl not available, cannot trigger ArgoCD sync"
fi

echo ""
echo -e "${GREEN}🎉 External Backstage setup completed successfully!${NC}"
echo ""
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Repository: ${BACKSTAGE_REPO_URL}"
echo -e "  • Branch: ${BACKSTAGE_BRANCH}"
echo -e "  • Image: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
echo -e "  • Location: ${BACKSTAGE_DIR}"
echo ""
echo -e "${BLUE}🚀 Next steps:${NC}"
echo -e "  • Backstage will be available at: http://localhost:3000"
echo -e "  • Monitor deployment: kubectl get pods -n backstage"
echo -e "  • Check ArgoCD: http://localhost:8080"
echo ""

# Optional: Show running pods
if command -v kubectl &> /dev/null; then
    echo -e "${BLUE}📦 Current Backstage pods:${NC}"
    kubectl get pods -n backstage -l app.kubernetes.io/name=backstage || echo "No Backstage pods found (deployment may be in progress)"
fi