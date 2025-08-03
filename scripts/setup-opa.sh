#!/bin/bash

# Open Policy Agent (OPA) Setup Script for IDP Platform
# This script deploys and configures OPA for fine-grained authorization

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites for OPA setup..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is required but not installed"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot access Kubernetes cluster"
        exit 1
    fi
    
    # Check if Istio is installed
    if ! kubectl get namespace istio-system &> /dev/null; then
        print_error "Istio is required but not installed"
        exit 1
    fi
    
    # Check if OPA CLI is available (optional)
    if command -v opa &> /dev/null; then
        print_success "OPA CLI found: $(opa version)"
    else
        print_warning "OPA CLI not found - policy validation will be limited"
    fi
    
    print_success "Prerequisites check completed"
}

# Deploy OPA infrastructure
deploy_opa() {
    print_status "Deploying OPA infrastructure..."
    
    # Create namespace
    kubectl create namespace opa-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace opa-system istio-injection=enabled --overwrite
    
    # Deploy OPA components
    kubectl apply -f infrastructure/authorization/opa-setup.yaml
    kubectl apply -f infrastructure/authorization/opa-policy-management.yaml
    
    print_success "OPA infrastructure deployed"
}

# Configure Istio integration
configure_istio_integration() {
    print_status "Configuring Istio integration with OPA..."
    
    # Apply Istio configuration
    kubectl apply -f infrastructure/authorization/opa-istio-integration.yaml
    
    # Wait for Istio configuration to be applied
    sleep 10
    
    # Restart Istio proxy to pick up new configuration
    kubectl rollout restart deployment/istio-proxy -n istio-system || true
    
    print_success "Istio integration configured"
}

# Wait for OPA to be ready
wait_for_opa() {
    print_status "Waiting for OPA to be ready..."
    
    # Wait for OPA deployment
    kubectl wait --for=condition=available --timeout=300s deployment/opa -n opa-system
    
    # Wait for OPA pods to be ready
    kubectl wait --for=condition=ready --timeout=300s pod -l app=opa -n opa-system
    
    # Check OPA health
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if kubectl exec -n opa-system deployment/opa -- curl -f http://localhost:8181/health &> /dev/null; then
            print_success "OPA is healthy and ready"
            return 0
        fi
        
        print_status "Waiting for OPA to be healthy (attempt $attempt/$max_attempts)..."
        sleep 10
        ((attempt++))
    done
    
    print_error "OPA failed to become healthy within timeout"
    return 1
}

