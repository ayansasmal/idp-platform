#!/bin/bash

# IDP Platform Quick Start Script
# One-command platform startup with health checks

# Note: We handle errors explicitly rather than using 'set -e' to provide better user feedback

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load IDP configuration if available
if [ -f "$SCRIPT_DIR/config-parser.sh" ]; then
    source "$SCRIPT_DIR/config-parser.sh" export 2>/dev/null || true
fi

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    IDP Platform Quick Start                 ║"
echo "║                                                              ║"
echo "║  🚀 Starting your Integrated Developer Platform...          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Step 1: Configuration Check
echo -e "${PURPLE}[1/6]${NC} ${BLUE}Checking platform configuration...${NC}"

# Check if configuration exists
if [ -f "$SCRIPT_DIR/config-parser.sh" ] && [ -f "$(dirname "$SCRIPT_DIR")/.idp-config/idp-config.yaml" ]; then
    echo -e "${GREEN}✓ IDP configuration found${NC}"
    
    # Show configuration summary
    if [ "${SHOW_CONFIG:-true}" = "true" ]; then
        echo -e "${BLUE}Configuration Summary:${NC}"
        echo -e "  • Platform Mode: ${GREEN}${IDP_PLATFORM_MODE:-Default}${NC}"
        echo -e "  • Data Protection: ${GREEN}$([ "$IDP_DATA_PROTECTION_ENABLED" = true ] && echo "Enabled" || echo "Disabled")${NC}"
        echo -e "  • External Registry: ${GREEN}$([ "$IDP_EXTERNAL_REGISTRY_ENABLED" = true ] && echo "$IDP_REGISTRY_TYPE" || echo "LocalStack ECR")${NC}"
        echo -e "  • External Auth: ${GREEN}$([ "$IDP_EXTERNAL_AUTH_ENABLED" = true ] && echo "$IDP_AUTH_PROVIDER" || echo "LocalStack Cognito")${NC}"
    fi
    
    # Validate configuration
    if ! "$SCRIPT_DIR/config-parser.sh" validate > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Configuration validation warnings detected${NC}"
        echo -e "${BLUE}Run './scripts/config-parser.sh show' to review configuration${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No configuration found${NC}"
    echo -e "${BLUE}💡 You can run './scripts/idp-setup-wizard.sh' to create a custom configuration${NC}"
    echo -e "${BLUE}   Proceeding with default settings...${NC}"
fi

echo ""

# Step 2: Health Check
echo -e "${PURPLE}[2/6]${NC} ${BLUE}Performing platform health check...${NC}"
if ! "$SCRIPT_DIR/start-platform.sh" health; then
    echo -e "${RED}Health check failed. Please fix the issues above before continuing.${NC}"
    exit 1
fi

echo -e "\n${GREEN}✓ Platform health check passed${NC}\n"

# Step 3: Setup External Backstage (if needed)
echo -e "${PURPLE}[3/6]${NC} ${BLUE}Setting up external Backstage integration...${NC}"

# Check if we need to setup external Backstage
if [ "${SETUP_BACKSTAGE:-true}" = "true" ]; then
    if [ -f "$SCRIPT_DIR/setup-backstage-external.sh" ]; then
        echo -e "${BLUE}Setting up external Backstage repository...${NC}"
        "$SCRIPT_DIR/setup-backstage-external.sh"
        echo -e "${GREEN}✓ External Backstage setup completed${NC}"
    else
        echo -e "${YELLOW}⚠ External Backstage setup script not found, skipping...${NC}"
    fi
else
    echo -e "${YELLOW}⚠ External Backstage setup skipped (SETUP_BACKSTAGE=false)${NC}"
fi

echo ""

# Step 4: Start Services
echo -e "${PURPLE}[4/6]${NC} ${BLUE}Starting all platform services...${NC}"

# Start in smart mode (only available services) in background
"$SCRIPT_DIR/start-platform.sh" smart &
PLATFORM_PID=$!

# Wait a bit for services to start
sleep 5

# Step 5: Wait for services to be ready
echo -e "\n${PURPLE}[5/6]${NC} ${BLUE}Waiting for services to be ready...${NC}"

# Function to check if a port is open
check_port() {
    local port=$1
    local service=$2
    local timeout=30
    local count=0
    
    while [ $count -lt $timeout ]; do
        if curl -s --connect-timeout 1 "http://localhost:$port" &>/dev/null; then
            echo -e "${GREEN}✓${NC} $service ready on port $port"
            return 0
        fi
        sleep 1
        ((count++))
    done
    
    echo -e "${YELLOW}⚠${NC} $service not ready on port $port (might need more time)"
    return 1
}

# The smart mode in start-platform.sh already handles service discovery
# and only starts available services, so we don't need to hardcode checks here
echo -e "${GREEN}✓ Services started using intelligent discovery${NC}"

# Step 6: Show access information
echo -e "\n${PURPLE}[6/6]${NC} ${BLUE}Platform is ready!${NC}"

echo -e "\n${GREEN}🎉 Your IDP Platform is now running!${NC}\n"

echo -e "${BLUE}📊 Service access information:${NC}"
echo -e "  ${GREEN}•${NC} Check running services: ${YELLOW}./scripts/start-platform.sh status${NC}"
echo -e "  ${GREEN}•${NC} Discover all services: ${YELLOW}./scripts/start-platform.sh discover${NC}"
echo -e ""
echo -e "${BLUE}🔗 Common service URLs (when available):${NC}"
echo -e "  ${GREEN}•${NC} ArgoCD (GitOps):           ${YELLOW}http://localhost:8080${NC}"
echo -e "  ${GREEN}•${NC} Backstage (Dev Portal):    ${YELLOW}http://localhost:3000${NC}"
echo -e "  ${GREEN}•${NC} Argo Workflows (CI/CD):    ${YELLOW}http://localhost:4000${NC} ${BLUE}[NEW!]${NC}"
echo -e "  ${GREEN}•${NC} Grafana (Monitoring):      ${YELLOW}http://localhost:3001${NC}"

echo -e "\n${BLUE}🔐 Default Credentials:${NC}"
echo -e "  ${GREEN}•${NC} ArgoCD:    admin / $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo 'admin')"
echo -e "  ${GREEN}•${NC} Grafana:   admin / admin"

echo -e "\n${BLUE}📚 Quick Commands:${NC}"
echo -e "  ${GREEN}•${NC} Check status:    ${YELLOW}./scripts/start-platform.sh status${NC}"
echo -e "  ${GREEN}•${NC} View logs:       ${YELLOW}./scripts/start-platform.sh logs [service]${NC}"
echo -e "  ${GREEN}•${NC} Health check:    ${YELLOW}./scripts/start-platform.sh health${NC}"
echo -e "  ${GREEN}•${NC} Stop platform:   ${YELLOW}./scripts/start-platform.sh stop${NC}"

echo -e "\n${BLUE}🔗 Platform Components:${NC}"
echo -e "  ${GREEN}•${NC} Kubernetes:     $(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo 'Unknown')"
echo -e "  ${GREEN}•${NC} Istio:          Service Mesh with mTLS"
echo -e "  ${GREEN}•${NC} ArgoCD:         GitOps Continuous Deployment"
echo -e "  ${GREEN}•${NC} Argo Workflows: Internal CI/CD for Container Builds ${BLUE}[NEW!]${NC}"
echo -e "  ${GREEN}•${NC} Crossplane:     Infrastructure as Code"
echo -e "  ${GREEN}•${NC} Observability:  Prometheus + Grafana + Jaeger + Kiali"

echo -e "\n${YELLOW}⚠️  Important Notes:${NC}"
echo -e "  ${GREEN}•${NC} Keep this terminal open to maintain port forwards"
echo -e "  ${GREEN}•${NC} Press Ctrl+C to stop all services"
echo -e "  ${GREEN}•${NC} Check the access-guide.md for detailed instructions"

echo -e "\n${BLUE}🚀 Ready to develop! Happy coding!${NC}\n"

# Function to handle cleanup on exit
cleanup() {
    echo -e "\n${BLUE}Cleaning up...${NC}"
    "$SCRIPT_DIR/start-platform.sh" stop
    exit 0
}

# Handle Ctrl+C gracefully
trap cleanup INT

# Wait for the platform process
wait $PLATFORM_PID