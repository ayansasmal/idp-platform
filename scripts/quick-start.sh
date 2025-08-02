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

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    IDP Platform Quick Start                 ║"
echo "║                                                              ║"
echo "║  🚀 Starting your Integrated Developer Platform...          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Step 1: Health Check
echo -e "${PURPLE}[1/4]${NC} ${BLUE}Performing platform health check...${NC}"
if ! "$SCRIPT_DIR/start-platform.sh" health; then
    echo -e "${RED}Health check failed. Please fix the issues above before continuing.${NC}"
    exit 1
fi

echo -e "\n${GREEN}✓ Platform health check passed${NC}\n"

# Step 2: Start Services
echo -e "${PURPLE}[2/4]${NC} ${BLUE}Starting all platform services...${NC}"

# Start in background to get immediate feedback
"$SCRIPT_DIR/start-platform.sh" start &
PLATFORM_PID=$!

# Wait a bit for services to start
sleep 5

# Step 3: Wait for services to be ready
echo -e "\n${PURPLE}[3/4]${NC} ${BLUE}Waiting for services to be ready...${NC}"

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

# Check critical services
declare CRITICAL_SERVICES=(
    ["8080"]="ArgoCD"
    ["3000"]="Backstage"
    ["3001"]="Grafana"
)

for port in "${!CRITICAL_SERVICES[@]}"; do
    check_port "$port" "${CRITICAL_SERVICES[$port]}"
done

# Step 4: Show access information
echo -e "\n${PURPLE}[4/4]${NC} ${BLUE}Platform is ready!${NC}"

echo -e "\n${GREEN}🎉 Your IDP Platform is now running!${NC}\n"

echo -e "${BLUE}📊 Access your services:${NC}"
echo -e "  ${GREEN}•${NC} ArgoCD (GitOps):           ${YELLOW}http://localhost:8080${NC}"
echo -e "  ${GREEN}•${NC} Backstage (Dev Portal):    ${YELLOW}http://localhost:3000${NC}"
echo -e "  ${GREEN}•${NC} Grafana (Monitoring):      ${YELLOW}http://localhost:3001${NC}"
echo -e "  ${GREEN}•${NC} Prometheus (Metrics):      ${YELLOW}http://localhost:9090${NC}"
echo -e "  ${GREEN}•${NC} Jaeger (Tracing):          ${YELLOW}http://localhost:16686${NC}"
echo -e "  ${GREEN}•${NC} Kiali (Service Mesh):      ${YELLOW}http://localhost:20001${NC}"
echo -e "  ${GREEN}•${NC} Monitoring Dashboard:      ${YELLOW}http://localhost:8090${NC}"

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