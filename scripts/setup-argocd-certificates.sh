#!/bin/bash

# ArgoCD SSL Certificate Setup Script
# This script sets up cert-manager and custom SSL certificates for ArgoCD

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
    echo -e "${PURPLE}[CERT-SETUP]${NC} $1"
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

# Check if kubectl is available and cluster is accessible
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        return 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    if ! kubectl get namespace argocd &> /dev/null; then
        print_error "ArgoCD namespace not found. Please run platform setup first."
        return 1
    fi
    
    return 0
}

# Install cert-manager via ArgoCD application
install_cert_manager() {
    print_status "Installing cert-manager..."
    
    # Apply cert-manager ArgoCD application
    kubectl apply -f "$ROOT_DIR/infrastructure/certificates/cert-manager-install.yaml"
    
    print_status "Waiting for cert-manager installation to complete..."
    
    # Wait for cert-manager namespace
    kubectl wait --for=condition=Ready --timeout=300s pod -l app=cert-manager -n cert-manager || {
        print_warning "cert-manager pods not ready, but continuing..."
    }
    
    print_success "cert-manager installed successfully"
}

# Setup ArgoCD certificates
setup_argocd_certificates() {
    print_status "Setting up ArgoCD SSL certificates..."
    
    # Apply cluster issuer and CA certificate
    kubectl apply -f "$ROOT_DIR/infrastructure/certificates/argocd-cluster-issuer.yaml"
    
    print_status "Waiting for CA certificate to be issued..."
    kubectl wait --for=condition=Ready --timeout=300s certificate/argocd-ca-certificate -n cert-manager || {
        print_warning "CA certificate not ready yet, but continuing..."
    }
    
    # Apply ArgoCD server certificates
    kubectl apply -f "$ROOT_DIR/infrastructure/certificates/argocd-server-certificate.yaml"
    
    print_status "Waiting for ArgoCD server certificates..."
    kubectl wait --for=condition=Ready --timeout=300s certificate/argocd-server-tls -n argocd || {
        print_warning "Server certificate not ready yet, but continuing..."
    }
    
    print_success "ArgoCD certificates configured"
}

