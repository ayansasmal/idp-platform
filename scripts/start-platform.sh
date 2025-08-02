#!/bin/bash

# IDP Platform Startup Script
# This script starts all port forwards for easy development access

# Note: We don't use 'set -e' here to allow graceful handling of service failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDS_FILE="${SCRIPT_DIR}/.port-forward-pids"

# Service configurations  
get_service_config() {
    case "$1" in
        "argocd") echo "argocd:argocd-server:8080:80" ;;
        "backstage") echo "backstage:backstage:3000:80" ;;
        "grafana") echo "istio-system:grafana:3001:3000" ;;
        "prometheus") echo "istio-system:prometheus:9090:9090" ;;
        "jaeger") echo "istio-system:tracing:16686:80" ;;
        "kiali") echo "istio-system:kiali:20001:20001" ;;
        "monitoring") echo "istio-system:monitoring-dashboard:8090:80" ;;
        "alertmanager") echo "istio-system:alertmanager:9093:9093" ;;
        *) echo "" ;;
    esac
}

# Get all service names
get_all_services() {
    echo "argocd backstage grafana prometheus jaeger kiali monitoring alertmanager"
}

# Help function
show_help() {
    echo -e "${BLUE}IDP Platform Startup Script${NC}"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start [services]    Start port forwarding for specified services (or all)"
    echo "  stop               Stop all port forwarding"
    echo "  status             Show status of port forwards"
    echo "  restart            Restart all port forwards"
    echo "  logs [service]     Show logs for a specific service"
    echo "  health             Check platform health"
    echo ""
    echo "Available services:"
    for service in $(get_all_services); do
        local config=$(get_service_config "$service")
        IFS=':' read -r namespace svc local_port remote_port <<< "$config"
        echo "  ${service} - http://localhost:${local_port}"
    done
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start all services"
    echo "  $0 start argocd backstage   # Start only ArgoCD and Backstage"
    echo "  $0 stop                     # Stop all port forwards"
    echo "  $0 status                   # Check what's running"
}

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
        exit 1
    fi
}

# Check if cluster is accessible
check_cluster() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
        echo "Make sure your cluster is running and kubectl is configured"
        exit 1
    fi
}

# Wait for service to be ready
wait_for_service() {
    local namespace=$1
    local service=$2
    local timeout=60
    local count=0
    
    echo -n "Waiting for ${namespace}/${service} to be ready..."
    
    while [ $count -lt $timeout ]; do
        if kubectl get svc -n "$namespace" "$service" &> /dev/null; then
            echo -e " ${GREEN}✓${NC}"
            return 0
        fi
        echo -n "."
        sleep 1
        ((count++))
    done
    
    echo -e " ${RED}✗${NC}"
    echo -e "${YELLOW}Warning: Service ${namespace}/${service} not found${NC}"
    return 1
}

# Start port forward for a service
start_port_forward() {
    local service_name=$1
    local config=$(get_service_config "$service_name")
    
    if [[ -z "$config" ]]; then
        echo -e "${RED}Error: Unknown service '$service_name'${NC}"
        return 1
    fi
    
    IFS=':' read -r namespace svc local_port remote_port <<< "$config"
    
    # Check if port is already in use
    if lsof -Pi :$local_port -sTCP:LISTEN -t &> /dev/null; then
        echo -e "${YELLOW}Port $local_port already in use for $service_name${NC}"
        # Store PID anyway since service might be running from previous session
        local existing_pid=$(lsof -Pi :$local_port -sTCP:LISTEN -t)
        echo "$service_name:$existing_pid:$local_port" >> "$PIDS_FILE"
        return 0
    fi
    
    # Wait for service to be ready
    if ! wait_for_service "$namespace" "$svc"; then
        return 1
    fi
    
    # Start port forward in background
    echo -e "Starting ${BLUE}$service_name${NC} on http://localhost:${GREEN}$local_port${NC}"
    kubectl port-forward -n "$namespace" "svc/$svc" "$local_port:$remote_port" &> /dev/null &
    local pid=$!
    
    # Store PID
    echo "$service_name:$pid:$local_port" >> "$PIDS_FILE"
    
    # Wait a moment and check if it started successfully
    sleep 2
    if ! kill -0 "$pid" 2>/dev/null; then
        echo -e "${RED}Error: Failed to start port forward for $service_name${NC}"
        return 1
    fi
    
    return 0
}

# Stop all port forwards
stop_port_forwards() {
    if [[ ! -f "$PIDS_FILE" ]]; then
        echo -e "${YELLOW}No active port forwards found${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Stopping port forwards...${NC}"
    
    while IFS=':' read -r service_name pid port; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo -e "Stopping ${service_name} (PID: $pid, Port: $port)"
            kill "$pid" 2>/dev/null || true
        fi
    done < "$PIDS_FILE"
    
    # Clean up PID file
    rm -f "$PIDS_FILE"
    
    # Kill any remaining kubectl port-forward processes
    pkill -f "kubectl port-forward" 2>/dev/null || true
    
    echo -e "${GREEN}All port forwards stopped${NC}"
}

# Show status of port forwards
show_status() {
    echo -e "${BLUE}IDP Platform Service Status${NC}"
    echo "----------------------------------------"
    
    if [[ ! -f "$PIDS_FILE" ]]; then
        echo -e "${YELLOW}No active port forwards${NC}"
        return 0
    fi
    
    local active_count=0
    
    while IFS=':' read -r service_name pid port; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $service_name - http://localhost:$port (PID: $pid)"
            ((active_count++))
        else
            echo -e "${RED}✗${NC} $service_name - stopped"
        fi
    done < "$PIDS_FILE"
    
    echo "----------------------------------------"
    echo -e "Active services: ${GREEN}$active_count${NC}"
    
    # Clean up stale entries
    if [[ $active_count -eq 0 ]]; then
        rm -f "$PIDS_FILE"
    fi
}

# Check platform health
check_health() {
    echo -e "${BLUE}IDP Platform Health Check${NC}"
    echo "----------------------------------------"
    
    # Check cluster connectivity
    if kubectl cluster-info &> /dev/null; then
        echo -e "${GREEN}✓${NC} Kubernetes cluster - Connected"
    else
        echo -e "${RED}✗${NC} Kubernetes cluster - Not accessible"
        return 1
    fi
    
    # Check critical namespaces
    local namespaces=("argocd" "backstage" "istio-system")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            echo -e "${GREEN}✓${NC} Namespace $ns - Exists"
        else
            echo -e "${RED}✗${NC} Namespace $ns - Missing"
        fi
    done
    
    # Check service availability
    echo ""
    echo "Service Availability:"
    for service_name in $(get_all_services); do
        local config=$(get_service_config "$service_name")
        IFS=':' read -r namespace svc local_port remote_port <<< "$config"
        if kubectl get svc -n "$namespace" "$svc" &> /dev/null; then
            local ready=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name="$svc" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
            if [[ $ready -gt 0 ]]; then
                echo -e "${GREEN}✓${NC} $service_name ($namespace/$svc) - Ready"
            else
                echo -e "${YELLOW}⚠${NC} $service_name ($namespace/$svc) - Service exists but no ready pods"
            fi
        else
            echo -e "${RED}✗${NC} $service_name ($namespace/$svc) - Service not found"
        fi
    done
}

# Show logs for a service
show_logs() {
    local service_name=$1
    
    if [[ -z "$service_name" ]]; then
        echo -e "${RED}Error: Please specify a service name${NC}"
        echo "Available services: $(get_all_services)"
        return 1
    fi
    
    local config=$(get_service_config "$service_name")
    if [[ -z "$config" ]]; then
        echo -e "${RED}Error: Unknown service '$service_name'${NC}"
        return 1
    fi
    
    IFS=':' read -r namespace svc local_port remote_port <<< "$config"
    
    echo -e "${BLUE}Showing logs for $service_name${NC}"
    echo "Press Ctrl+C to exit"
    echo "----------------------------------------"
    
    kubectl logs -n "$namespace" -l app.kubernetes.io/name="$svc" -f
}

# Main function
main() {
    check_kubectl
    check_cluster
    
    case "${1:-start}" in
        "start")
            shift
            if [[ $# -eq 0 ]]; then
                # Start all services
                echo -e "${BLUE}Starting all IDP platform services...${NC}"
                echo ""
                
                # Stop any existing port forwards first
                stop_port_forwards
                
                local started_count=0
                for service_name in $(get_all_services); do
                    if start_port_forward "$service_name"; then
                        ((started_count++))
                    fi
                done
                
                echo ""
                echo -e "${GREEN}Started $started_count services${NC}"
                echo ""
                echo -e "${BLUE}Access your services:${NC}"
                for service_name in $(get_all_services); do
                    local config=$(get_service_config "$service_name")
                    IFS=':' read -r namespace svc local_port remote_port <<< "$config"
                    echo -e "  ${service_name}: ${GREEN}http://localhost:${local_port}${NC}"
                done
                echo ""
                echo -e "${YELLOW}Note: Keep this terminal open to maintain port forwards${NC}"
                echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"
                
                # Wait for interrupt
                trap 'echo -e "\n${BLUE}Shutting down...${NC}"; stop_port_forwards; exit 0' INT
                while true; do
                    sleep 1
                done
            else
                # Start specific services
                echo -e "${BLUE}Starting specified services...${NC}"
                echo ""
                
                local started_count=0
                for service_name in "$@"; do
                    if start_port_forward "$service_name"; then
                        ((started_count++))
                    fi
                done
                
                echo ""
                echo -e "${GREEN}Started $started_count services${NC}"
            fi
            ;;
        "stop")
            stop_port_forwards
            ;;
        "status")
            show_status
            ;;
        "restart")
            echo -e "${BLUE}Restarting all port forwards...${NC}"
            stop_port_forwards
            sleep 2
            exec "$0" start
            ;;
        "health")
            check_health
            ;;
        "logs")
            show_logs "$2"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$1'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"