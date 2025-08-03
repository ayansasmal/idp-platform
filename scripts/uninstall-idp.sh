#!/bin/bash

# IDP Platform Uninstall Script
# This script safely removes IDP Platform resources while preserving external dependencies

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIRMATION_REQUIRED=${CONFIRMATION_REQUIRED:-true}
DRY_RUN=${DRY_RUN:-false}

echo -e "${RED}🧹 IDP Platform Uninstall Script${NC}"
echo -e "${YELLOW}⚠️  This will remove IDP Platform resources from your system${NC}"
echo

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect Kubernetes runtime
detect_k8s_runtime() {
    echo -e "${BLUE}🔍 Detecting Kubernetes runtime...${NC}"
    
    if kubectl config current-context 2>/dev/null | grep -q "docker-desktop"; then
        echo -e "${GREEN}✅ Docker Desktop Kubernetes detected${NC}"
        echo "docker-desktop"
    elif kubectl config current-context 2>/dev/null | grep -q "kind"; then
        echo -e "${YELLOW}⚠️  Kind cluster detected${NC}"
        echo "kind"
    elif kubectl config current-context 2>/dev/null | grep -q "minikube"; then
        echo -e "${YELLOW}⚠️  Minikube cluster detected${NC}"
        echo "minikube"
    else
        echo -e "${CYAN}ℹ️  Unknown or external Kubernetes cluster${NC}"
        echo "unknown"
    fi
}

# Function to show what will be removed
show_removal_plan() {
    echo -e "${CYAN}📋 Removal Plan:${NC}"
    echo
    echo -e "${YELLOW}Kubernetes Resources to Remove:${NC}"
    echo "  • All IDP Platform namespaces (argocd, backstage, argo-workflows, etc.)"
    echo "  • Crossplane and its Custom Resources"
    echo "  • Istio service mesh components"
    echo "  • External Secrets Operator"
    echo "  • Monitoring stack (Prometheus, Grafana, Jaeger, Kiali)"
    echo "  • Cert-manager"
    echo "  • Custom Resource Definitions (CRDs)"
    echo
    echo -e "${YELLOW}Docker Resources to Remove:${NC}"
    echo "  • IDP-related container images"
    echo "  • LocalStack ECR images (IDP workloads only)"
    echo "  • Stopped containers from IDP deployments"
    echo
    echo -e "${GREEN}Resources Preserved:${NC}"
    echo "  • Docker Desktop Kubernetes cluster"
    echo "  • External LocalStack installation and data"
    echo "  • System-wide tools (awslocal, kubectl, docker, etc.)"
    echo "  • AWS CLI configuration"
    echo "  • Non-IDP docker images"
    echo
    echo -e "${RED}Manual Actions Required for Alternative Setups:${NC}"
    echo "  • Kind clusters: kind delete cluster --name <cluster-name>"
    echo "  • Minikube: minikube delete"
    echo "  • External clusters: Manual cleanup required"
    echo
}

# Function to remove Kubernetes namespaces
remove_k8s_namespaces() {
    echo -e "${YELLOW}🗑️  Removing IDP Platform namespaces...${NC}"
    
    local namespaces=(
        "argocd"
        "backstage" 
        "argo-workflows"
        "istio-system"
        "crossplane-system"
        "external-secrets-system"
        "cert-manager"
        "development"
        "staging"
        "production"
        "localstack"
    )
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            echo -e "${BLUE}  ↪ Removing namespace: $ns${NC}"
            if [[ "$DRY_RUN" == "false" ]]; then
                kubectl delete namespace "$ns" --timeout=60s || echo -e "${YELLOW}    ⚠️  Failed to delete $ns (may not exist)${NC}"
            else
                echo -e "${CYAN}    [DRY RUN] Would delete namespace: $ns${NC}"
            fi
        else
            echo -e "${GREEN}  ✅ Namespace $ns does not exist${NC}"
        fi
    done
}

# Function to remove Custom Resource Definitions
remove_crds() {
    echo -e "${YELLOW}🗑️  Removing IDP Platform CRDs...${NC}"
    
    local crd_patterns=(
        "*.platform.idp"
        "*.crossplane.io"
        "*.istio.io"
        "*.external-secrets.io"
        "*.cert-manager.io"
        "*.argoproj.io"
    )
    
    for pattern in "${crd_patterns[@]}"; do
        local crds
        crds=$(kubectl get crd -o name 2>/dev/null | grep -E "${pattern//\*/.*}" || true)
        
        if [[ -n "$crds" ]]; then
            echo -e "${BLUE}  ↪ Removing CRDs matching: $pattern${NC}"
            if [[ "$DRY_RUN" == "false" ]]; then
                echo "$crds" | xargs kubectl delete --timeout=60s || echo -e "${YELLOW}    ⚠️  Some CRDs may have failed to delete${NC}"
            else
                echo -e "${CYAN}    [DRY RUN] Would delete CRDs: $pattern${NC}"
                echo "$crds" | sed 's/^/      /'
            fi
        fi
    done
}

# Function to remove IDP-related Docker images
remove_docker_images() {
    echo -e "${YELLOW}🗑️  Removing IDP-related Docker images...${NC}"
    
    if ! command_exists docker; then
        echo -e "${YELLOW}  ⚠️  Docker not available, skipping image cleanup${NC}"
        return
    fi
    
    # Remove IDP-specific images
    local image_patterns=(
        "000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566/idp/*"
        "*backstage*"
        "*argocd*" 
        "*crossplane*"
        "*istio*"
        "*localstack*"
    )
    
    echo -e "${BLUE}  ↪ Scanning for IDP-related images...${NC}"
    
    for pattern in "${image_patterns[@]}"; do
        local images
        images=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep -i "${pattern//\*/}" | awk 'NR>1' || true)
        
        if [[ -n "$images" ]]; then
            echo -e "${BLUE}    Found images matching: $pattern${NC}"
            if [[ "$DRY_RUN" == "false" ]]; then
                echo "$images" | while read -r image; do
                    if [[ -n "$image" ]]; then
                        echo -e "${CYAN}      Removing: $image${NC}"
                        docker rmi "$image" 2>/dev/null || echo -e "${YELLOW}        ⚠️  Failed to remove $image${NC}"
                    fi
                done
            else
                echo -e "${CYAN}    [DRY RUN] Would remove images:${NC}"
                echo "$images" | sed 's/^/      /'
            fi
        fi
    done
}

# Function to clean LocalStack ECR (IDP workloads only)
clean_localstack_ecr() {
    echo -e "${YELLOW}🗑️  Cleaning IDP workloads from LocalStack ECR...${NC}"
    
    if ! command_exists awslocal; then
        echo -e "${YELLOW}  ⚠️  awslocal not available, skipping ECR cleanup${NC}"
        echo -e "${BLUE}  💡 You can manually clean ECR with: awslocal ecr list-repositories${NC}"
        return
    fi
    
    # Check if LocalStack is running
    if ! curl -s http://localhost:4566/_localstack/health >/dev/null 2>&1; then
        echo -e "${YELLOW}  ⚠️  LocalStack not running, skipping ECR cleanup${NC}"
        return
    fi
    
    echo -e "${BLUE}  ↪ Scanning LocalStack ECR for IDP repositories...${NC}"
    
    # Get IDP-related repositories
    local repos
    repos=$(awslocal ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `idp/`)].repositoryName' --output text 2>/dev/null || true)
    
    if [[ -n "$repos" ]]; then
        echo -e "${BLUE}    Found IDP repositories in LocalStack ECR${NC}"
        for repo in $repos; do
            if [[ -n "$repo" ]]; then
                echo -e "${CYAN}      Repository: $repo${NC}"
                if [[ "$DRY_RUN" == "false" ]]; then
                    awslocal ecr delete-repository --repository-name "$repo" --force 2>/dev/null || \
                        echo -e "${YELLOW}        ⚠️  Failed to delete repository $repo${NC}"
                else
                    echo -e "${CYAN}      [DRY RUN] Would delete repository: $repo${NC}"
                fi
            fi
        done
    else
        echo -e "${GREEN}  ✅ No IDP repositories found in LocalStack ECR${NC}"
    fi
}

# Function to stop port forwards
stop_port_forwards() {
    echo -e "${YELLOW}🗑️  Stopping IDP port forwards...${NC}"
    
    local pids
    pids=$(ps aux | grep "kubectl port-forward" | grep -v grep | awk '{print $2}' || true)
    
    if [[ -n "$pids" ]]; then
        echo -e "${BLUE}  ↪ Found running port forwards${NC}"
        if [[ "$DRY_RUN" == "false" ]]; then
            for pid in $pids; do
                echo -e "${CYAN}    Stopping PID: $pid${NC}"
                kill "$pid" 2>/dev/null || true
            done
        else
            echo -e "${CYAN}  [DRY RUN] Would stop PIDs: $pids${NC}"
        fi
    else
        echo -e "${GREEN}  ✅ No active port forwards found${NC}"
    fi
    
    # Remove PID file if it exists
    local pids_file="${SCRIPT_DIR}/.port-forward-pids"
    if [[ -f "$pids_file" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            rm -f "$pids_file"
            echo -e "${GREEN}  ✅ Removed port forward PID file${NC}"
        else
            echo -e "${CYAN}  [DRY RUN] Would remove PID file: $pids_file${NC}"
        fi
    fi
}

# Function to clean up generated files
cleanup_generated_files() {
    echo -e "${YELLOW}🗑️  Cleaning up generated files...${NC}"
    
    local files_to_remove=(
        "docker-compose.localstack.yml"
        "localstack-idp-config.json"
        ".port-forward-pids"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            echo -e "${BLUE}  ↪ Removing: $file${NC}"
            if [[ "$DRY_RUN" == "false" ]]; then
                rm -f "$file"
            else
                echo -e "${CYAN}    [DRY RUN] Would remove: $file${NC}"
            fi
        fi
    done
}

# Function to show manual cleanup instructions
show_manual_cleanup() {
    local k8s_runtime="$1"
    
    echo -e "${CYAN}📝 Manual Cleanup Instructions:${NC}"
    echo
    
    case "$k8s_runtime" in
        "kind")
            echo -e "${YELLOW}Kind Cluster Cleanup:${NC}"
            echo "  • List clusters: kind get clusters"
            echo "  • Delete cluster: kind delete cluster --name <cluster-name>"
            echo "  • Delete all: kind delete clusters --all"
            ;;
        "minikube")
            echo -e "${YELLOW}Minikube Cleanup:${NC}"
            echo "  • Stop cluster: minikube stop"
            echo "  • Delete cluster: minikube delete"
            echo "  • Delete all profiles: minikube delete --all"
            ;;
        "unknown")
            echo -e "${YELLOW}External Cluster Cleanup:${NC}"
            echo "  • Check your cluster provider documentation"
            echo "  • Remove any cluster-specific resources manually"
            ;;
        *)
            echo -e "${GREEN}Docker Desktop Kubernetes:${NC}"
            echo "  • No additional cleanup required"
            echo "  • Cluster will remain available for other projects"
            ;;
    esac
    
    echo
    echo -e "${YELLOW}Optional LocalStack Cleanup (if no longer needed):${NC}"
    echo "  • Stop LocalStack: docker stop localstack-idp"
    echo "  • Remove container: docker rm localstack-idp"
    echo "  • Remove data: rm -rf \${TMPDIR:-/tmp}/localstack"
    echo "  • Note: This will remove ALL LocalStack data, not just IDP"
    echo
    echo -e "${YELLOW}System Tools (preserved):${NC}"
    echo "  • awslocal, kubectl, docker, jq remain installed"
    echo "  • AWS CLI configuration preserved"
    echo "  • Remove manually if desired: pip3 uninstall awslocal"
}

# Function to confirm uninstall
confirm_uninstall() {
    if [[ "$CONFIRMATION_REQUIRED" == "false" ]]; then
        return 0
    fi
    
    echo -e "${RED}⚠️  CONFIRMATION REQUIRED${NC}"
    echo -e "${YELLOW}This will remove IDP Platform resources. Are you sure?${NC}"
    echo
    read -p "Type 'yes' to continue: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        echo -e "${BLUE}💡 Uninstall cancelled. Run with --dry-run to see what would be removed.${NC}"
        exit 0
    fi
}

# Function to show help
show_help() {
    echo -e "${BLUE}IDP Platform Uninstall Script${NC}"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --dry-run              Show what would be removed without actually removing"
    echo "  --yes                  Skip confirmation prompt"
    echo "  --help                 Show this help message"
    echo
    echo "Examples:"
    echo "  $0                     Interactive uninstall with confirmation"
    echo "  $0 --dry-run           Show removal plan without executing"
    echo "  $0 --yes               Uninstall without confirmation"
    echo "  $0 --dry-run --yes     Show plan without confirmation"
    echo
    echo "What gets removed:"
    echo "  • All IDP Kubernetes resources and namespaces"
    echo "  • IDP-related Docker images and containers"
    echo "  • LocalStack ECR repositories (IDP workloads only)"
    echo "  • Generated configuration files"
    echo
    echo "What gets preserved:"
    echo "  • Kubernetes cluster (Docker Desktop/Kind/Minikube)"
    echo "  • External LocalStack installation and data"
    echo "  • System tools (awslocal, kubectl, docker, etc.)"
    echo "  • Non-IDP Docker images and containers"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes)
            CONFIRMATION_REQUIRED=false
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo -e "${RED}🧹 IDP Platform Uninstall${NC}"
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${CYAN}🔍 DRY RUN MODE - No changes will be made${NC}"
        echo
    fi
    
    # Detect Kubernetes runtime
    local k8s_runtime
    k8s_runtime=$(detect_k8s_runtime)
    echo
    
    # Show removal plan
    show_removal_plan
    
    # Confirm if required
    if [[ "$DRY_RUN" == "false" ]]; then
        confirm_uninstall
        echo
    fi
    
    # Execute removal steps
    echo -e "${BLUE}🚀 Starting IDP Platform removal...${NC}"
    echo
    
    stop_port_forwards
    echo
    
    remove_k8s_namespaces
    echo
    
    remove_crds
    echo
    
    remove_docker_images
    echo
    
    clean_localstack_ecr
    echo
    
    cleanup_generated_files
    echo
    
    # Show completion status
    if [[ "$DRY_RUN" == "false" ]]; then
        echo -e "${GREEN}✅ IDP Platform removal completed!${NC}"
    else
        echo -e "${CYAN}🔍 Dry run completed - no changes made${NC}"
    fi
    echo
    
    # Show manual cleanup instructions
    show_manual_cleanup "$k8s_runtime"
    
    echo -e "${BLUE}💡 You can re-install the IDP Platform anytime by running the setup scripts${NC}"
}

# Run main function
main "$@"