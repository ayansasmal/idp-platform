#!/bin/bash

# Setup Local Development Environment
# This script sets up the local development environment with proper certificates and connections

set -euo pipefail

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

print_header() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $(printf "%-60s" "$1") ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
}

print_status() {
    echo -e "${PURPLE}[DEV-SETUP]${NC} $1"
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

# Check if platform is running
check_platform() {
    print_status "Checking if IDP platform is running..."
    
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Kubernetes cluster not accessible"
        return 1
    fi
    
    if ! kubectl get namespace argocd &>/dev/null; then
        print_error "ArgoCD not found. Run './scripts/idp.sh setup' first"
        return 1
    fi
    
    if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server | grep -q Running; then
        print_error "ArgoCD server not running. Run './scripts/idp.sh start' first"
        return 1
    fi
    
    print_success "Platform is running"
    return 0
}

# Extract certificates for local development
setup_certificates() {
    print_status "Extracting certificates for local development..."
    
    if [ -f "$SCRIPT_DIR/extract-certificates.sh" ]; then
        "$SCRIPT_DIR/extract-certificates.sh" extract
    else
        print_error "Certificate extraction script not found"
        return 1
    fi
    
    print_success "Certificates extracted"
}

# Setup environment variables
setup_environment() {
    print_status "Setting up development environment variables..."
    
    # Create environment file
    cat > "$ROOT_DIR/.env.development" << EOF
# IDP Platform Development Environment
# Source this file: source .env.development

# Certificate paths
export NODE_EXTRA_CA_CERTS="\$(pwd)/.certs/argocd-ca.crt"
export CURL_CA_BUNDLE="\$(pwd)/.certs/argocd-ca.crt"
export REQUESTS_CA_BUNDLE="\$(pwd)/.certs/argocd-ca.crt"

# ArgoCD credentials
export ARGOCD_USERNAME="admin"
export ARGOCD_PASSWORD="\$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo 'admin')"

# ArgoCD URLs
export ARGOCD_SERVER_URL="https://localhost:8443"
export ARGOCD_CLUSTER_URL="https://argocd-server.argocd.svc.cluster.local:443"

# Unleash configuration
export UNLEASH_URL="http://localhost:4243"
export UNLEASH_USERNAME="admin"
export UNLEASH_PASSWORD="unleash4all"

# Backstage URLs
export BACKSTAGE_URL="http://localhost:3000"

# Development flags
export NODE_TLS_REJECT_UNAUTHORIZED="0"  # Only for development!
export IDP_ENVIRONMENT="development"

echo "IDP Development environment loaded!"
echo "ArgoCD URL: \$ARGOCD_SERVER_URL"
echo "Unleash URL: \$UNLEASH_URL"
echo "Backstage URL: \$BACKSTAGE_URL"
EOF

    print_success "Environment file created at .env.development"
}

# Start necessary port forwards
start_port_forwards() {
    print_status "Starting development port forwards..."
    
    # Kill existing port forwards
    pkill -f "kubectl port-forward.*argocd" 2>/dev/null || true
    pkill -f "kubectl port-forward.*unleash" 2>/dev/null || true
    pkill -f "kubectl port-forward.*backstage" 2>/dev/null || true
    
    sleep 2
    
    # Start ArgoCD port forward (HTTPS)
    print_status "Starting ArgoCD port forward (https://localhost:8443)..."
    kubectl port-forward -n argocd svc/argocd-server 8443:443 > /dev/null 2>&1 &
    
    # Start Unleash port forward
    if kubectl get svc unleash -n unleash &>/dev/null; then
        print_status "Starting Unleash port forward (http://localhost:4243)..."
        kubectl port-forward -n unleash svc/unleash 4243:4242 > /dev/null 2>&1 &
    fi
    
    # Start Backstage port forward
    if kubectl get svc backstage -n backstage &>/dev/null; then
        print_status "Starting Backstage port forward (http://localhost:3000)..."
        kubectl port-forward -n backstage svc/backstage 3000:80 > /dev/null 2>&1 &
    fi
    
    # Wait for connections to establish
    sleep 5
    
    print_success "Port forwards started"
}

# Verify connections
verify_connections() {
    print_status "Verifying development connections..."
    
    # Test ArgoCD
    if curl -k -s https://localhost:8443/api/version &>/dev/null; then
        print_success "✓ ArgoCD HTTPS accessible at https://localhost:8443"
    else
        print_warning "⚠ ArgoCD HTTPS not responding (may need more time)"
    fi
    
    # Test ArgoCD with certificate
    if curl --cacert "$ROOT_DIR/.certs/argocd-ca.crt" -s https://localhost:8443/api/version &>/dev/null; then
        print_success "✓ ArgoCD certificate validation working"
    else
        print_warning "⚠ ArgoCD certificate validation failed"
    fi
    
    # Test Unleash
    if curl -s http://localhost:4243/health &>/dev/null; then
        print_success "✓ Unleash accessible at http://localhost:4243"
    else
        print_warning "⚠ Unleash not responding"
    fi
    
    # Test Backstage
    if curl -s http://localhost:3000 &>/dev/null; then
        print_success "✓ Backstage accessible at http://localhost:3000"
    else
        print_warning "⚠ Backstage not responding"
    fi
}

# Create development helper scripts
create_helpers() {
    print_status "Creating development helper scripts..."
    
    # ArgoCD login helper
    cat > "$ROOT_DIR/dev-argocd-login.sh" << 'EOF'
#!/bin/bash
# ArgoCD CLI login helper for development

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login localhost:8443 --username admin --password "$ARGOCD_PASSWORD" --cacert .certs/argocd-ca.crt

echo "ArgoCD CLI logged in successfully!"
echo "Try: argocd app list"
EOF
    chmod +x "$ROOT_DIR/dev-argocd-login.sh"
    
    # Development status checker
    cat > "$ROOT_DIR/dev-status.sh" << 'EOF'
#!/bin/bash
# Development environment status checker

echo "=== IDP Development Environment Status ==="
echo ""

# Check port forwards
echo "Port Forwards:"
if curl -k -s https://localhost:8443/api/version &>/dev/null; then
    echo "  ✓ ArgoCD HTTPS: https://localhost:8443"
else
    echo "  ✗ ArgoCD HTTPS: Not responding"
fi

if curl -s http://localhost:4243/health &>/dev/null; then
    echo "  ✓ Unleash: http://localhost:4243"
else
    echo "  ✗ Unleash: Not responding"
fi

if curl -s http://localhost:3000 &>/dev/null; then
    echo "  ✓ Backstage: http://localhost:3000"
else
    echo "  ✗ Backstage: Not responding"
fi

echo ""

# Check certificates
echo "Certificates:"
if [ -f ".certs/argocd-ca.crt" ]; then
    EXPIRY=$(openssl x509 -in .certs/argocd-ca.crt -noout -enddate | cut -d= -f2)
    echo "  ✓ CA Certificate: Valid until $EXPIRY"
else
    echo "  ✗ CA Certificate: Not found"
fi

echo ""

# Check environment
echo "Environment Variables:"
if [ -n "${NODE_EXTRA_CA_CERTS:-}" ]; then
    echo "  ✓ NODE_EXTRA_CA_CERTS: $NODE_EXTRA_CA_CERTS"
else
    echo "  ⚠ NODE_EXTRA_CA_CERTS: Not set (run: source .env.development)"
fi

if [ -n "${ARGOCD_PASSWORD:-}" ]; then
    echo "  ✓ ARGOCD_PASSWORD: Set"
else
    echo "  ⚠ ARGOCD_PASSWORD: Not set (run: source .env.development)"
fi
EOF
    chmod +x "$ROOT_DIR/dev-status.sh"
    
    print_success "Helper scripts created (dev-argocd-login.sh, dev-status.sh)"
}

# Show usage instructions
show_instructions() {
    print_header "Development Environment Ready"
    
    echo -e "${GREEN}🎉 Local development environment setup complete!${NC}\n"
    
    echo -e "${BLUE}📋 Quick Start:${NC}"
    echo -e "  1. Load environment: ${YELLOW}source .env.development${NC}"
    echo -e "  2. Check status: ${YELLOW}./dev-status.sh${NC}"
    echo -e "  3. Login to ArgoCD CLI: ${YELLOW}./dev-argocd-login.sh${NC}\n"
    
    echo -e "${BLUE}🔗 Access URLs:${NC}"
    echo -e "  • ArgoCD UI: ${YELLOW}https://localhost:8443${NC} (admin / <from env>)"
    echo -e "  • Unleash UI: ${YELLOW}http://localhost:4243${NC} (admin / unleash4all)"
    echo -e "  • Backstage UI: ${YELLOW}http://localhost:3000${NC}\n"
    
    echo -e "${BLUE}🛠 Development Tools:${NC}"
    echo -e "  • Certificates: ${YELLOW}.certs/${NC} directory"
    echo -e "  • Environment: ${YELLOW}.env.development${NC} file"
    echo -e "  • Helpers: ${YELLOW}dev-*.sh${NC} scripts\n"
    
    echo -e "${BLUE}📚 Usage Examples:${NC}"
    echo -e "  Node.js: ${YELLOW}NODE_EXTRA_CA_CERTS=.certs/argocd-ca.crt node app.js${NC}"
    echo -e "  cURL: ${YELLOW}curl --cacert .certs/argocd-ca.crt https://localhost:8443/api/version${NC}"
    echo -e "  Python: ${YELLOW}requests.get(url, verify='.certs/argocd-ca.crt')${NC}\n"
    
    print_success "Development environment ready for use!"
}

# Main execution
main() {
    print_header "IDP Local Development Setup"
    
    if ! check_platform; then
        print_error "Platform not ready. Run './scripts/idp.sh setup && ./scripts/idp.sh start' first"
        exit 1
    fi
    
    setup_certificates
    setup_environment
    start_port_forwards
    verify_connections
    create_helpers
    show_instructions
}

# Handle command line arguments
case "${1:-setup}" in
    "setup"|"")
        main
        ;;
    "status")
        if [ -f "$ROOT_DIR/dev-status.sh" ]; then
            "$ROOT_DIR/dev-status.sh"
        else
            print_error "Development status script not found. Run setup first."
        fi
        ;;
    "clean")
        print_status "Cleaning development environment..."
        pkill -f "kubectl port-forward" 2>/dev/null || true
        rm -f "$ROOT_DIR/.env.development"
        rm -f "$ROOT_DIR/dev-argocd-login.sh"
        rm -f "$ROOT_DIR/dev-status.sh"
        rm -rf "$ROOT_DIR/.certs"
        print_success "Development environment cleaned"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [setup|status|clean|help]"
        echo ""
        echo "Commands:"
        echo "  setup  - Setup local development environment (default)"
        echo "  status - Check development environment status"
        echo "  clean  - Clean development environment"
        echo "  help   - Show this help message"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac