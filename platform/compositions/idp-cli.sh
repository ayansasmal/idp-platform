#!/bin/bash

# IDP Platform CLI
# Main entry point for IDP platform operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGMAP_NAME="idp-cli-scripts"
NAMESPACE="idp-system"

# Function to extract and run scripts from ConfigMap
extract_and_run() {
    local script_name="$1"
    shift
    
    # Get script from ConfigMap
    local script_content
    script_content=$(kubectl get configmap "$CONFIGMAP_NAME" -n "$NAMESPACE" -o jsonpath="{.data['$script_name']}" 2>/dev/null)
    
    if [ -z "$script_content" ]; then
        echo "Error: Script '$script_name' not found in ConfigMap '$CONFIGMAP_NAME'"
        exit 1
    fi
    
    # Create temporary script file
    local temp_script=$(mktemp)
    echo "$script_content" > "$temp_script"
    chmod +x "$temp_script"
    
    # Run the script
    "$temp_script" "$@"
    
    # Clean up
    rm -f "$temp_script"
}

# Main command handling
case "${1:-help}" in
    "create")
        shift
        extract_and_run "create-webapp.sh" "$@"
        ;;
    "delete")
        shift
        extract_and_run "delete-webapp.sh" "$@"
        ;;
    "list")
        shift
        extract_and_run "list-webapps.sh" "$@"
        ;;
    "status")
        shift
        extract_and_run "webapp-status.sh" "$@"
        ;;
    "help"|*)
        cat <<EOF
🚀 IDP Platform CLI

USAGE:
    $0 <command> [options]

COMMANDS:
    create <app-name> <image> [namespace] [environment] [replicas]
        Create a new WebApplication
        
    delete <app-name> [namespace]
        Delete a WebApplication
        
    list [namespace]
        List WebApplications (all namespaces if none specified)
        
    status <app-name> [namespace]
        Show detailed status of a WebApplication
        
    help
        Show this help message

EXAMPLES:
    # Create a simple nginx app
    $0 create my-app nginx:latest
    
    # Create an app in production
    $0 create api-server myapp:v1.2.3 production production 3
    
    # List all apps
    $0 list
    
    # Check app status
    $0 status my-app development
    
    # Delete an app
    $0 delete my-app

For more information, visit: https://github.com/your-org/idp-platform
EOF
        ;;
esac