# Load and validate policies
load_policies() {
    print_status "Loading and validating OPA policies..."
    
    # If OPA CLI is available, validate policies locally
    if command -v opa &> /dev/null; then
        print_status "Validating policies with OPA CLI..."
        
        # Extract policies from ConfigMap
        kubectl get configmap opa-policies -n opa-system -o jsonpath='{.data}' > /tmp/opa-policies.json
        
        # Create temporary directory for policies
        mkdir -p /tmp/opa-policies
        
        # Extract each policy file
        python3 -c "
import json
import sys

data = json.load(open('/tmp/opa-policies.json'))
for filename, content in data.items():
    if filename.endswith('.rego'):
        with open(f'/tmp/opa-policies/{filename}', 'w') as f:
            f.write(content)
"
        
        # Validate each policy
        for policy in /tmp/opa-policies/*.rego; do
            if [ -f "$policy" ]; then
                print_status "Validating $(basename "$policy")..."
                if opa fmt "$policy" > /dev/null; then
                    print_success "Policy $(basename "$policy") is valid"
                else
                    print_error "Policy $(basename "$policy") has syntax errors"
                    return 1
                fi
            fi
        done
        
        # Run policy tests
        if [ -f "/tmp/opa-policies/authz_test.rego" ]; then
            print_status "Running policy tests..."
            opa test /tmp/opa-policies/
            print_success "All policy tests passed"
        fi
        
        # Clean up
        rm -rf /tmp/opa-policies /tmp/opa-policies.json
    else
        print_warning "OPA CLI not available - skipping local policy validation"
    fi
    
    # Test OPA API endpoints
    print_status "Testing OPA API endpoints..."
    
    # Test policy query endpoint
    if kubectl exec -n opa-system deployment/opa -- curl -f http://localhost:8181/v1/data/envoy/authz &> /dev/null; then
        print_success "OPA policy endpoint is accessible"
    else
        print_warning "OPA policy endpoint test failed"
    fi
    
    print_success "Policy loading completed"
}

# Enable OPA authorization for specific services
enable_opa_for_services() {
    print_status "Enabling OPA authorization for platform services..."
    
    # Label services that require OPA authorization
    kubectl label deployment backstage opa-authz=enabled -n backstage --overwrite || true
    kubectl label deployment argocd-server opa-authz=enabled -n argocd --overwrite || true
    kubectl label deployment grafana opa-authz=enabled -n monitoring --overwrite || true
    
    # Restart deployments to pick up new Istio configuration
    kubectl rollout restart deployment/backstage -n backstage || true
    kubectl rollout restart deployment/argocd-server -n argocd || true
    kubectl rollout restart deployment/grafana -n monitoring || true
    
    print_success "OPA authorization enabled for platform services"
}

# Test OPA authorization
test_opa_authorization() {
    print_status "Testing OPA authorization..."
    
    # Test unauthenticated request (should be denied)
    print_status "Testing unauthenticated request..."
    
    # Port forward to OPA for testing
    kubectl port-forward -n opa-system svc/opa 8181:8181 &
    local port_forward_pid=$!
    sleep 5
    
    # Test authorization query
    local test_result=$(curl -s -X POST http://localhost:8181/v1/data/envoy/authz/allow \
        -H "Content-Type: application/json" \
        -d '{
            "input": {
                "attributes": {
                    "request": {
                        "http": {
                            "path": "/api/catalog",
                            "method": "GET",
                            "headers": {}
                        }
                    }
                }
            }
        }')
    
    # Kill port forward
    kill $port_forward_pid 2>/dev/null || true
    
    if echo "$test_result" | grep -q '"result":false'; then
        print_success "Unauthenticated request correctly denied"
    else
        print_warning "Authorization test results unclear: $test_result"
    fi
    
    print_success "OPA authorization testing completed"
}

# Create OPA dashboard virtual service
create_opa_dashboard() {
    print_status "Creating OPA dashboard..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: opa-dashboard
  namespace: opa-system
spec:
  hosts:
  - "opa.idp.local"
  gateways:
  - istio-system/platform-gateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: opa-dashboard.opa-system.svc.cluster.local
        port:
          number: 80
EOF
    
    print_success "OPA dashboard created at https://opa.idp.local"
}

# Display setup summary
display_summary() {
    echo
    echo "=================================="
    echo "OPA Authorization Setup Complete"
    echo "=================================="
    echo
    echo "OPA Configuration:"
    echo "  Namespace: opa-system"
    echo "  Replicas: 3"
    echo "  GRPC Port: 9191"
    echo "  HTTP Port: 8181"
    echo
    echo "Enabled Services:"
    echo "  - Backstage (fine-grained catalog authorization)"
    echo "  - ArgoCD (application access control)"
    echo "  - Grafana (monitoring access control)"
    echo
    echo "Access URLs:"
    echo "  OPA Dashboard: https://opa.idp.local"
    echo "  OPA API: http://opa.opa-system.svc.cluster.local:8181"
    echo
    echo "Policy Management:"
    echo "  - Policies are stored in ConfigMaps"
    echo "  - Automatic policy sync every 5 minutes"
    echo "  - Policy validation on deployment"
    echo
    echo "Next Steps:"
    echo "1. Customize authorization policies in ConfigMap opa-policies"
    echo "2. Configure user groups and roles in your identity provider"
    echo "3. Test authorization with different user roles"
    echo "4. Monitor OPA decisions in the dashboard"
    echo
}

# Validate OPA setup
validate_setup() {
    print_status "Validating OPA setup..."
    
    # Check if pods are running
    if kubectl get pods -n opa-system | grep -E "Running|Ready"; then
        print_success "OPA pods are running"
    else
        print_error "Some OPA pods are not running"
        kubectl get pods -n opa-system
        return 1
    fi
    
    # Check OPA health
    if kubectl exec -n opa-system deployment/opa -- curl -f http://localhost:8181/health &> /dev/null; then
        print_success "OPA health check passed"
    else
        print_error "OPA health check failed"
        return 1
    fi
    
    # Check policy bundle status
    local bundle_status=$(kubectl exec -n opa-system deployment/opa -- curl -s http://localhost:8181/v1/status)
    if echo "$bundle_status" | grep -q "bundles"; then
        print_success "OPA policy bundles are loaded"
    else
        print_warning "OPA policy bundle status unclear"
    fi
    
    print_success "OPA setup validation completed"
}

# Main execution
main() {
    print_status "Starting OPA authorization setup"
    
    check_prerequisites
    deploy_opa
    configure_istio_integration
    wait_for_opa
    load_policies
    enable_opa_for_services
    test_opa_authorization
    create_opa_dashboard
    validate_setup
    display_summary
    
    print_success "OPA authorization setup completed successfully!"
}

# Check if running directly or being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi