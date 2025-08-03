#!/bin/bash

# IDP CLI MCP Server Management Extension
# Usage: idp-cli mcp <command> [options]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="mcp-platform"
MCP_API_VERSION="platform.idp/v1alpha1"

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
}

# Check if MCP platform is deployed
check_mcp_platform() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "MCP platform namespace '$NAMESPACE' not found. Please deploy the MCP platform first."
        exit 1
    fi
}

# List MCP servers
list_mcp_servers() {
    local format=${1:-"table"}
    
    log_info "Listing MCP servers in namespace: $NAMESPACE"
    
    if [[ "$format" == "json" ]]; then
        kubectl get mcpservers -n "$NAMESPACE" -o json
    elif [[ "$format" == "yaml" ]]; then
        kubectl get mcpservers -n "$NAMESPACE" -o yaml
    else
        kubectl get mcpservers -n "$NAMESPACE" -o wide
    fi
}

# Get MCP server details
get_mcp_server() {
    local server_name="$1"
    local format=${2:-"yaml"}
    
    if [[ -z "$server_name" ]]; then
        log_error "MCP server name is required"
        exit 1
    fi
    
    log_info "Getting details for MCP server: $server_name"
    kubectl get mcpserver "$server_name" -n "$NAMESPACE" -o "$format"
}

# Create MCP server
create_mcp_server() {
    local server_name="$1"
    local server_type="$2"
    local capabilities="$3"
    local runtime=${4:-"python"}
    
    if [[ -z "$server_name" || -z "$server_type" || -z "$capabilities" ]]; then
        log_error "Usage: idp-cli mcp create <name> <type> <capabilities> [runtime]"
        log_error "Types: code-intelligence, infrastructure-intelligence, document-processing, workflow-automation, security-analysis"
        log_error "Example: idp-cli mcp create my-code-server code-intelligence 'code-completion,code-review' python"
        exit 1
    fi
    
    # Convert comma-separated capabilities to array format
    local caps_array=""
    IFS=',' read -ra CAPS <<< "$capabilities"
    for cap in "${CAPS[@]}"; do
        caps_array+="    - \"$(echo "$cap" | xargs)\"\n"
    done
    
    cat <<EOF | kubectl apply -f -
apiVersion: platform.idp/v1alpha1
kind: MCPServer
metadata:
  name: $server_name
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: $server_name
    app.kubernetes.io/component: mcp-server
    app.kubernetes.io/part-of: idp-platform
    platform.idp/type: mcp-server
    platform.idp/environment: development
spec:
  serverType: $server_type
  runtime: $runtime
  capabilities:
$(echo -e "$caps_array")
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "4Gi"
  scaling:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    targetCPUUtilization: 70
  security:
    authentication: true
    authorization: true
    encryption: true
    dataRetention: "30d"
    auditLogging: true
  networking:
    internalOnly: false
    loadBalancer: true
    istioInjection: true
EOF
    
    log_success "MCP server '$server_name' created successfully"
}

# Delete MCP server
delete_mcp_server() {
    local server_name="$1"
    local confirm=${2:-"false"}
    
    if [[ -z "$server_name" ]]; then
        log_error "MCP server name is required"
        exit 1
    fi
    
    if [[ "$confirm" != "--confirm" ]]; then
        read -p "Are you sure you want to delete MCP server '$server_name'? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deletion cancelled"
            exit 0
        fi
    fi
    
    kubectl delete mcpserver "$server_name" -n "$NAMESPACE"
    log_success "MCP server '$server_name' deleted successfully"
}

# Scale MCP server
scale_mcp_server() {
    local server_name="$1"
    local replicas="$2"
    
    if [[ -z "$server_name" || -z "$replicas" ]]; then
        log_error "Usage: idp-cli mcp scale <name> <replicas>"
        exit 1
    fi
    
    if ! [[ "$replicas" =~ ^[0-9]+$ ]] || [[ "$replicas" -lt 0 ]]; then
        log_error "Replicas must be a non-negative integer"
        exit 1
    fi
    
    kubectl patch mcpserver "$server_name" -n "$NAMESPACE" --type='merge' -p="{\"spec\":{\"scaling\":{\"minReplicas\":$replicas,\"maxReplicas\":$(($replicas > 5 ? $replicas : 5))}}}"
    log_success "MCP server '$server_name' scaled to $replicas replicas"
}

# Get MCP server logs
logs_mcp_server() {
    local server_name="$1"
    local follow=${2:-"false"}
    
    if [[ -z "$server_name" ]]; then
        log_error "MCP server name is required"
        exit 1
    fi
    
    local selector="app.kubernetes.io/name=$server_name"
    local kubectl_args="-l $selector -n $NAMESPACE"
    
    if [[ "$follow" == "-f" || "$follow" == "--follow" ]]; then
        kubectl_args+=" -f"
    fi
    
    log_info "Getting logs for MCP server: $server_name"
    kubectl logs $kubectl_args
}

# Get MCP server status
status_mcp_server() {
    local server_name="$1"
    
    if [[ -z "$server_name" ]]; then
        log_error "MCP server name is required"
        exit 1
    fi
    
    log_info "Status for MCP server: $server_name"
    echo
    
    # Get MCP server status
    local status=$(kubectl get mcpserver "$server_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Not Found")
    local replicas=$(kubectl get mcpserver "$server_name" -n "$NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    local ready_replicas=$(kubectl get mcpserver "$server_name" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    echo "Status: $status"
    echo "Replicas: $ready_replicas/$replicas"
    echo
    
    # Get pod status
    echo "Pod Status:"
    kubectl get pods -l "app.kubernetes.io/name=$server_name" -n "$NAMESPACE" 2>/dev/null || echo "No pods found"
    echo
    
    # Get service endpoints
    echo "Service Endpoints:"
    kubectl get endpoints -l "app.kubernetes.io/name=$server_name" -n "$NAMESPACE" 2>/dev/null || echo "No endpoints found"
}

# Show MCP server metrics
metrics_mcp_server() {
    local server_name="$1"
    
    if [[ -z "$server_name" ]]; then
        log_error "MCP server name is required"
        exit 1
    fi
    
    log_info "Metrics for MCP server: $server_name"
    
    # Get metrics from the MCP server status
    local metrics=$(kubectl get mcpserver "$server_name" -n "$NAMESPACE" -o jsonpath='{.status.metrics}' 2>/dev/null)
    
    if [[ -n "$metrics" && "$metrics" != "null" ]]; then
        echo "$metrics" | jq .
    else
        log_warning "No metrics available for MCP server '$server_name'"
        echo "Try accessing metrics directly:"
        echo "kubectl port-forward -n $NAMESPACE svc/$server_name-service 8081:8081"
        echo "curl http://localhost:8081/metrics"
    fi
}

# Show help
show_help() {
    cat <<EOF
IDP CLI - MCP Server Management

Usage: idp-cli mcp <command> [options]

Commands:
  list [format]                    List all MCP servers (format: table, json, yaml)
  get <name> [format]              Get MCP server details (format: table, json, yaml)
  create <name> <type> <caps> [rt] Create a new MCP server
  delete <name> [--confirm]        Delete an MCP server
  scale <name> <replicas>          Scale MCP server replicas
  logs <name> [-f|--follow]        Get MCP server logs
  status <name>                    Get MCP server status and health
  metrics <name>                   Get MCP server metrics
  help                             Show this help message

Server Types:
  - code-intelligence              Code analysis, completion, and review
  - infrastructure-intelligence    Resource optimization and cost analysis
  - document-processing           Documentation generation and knowledge extraction
  - workflow-automation           CI/CD and workflow optimization
  - security-analysis             Security scanning and compliance

Examples:
  idp-cli mcp list
  idp-cli mcp create code-ai code-intelligence "code-completion,code-review" python
  idp-cli mcp scale code-ai 3
  idp-cli mcp logs code-ai -f
  idp-cli mcp delete code-ai --confirm

Environment Variables:
  MCP_NAMESPACE                   Override default namespace (default: mcp-platform)

EOF
}

# Main function
main() {
    check_kubectl
    
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        "list")
            check_mcp_platform
            list_mcp_servers "$@"
            ;;
        "get")
            check_mcp_platform
            get_mcp_server "$@"
            ;;
        "create")
            check_mcp_platform
            create_mcp_server "$@"
            ;;
        "delete")
            check_mcp_platform
            delete_mcp_server "$@"
            ;;
        "scale")
            check_mcp_platform
            scale_mcp_server "$@"
            ;;
        "logs")
            check_mcp_platform
            logs_mcp_server "$@"
            ;;
        "status")
            check_mcp_platform
            status_mcp_server "$@"
            ;;
        "metrics")
            check_mcp_platform
            metrics_mcp_server "$@"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Override namespace if environment variable is set
if [[ -n "${MCP_NAMESPACE:-}" ]]; then
    NAMESPACE="$MCP_NAMESPACE"
fi

# Run main function with all arguments
main "$@"