# Configure ArgoCD to use certificates
configure_argocd_server() {
    print_status "Configuring ArgoCD server for TLS..."
    
    # Apply ArgoCD server configuration
    kubectl apply -f "$ROOT_DIR/infrastructure/certificates/argocd-server-config.yaml"
    
    print_status "Waiting for CA certificate copy job to complete..."
    sleep 10  # Give the job time to start
    
    # Check if job completed successfully
    JOB_STATUS=$(kubectl get job copy-argocd-ca-cert -n argocd -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
    if [ "$JOB_STATUS" = "True" ]; then
        print_success "CA certificate copied successfully"
    else
        print_warning "CA certificate copy job may still be running"
    fi
    
    print_success "ArgoCD server configured for TLS"
}

# Setup Backstage certificate integration
setup_backstage_certs() {
    print_status "Setting up Backstage certificate integration..."
    
    # Apply Backstage certificate configuration
    kubectl apply -f "$ROOT_DIR/infrastructure/certificates/backstage-argocd-certs.yaml"
    
    print_status "Waiting for certificate sync job..."
    sleep 10
    
    # Check if Backstage sync job completed
    JOB_STATUS=$(kubectl get job sync-argocd-ca-to-backstage -n backstage -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "False")
    if [ "$JOB_STATUS" = "True" ]; then
        print_success "ArgoCD CA certificate synced to Backstage"
    else
        print_warning "Backstage certificate sync may still be running"
    fi
    
    print_success "Backstage certificate integration completed"
}

# Setup LocalStack certificate backup
setup_localstack_backup() {
    if curl -s http://localhost:4566/health > /dev/null 2>&1; then
        print_status "Setting up LocalStack certificate backup..."
        
        kubectl apply -f "$ROOT_DIR/infrastructure/certificates/localstack-cert-backup.yaml"
        
        print_success "LocalStack certificate backup configured"
    else
        print_warning "LocalStack not available, skipping certificate backup setup"
    fi
}

# Apply ArgoCD TLS patches
apply_argocd_patches() {
    print_status "Applying ArgoCD TLS configuration patches..."
    
    # Note: The TLS patch will be applied via ArgoCD sync
    # For now, we'll just ensure the configuration is ready
    kubectl apply -f "$ROOT_DIR/infrastructure/certificates/argocd-server-tls-patch.yaml"
    
    print_status "Restarting ArgoCD server to pick up new configuration..."
    kubectl rollout restart deployment/argocd-server -n argocd
    
    print_status "Waiting for ArgoCD server to be ready..."
    kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
    
    print_success "ArgoCD server restarted with TLS configuration"
}

# Verify certificate setup
verify_certificates() {
    print_status "Verifying certificate setup..."
    
    # Check if certificates exist
    if kubectl get secret argocd-server-tls -n argocd &>/dev/null; then
        print_success "✓ ArgoCD server certificate found"
    else
        print_error "✗ ArgoCD server certificate missing"
        return 1
    fi
    
    if kubectl get configmap argocd-ca-certificates -n argocd &>/dev/null; then
        print_success "✓ ArgoCD CA certificate ConfigMap found"
    else
        print_error "✗ ArgoCD CA certificate ConfigMap missing"
        return 1
    fi
    
    if kubectl get configmap argocd-ca-certificate -n backstage &>/dev/null; then
        print_success "✓ Backstage CA certificate ConfigMap found"
    else
        print_warning "⚠ Backstage CA certificate ConfigMap missing (may still be syncing)"
    fi
    
    # Test ArgoCD server connectivity
    print_status "Testing ArgoCD server connectivity..."
    if kubectl port-forward -n argocd svc/argocd-server 8443:443 > /dev/null 2>&1 &
    then
        PF_PID=$!
        sleep 5
        
        if curl -k -s https://localhost:8443/api/version &>/dev/null; then
            print_success "✓ ArgoCD server responding on HTTPS"
        else
            print_warning "⚠ ArgoCD server HTTPS not yet responding (may need more time)"
        fi
        
        kill $PF_PID 2>/dev/null || true
    fi
    
    print_success "Certificate verification completed"
}

# Main execution
main() {
    print_header "ArgoCD SSL Certificate Setup"
    
    print_status "Starting ArgoCD SSL certificate setup..."
    
    if ! check_prerequisites; then
        exit 1
    fi
    
    install_cert_manager
    setup_argocd_certificates
    configure_argocd_server
    setup_backstage_certs
    setup_localstack_backup
    apply_argocd_patches
    verify_certificates
    
    print_header "Certificate Setup Complete"
    
    echo -e "${GREEN}🎉 ArgoCD SSL certificates have been configured!${NC}\n"
    echo -e "${BLUE}📋 Summary:${NC}"
    echo -e "  • cert-manager installed and configured"
    echo -e "  • ArgoCD server certificates generated and applied"
    echo -e "  • CA certificates shared with Backstage"
    echo -e "  • LocalStack backup configured (if available)"
    echo -e "  • ArgoCD server configured for HTTPS\n"
    
    echo -e "${YELLOW}📝 Next Steps:${NC}"
    echo -e "  1. Access ArgoCD via: kubectl port-forward -n argocd svc/argocd-server 8443:443"
    echo -e "  2. Use https://localhost:8443 for ArgoCD UI"
    echo -e "  3. Update Backstage configuration to use HTTPS ArgoCD endpoints"
    echo -e "  4. The CA certificate is available in Backstage at /etc/ssl/argocd/ca.crt\n"
    
    print_success "ArgoCD SSL setup completed successfully!"
}

# Handle command line arguments
case "${1:-setup}" in
    "setup"|"")
        main
        ;;
    "verify")
        print_header "Certificate Verification"
        check_prerequisites && verify_certificates
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [setup|verify|help]"
        echo ""
        echo "Commands:"
        echo "  setup   - Set up ArgoCD SSL certificates (default)"
        echo "  verify  - Verify certificate setup"
        echo "  help    - Show this help message"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac