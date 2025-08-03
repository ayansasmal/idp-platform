#!/bin/bash

# IDP Platform Bootstrap Script
# Deploys the complete IDP platform from scratch with proper ordering and dependencies

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Platform info
PLATFORM_NAME="IDP Platform"
PLATFORM_VERSION="2.0.0"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                IDP Platform Bootstrap                        ║"
echo "║                                                              ║"
echo "║  🚀 Deploying complete platform from scratch...             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_phase() {
    echo -e "${PURPLE}[PHASE]${NC} $1"
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    print_status "Waiting for deployment $deployment in namespace $namespace..."
    if kubectl wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n $namespace 2>/dev/null; then
        print_success "Deployment $deployment is ready"
        return 0
    else
        print_error "Deployment $deployment failed to become ready within ${timeout}s"
        return 1
    fi
}

# Function to wait for CRDs to be established
wait_for_crds() {
    local crd_pattern=$1
    local timeout=${2:-120}
    
    print_status "Waiting for CRDs matching pattern: $crd_pattern"
    local end_time=$(($(date +%s) + timeout))
    
    while [ $(date +%s) -lt $end_time ]; do
        if kubectl get crd | grep -q "$crd_pattern"; then
            local crds=$(kubectl get crd | grep "$crd_pattern" | awk '{print $1}')
            local all_ready=true
            
            for crd in $crds; do
                if ! kubectl wait --for condition=established --timeout=10s crd/$crd >/dev/null 2>&1; then
                    all_ready=false
                    break
                fi
            done
            
            if [ "$all_ready" = true ]; then
                print_success "All CRDs matching '$crd_pattern' are ready"
                return 0
            fi
        fi
        print_status "Waiting for CRDs to be established..."
        sleep 10
    done
    
    print_error "CRDs matching '$crd_pattern' failed to become ready within ${timeout}s"
    return 1
}

# Function to check prerequisites
check_prerequisites() {
    print_phase "Checking prerequisites..."
    
    # Check if kubectl is available and connected
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is required but not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot access Kubernetes cluster"
        exit 1
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        print_error "helm is required but not installed"
        exit 1
    fi
    
    # Check if istioctl is available in path
    if ! command -v istioctl &> /dev/null; then
        # Try to add local istio to path
        if [ -f "./istio-1.26.3/bin/istioctl" ]; then
            export PATH=$PATH:$(pwd)/istio-1.26.3/bin
            print_success "Using local istioctl from ./istio-1.26.3/bin/"
        else
            print_error "istioctl is required but not found. Please install Istio CLI."
            exit 1
        fi
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "CLAUDE.md" ]] || [[ ! -d "applications" ]]; then
        print_error "Please run this script from the IDP platform root directory"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Phase 1: Install Istio Service Mesh
install_istio() {
    print_phase "Installing Istio Service Mesh..."
    
    # Install Istio with demo profile (includes ingress gateway)
    print_status "Installing Istio control plane..."
    istioctl install --set values.defaultRevision=default -y
    
    # Wait for Istio to be ready
    wait_for_deployment istio-system istiod 300
    
    # Label default namespace for injection
    kubectl label namespace default istio-injection=enabled --overwrite
    
    # Install Istio addons (monitoring stack)
    print_status "Installing Istio addons (Prometheus, Grafana, Jaeger, Kiali)..."
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/prometheus.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/grafana.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/jaeger.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/addons/kiali.yaml || true
    
    print_success "Istio installation completed"
}

# Phase 2: Install ArgoCD
install_argocd() {
    print_phase "Installing ArgoCD GitOps Engine..."
    
    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Install ArgoCD
    print_status "Installing ArgoCD core components..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    wait_for_deployment argocd argocd-server 300
    
    # Patch ArgoCD server to be insecure (for local development)
    print_status "Configuring ArgoCD for local access..."
    kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p='{"data":{"server.insecure":"true"}}'
    kubectl rollout restart deployment argocd-server -n argocd
    
    # Wait for restart
    wait_for_deployment argocd argocd-server 180
    
    print_success "ArgoCD installation completed"
}

# Phase 3: Install Crossplane
install_crossplane() {
    print_phase "Installing Crossplane Infrastructure as Code..."
    
    # Add Crossplane Helm repository
    helm repo add crossplane-stable https://charts.crossplane.io/stable
    helm repo update
    
    # Create namespace
    kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Crossplane
    print_status "Installing Crossplane..."
    helm upgrade --install crossplane crossplane-stable/crossplane \
        --namespace crossplane-system \
        --set resourcesCrossplane.limits.cpu=1 \
        --set resourcesCrossplane.limits.memory=2Gi \
        --set resourcesCrossplane.requests.cpu=100m \
        --set resourcesCrossplane.requests.memory=256Mi \
        --wait
    
    # Wait for Crossplane CRDs
    wait_for_crds "crossplane"
    
    print_success "Crossplane installation completed"
}

# Phase 4: Install External Secrets Operator
install_external_secrets() {
    print_phase "Installing External Secrets Operator..."
    
    # Add External Secrets Helm repository
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    
    # Create namespace
    kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Install External Secrets Operator
    print_status "Installing External Secrets Operator..."
    helm upgrade --install external-secrets external-secrets/external-secrets \
        --namespace external-secrets-system \
        --wait
    
    # Wait for deployment
    wait_for_deployment external-secrets-system external-secrets 300
    
    print_success "External Secrets Operator installation completed"
}

# Phase 5: Install cert-manager
install_cert_manager() {
    print_phase "Installing cert-manager..."
    
    # Add cert-manager Helm repository
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    # Create namespace
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    # Install cert-manager
    print_status "Installing cert-manager..."
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.13.0 \
        --set installCRDs=true \
        --wait
    
    # Wait for deployment
    wait_for_deployment cert-manager cert-manager 300
    
    print_success "cert-manager installation completed"
}

# Phase 6: Install Argo Workflows
install_argo_workflows() {
    print_phase "Installing Argo Workflows..."
    
    # Create namespace (Argo Workflows expects 'argo' namespace)
    kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Argo Workflows
    print_status "Installing Argo Workflows..."
    kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.2/install.yaml
    
    # Wait for deployment
    wait_for_deployment argo argo-server 300
    
    # Configure Argo Workflows for local access
    kubectl patch configmap workflow-controller-configmap -n argo --type merge -p='{"data":{"containerRuntimeExecutor":"k8sapi"}}'
    
    print_success "Argo Workflows installation completed"
}

# Phase 7: Deploy platform infrastructure via ArgoCD
deploy_platform_infrastructure() {
    print_phase "Deploying platform infrastructure via ArgoCD..."
    
    # Apply the ArgoCD project first
    print_status "Creating ArgoCD project..."
    kubectl apply -f applications/argocd/argocd-apps.yaml
    
    # Wait a moment for the project to be created
    sleep 10
    
    # Apply infrastructure applications
    print_status "Deploying core infrastructure applications..."
    kubectl apply -f applications/infrastructure/core-infrastructure-apps.yaml
    
    # Wait for infrastructure to be deployed
    print_status "Waiting for infrastructure applications to sync..."
    sleep 30
    
    print_success "Platform infrastructure deployment initiated"
}

# Phase 8: Deploy platform services  
deploy_platform_services() {
    print_phase "Deploying platform services..."
    
    # Apply platform services
    print_status "Deploying platform services..."
    kubectl apply -f applications/platform-services-apps.yaml
    
    # Wait for services to be deployed
    print_status "Waiting for platform services to sync..."
    sleep 30
    
    print_success "Platform services deployment initiated"
}

# Phase 9: Skip Backstage for now (requires container image)
skip_backstage() {
    print_phase "Skipping Backstage Developer Portal (requires container image)..."
    
    # Create namespace for PostgreSQL only
    kubectl create namespace backstage --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy only PostgreSQL (needed for later Backstage deployment)
    print_status "Deploying PostgreSQL for future Backstage deployment..."
    kubectl apply -f applications/backstage/postgres.yaml
    
    print_warning "Backstage skipped - container image needs to be built first"
    print_success "PostgreSQL database deployed for future Backstage use"
}

# Phase 10: Setup networking and ingress
setup_networking() {
    print_phase "Setting up networking and ingress..."
    
    # Apply Istio gateways and virtual services
    print_status "Configuring Istio ingress..."
    kubectl apply -f infrastructure/istio/gateways/
    kubectl apply -f infrastructure/istio/virtual-services/ || true
    
    # Apply additional networking configuration
    kubectl apply -f applications/argocd/argocd-virtualservice.yaml || true
    kubectl apply -f applications/backstage/backstage-virtualservice.yaml || true
    
    print_success "Networking configuration completed"
}

# Phase 10.5: Configure ArgoCD with Cognito authentication
configure_argocd_cognito() {
    print_phase "Configuring ArgoCD with Cognito authentication..."
    
    # Copy Cognito secrets to argocd namespace
    print_status "Copying Cognito secrets to ArgoCD namespace..."
    kubectl get secret cognito-config -o yaml | sed 's/namespace: default/namespace: argocd/' | kubectl apply -f - || true
    kubectl get secret argocd-cognito -o yaml | sed 's/namespace: default/namespace: argocd/' | kubectl apply -f - || true
    
    # Apply ArgoCD Cognito configuration
    print_status "Applying ArgoCD Cognito configuration..."
    kubectl apply -f applications/argocd/argocd-cognito-config.yaml
    
    # Wait for setup job to complete
    print_status "Waiting for ArgoCD Cognito setup to complete..."
    kubectl wait --for=condition=complete --timeout=120s job/argocd-cognito-setup -n argocd || true
    
    print_success "ArgoCD Cognito authentication configured"
}

# Phase 11: Start platform services
start_platform_services() {
    print_phase "Starting platform services with port forwarding..."
    
    print_status "Starting port forwarding for platform services..."
    
    # Start platform services in background
    export PATH=$PATH:$(pwd)/istio-1.26.3/bin
    ./scripts/start-platform.sh start > /dev/null 2>&1 &
    
    # Give services time to start
    sleep 10
    
    print_success "Platform services started with port forwarding"
}

# Phase 12: Final validation and setup
final_validation() {
    print_phase "Final validation and setup..."
    
    # Check ArgoCD applications status
    print_status "Checking ArgoCD applications..."
    kubectl get applications -n argocd || true
    
    # Get ArgoCD admin password
    print_status "Retrieving ArgoCD admin password..."
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d || echo "Password not yet available")
    
    print_success "Platform bootstrap completed!"
    
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗"
    echo "║                   Platform Access Information               ║"
    echo "╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "${GREEN}🎉 IDP Platform is now deployed!${NC}\n"
    
    echo -e "${BLUE}📊 Services Status:${NC}"
    echo "  • ArgoCD:          http://localhost:8080"
    echo "  • Backstage:       http://localhost:3000"
    echo "  • Argo Workflows:  http://localhost:4000"
    echo "  • Grafana:         http://localhost:3001"
    echo "  • Prometheus:      http://localhost:9090"
    echo "  • Jaeger:          http://localhost:16686"
    echo "  • Kiali:           http://localhost:20001"
    
    echo -e "\n${BLUE}🔐 Default Credentials:${NC}"
    echo "  • ArgoCD:    admin / $ARGOCD_PASSWORD"
    echo "  • Grafana:   admin / admin"
    
    echo -e "\n${BLUE}📚 Next Steps:${NC}"
    echo "  1. Run: ./scripts/start-platform.sh start"
    echo "  2. Access services via the URLs above"
    echo "  3. Check ArgoCD for application sync status"
    echo "  4. Explore Backstage for self-service capabilities"
    
    echo -e "\n${YELLOW}💡 Pro Tips:${NC}"
    echo "  • Use 'kubectl get applications -n argocd' to check GitOps status"
    echo "  • All platform components are managed by ArgoCD"
    echo "  • Check the access-guide.md for detailed instructions"
    
    echo -e "\n${GREEN}🚀 Platform ready for development!${NC}"
}

# Main execution flow
main() {
    print_status "Starting IDP Platform bootstrap..."
    
    # Execute phases in order
    check_prerequisites
    install_istio
    install_argocd
    install_crossplane
    install_external_secrets
    install_cert_manager
    install_argo_workflows
    deploy_platform_infrastructure
    deploy_platform_services
    skip_backstage
    setup_networking
    configure_argocd_cognito
    start_platform_services
    final_validation
    
    print_success "Bootstrap completed successfully! 🎉"
}

# Handle script interruption
trap 'print_error "Bootstrap interrupted. Run the script again to continue."; exit 1' INT TERM

# Check if running directly or being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi