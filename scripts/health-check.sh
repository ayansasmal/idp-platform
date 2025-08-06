#!/bin/bash

# Component Health Check Script
# Validates platform component health after updates or during rollbacks

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSIONS_FILE="$ROOT_DIR/platform-versions.yaml"

print_status() {
    echo -e "${PURPLE}[HEALTH]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[HEALTHY]${NC} $1"
}

print_error() {
    echo -e "${RED}[UNHEALTHY]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Health check functions for each component type
check_argocd_health() {
    print_status "Checking ArgoCD health..."
    
    # Check if ArgoCD server is running
    if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --field-selector=status.phase=Running | grep -q argocd-server; then
        print_success "ArgoCD server is running"
    else
        print_error "ArgoCD server is not running"
        return 1
    fi
    
    # Check ArgoCD API health
    if kubectl get -n argocd service argocd-server &> /dev/null; then
        print_success "ArgoCD service is available"
    else
        print_error "ArgoCD service is not available"
        return 1
    fi
    
    return 0
}

check_istio_health() {
    print_status "Checking Istio health..."
    
    # Check Istio control plane pods
    local unhealthy_pods=0
    for component in istiod istio-proxy; do
        if ! kubectl get pods -n istio-system -l app=$component --field-selector=status.phase=Running | grep -q $component; then
            print_error "Istio component $component is not running"
            ((unhealthy_pods++))
        fi
    done
    
    if [ $unhealthy_pods -eq 0 ]; then
        print_success "Istio control plane is healthy"
    else
        print_error "Istio control plane has $unhealthy_pods unhealthy components"
        return 1
    fi
    
    # Check if Istio injection is working
    if kubectl get namespace default -o jsonpath='{.metadata.labels.istio-injection}' | grep -q enabled; then
        print_success "Istio injection is enabled"
    else
        print_warning "Istio injection not enabled on default namespace"
    fi
    
    return 0
}

check_monitoring_health() {
    print_status "Checking monitoring stack health..."
    
    local components=("prometheus" "grafana" "alertmanager")
    local unhealthy=0
    
    for component in "${components[@]}"; do
        if kubectl get pods -n monitoring -l app.kubernetes.io/name=$component --field-selector=status.phase=Running | grep -q $component; then
            print_success "$component is running"
        else
            print_error "$component is not running"
            ((unhealthy++))
        fi
    done
    
    if [ $unhealthy -eq 0 ]; then
        print_success "Monitoring stack is healthy"
        return 0
    else
        print_error "Monitoring stack has $unhealthy unhealthy components"
        return 1
    fi
}

check_backstage_health() {
    print_status "Checking Backstage health..."
    
    if kubectl get pods -n backstage -l app.kubernetes.io/name=backstage --field-selector=status.phase=Running | grep -q backstage; then
        print_success "Backstage is running"
    else
        print_error "Backstage is not running"
        return 1
    fi
    
    # Check if Backstage service is accessible
    if kubectl get service -n backstage backstage &> /dev/null; then
        print_success "Backstage service is available"
        return 0
    else
        print_error "Backstage service is not available"
        return 1
    fi
}

check_workflows_health() {
    print_status "Checking Argo Workflows health..."
    
    if kubectl get pods -n argo-workflows -l app.kubernetes.io/name=argo-workflows-server --field-selector=status.phase=Running | grep -q argo-workflows; then
        print_success "Argo Workflows server is running"
    else
        print_error "Argo Workflows server is not running"
        return 1
    fi
    
    # Check workflow controller
    if kubectl get pods -n argo-workflows -l app.kubernetes.io/name=argo-workflows-workflow-controller --field-selector=status.phase=Running | grep -q workflow-controller; then
        print_success "Argo Workflows controller is running"
        return 0
    else
        print_error "Argo Workflows controller is not running"
        return 1
    fi
}

check_external_secrets_health() {
    print_status "Checking External Secrets health..."
    
    if kubectl get pods -n external-secrets -l app.kubernetes.io/name=external-secrets --field-selector=status.phase=Running | grep -q external-secrets; then
        print_success "External Secrets operator is running"
        return 0
    else
        print_error "External Secrets operator is not running"
        return 1
    fi
}

# Generic component health check
check_component_health() {
    local component="$1"
    
    case "$component" in
        "argocd-platform")
            check_argocd_health
            ;;
        "istio-config")
            check_istio_health
            ;;
        "monitoring-stack")
            check_monitoring_health
            ;;
        "backstage-deployment")
            check_backstage_health
            ;;
        "argo-workflows")
            check_workflows_health
            ;;
        "external-secrets")
            check_external_secrets_health
            ;;
        *)
            print_warning "No specific health check available for component: $component"
            # Generic health check based on ArgoCD application status
            if kubectl get application "$component" -n argocd &> /dev/null; then
                local sync_status=$(kubectl get application "$component" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
                local health_status=$(kubectl get application "$component" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
                
                if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
                    print_success "Component $component is synced and healthy"
                    return 0
                else
                    print_error "Component $component sync: $sync_status, health: $health_status"
                    return 1
                fi
            else
                print_error "Component $component not found in ArgoCD"
                return 1
            fi
            ;;
    esac
}

# Main health check function
run_health_check() {
    local component="${1:-}"
    local exit_code=0
    
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    IDP Platform Health Check                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    if [ -n "$component" ]; then
        print_status "Running health check for component: $component"
        if ! check_component_health "$component"; then
            exit_code=1
        fi
    else
        print_status "Running full platform health check..."
        
        # Check core components
        local components=("argocd-platform" "istio-config" "monitoring-stack" "backstage-deployment" "argo-workflows" "external-secrets")
        
        for comp in "${components[@]}"; do
            echo ""
            if ! check_component_health "$comp"; then
                exit_code=1
            fi
        done
    fi
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        print_success "All health checks passed ✅"
    else
        print_error "Some health checks failed ❌"
    fi
    
    return $exit_code
}

# Command line handling
case "${1:-all}" in
    "all")
        run_health_check
        ;;
    *)
        run_health_check "$1"
        ;;
esac