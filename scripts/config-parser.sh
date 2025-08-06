#!/bin/bash

# IDP Configuration Parser
# Parses YAML configuration and provides environment variables for other scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/.idp-config"
CONFIG_FILE="$CONFIG_DIR/idp-config.yaml"

# Function to print status
print_status() {
    echo -e "${BLUE}[CONFIG]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to parse YAML value
parse_yaml_value() {
    local key="$1"
    local file="$2"
    
    if [ -f "$file" ]; then
        # Simple YAML parsing - looks for key: value pairs
        grep "^[[:space:]]*${key}:" "$file" | sed 's/.*:[[:space:]]*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
    fi
}

# Function to check if key exists and has value
yaml_key_exists() {
    local key="$1"
    local file="$2"
    
    if [ -f "$file" ] && grep -q "^[[:space:]]*${key}:" "$file"; then
        local value=$(parse_yaml_value "$key" "$file")
        [ -n "$value" ] && [ "$value" != "false" ]
    else
        return 1
    fi
}

# Function to export configuration as environment variables
export_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        print_status "Run './scripts/idp-setup-wizard.sh' to generate configuration"
        return 1
    fi
    
    print_status "Loading IDP configuration from $CONFIG_FILE"
    
    # Parse platform configuration
    export IDP_PLATFORM_NAME=$(parse_yaml_value "name" "$CONFIG_FILE")
    export IDP_PLATFORM_NAMESPACE=$(parse_yaml_value "namespace" "$CONFIG_FILE")
    export IDP_PLATFORM_DOMAIN=$(parse_yaml_value "domain" "$CONFIG_FILE")
    export IDP_PLATFORM_MODE=$(parse_yaml_value "mode" "$CONFIG_FILE")
    
    # Parse resource configuration
    export IDP_CPU_LIMIT=$(parse_yaml_value "cpu_limit" "$CONFIG_FILE")
    export IDP_MEMORY_LIMIT=$(parse_yaml_value "memory_limit" "$CONFIG_FILE")
    
    # Parse data protection settings
    if yaml_key_exists "enabled" "$CONFIG_FILE" && grep -A5 "data_protection:" "$CONFIG_FILE" | grep -q "enabled: true"; then
        export IDP_DATA_PROTECTION_ENABLED=true
        export IDP_NETWORK_POLICIES_ENABLED=true
        export IDP_AUDIT_LOGGING_ENABLED=true
        export IDP_ENCRYPTION_IN_TRANSIT=true
    else
        export IDP_DATA_PROTECTION_ENABLED=false
        export IDP_NETWORK_POLICIES_ENABLED=false
        export IDP_AUDIT_LOGGING_ENABLED=false
        export IDP_ENCRYPTION_IN_TRANSIT=false
    fi
    
    # Parse external systems configuration
    if grep -A10 "external_systems:" "$CONFIG_FILE" | grep -A5 "security_tools:" | grep -q "enabled: true"; then
        export IDP_EXTERNAL_SECURITY_ENABLED=true
        
        # Check for specific security tools
        if grep -A20 "security_tools:" "$CONFIG_FILE" | grep -A5 "fortify:" | grep -q "enabled: true"; then
            export IDP_FORTIFY_ENABLED=true
            export IDP_FORTIFY_SERVER_URL=$(grep -A20 "security_tools:" "$CONFIG_FILE" | grep -A10 "fortify:" | parse_yaml_value "server_url" /dev/stdin)
            export IDP_FORTIFY_USERNAME=$(grep -A20 "security_tools:" "$CONFIG_FILE" | grep -A10 "fortify:" | parse_yaml_value "username" /dev/stdin)
        fi
        
        if grep -A20 "security_tools:" "$CONFIG_FILE" | grep -A5 "veracode:" | grep -q "enabled: true"; then
            export IDP_VERACODE_ENABLED=true
            export IDP_VERACODE_API_ID=$(grep -A20 "security_tools:" "$CONFIG_FILE" | grep -A10 "veracode:" | parse_yaml_value "api_id" /dev/stdin)
        fi
    else
        export IDP_EXTERNAL_SECURITY_ENABLED=false
    fi
    
    # Parse container registry configuration
    if grep -A10 "external_systems:" "$CONFIG_FILE" | grep -A5 "container_registry:" | grep -q "enabled: true"; then
        export IDP_EXTERNAL_REGISTRY_ENABLED=true
        export IDP_REGISTRY_TYPE=$(grep -A10 "container_registry:" "$CONFIG_FILE" | parse_yaml_value "type" /dev/stdin)
        
        case "$IDP_REGISTRY_TYPE" in
            "AWS ECR")
                export IDP_ECR_REGION=$(grep -A15 "container_registry:" "$CONFIG_FILE" | grep -A5 "aws_ecr:" | parse_yaml_value "region" /dev/stdin)
                export IDP_ECR_REGISTRY_URL=$(grep -A15 "container_registry:" "$CONFIG_FILE" | grep -A5 "aws_ecr:" | parse_yaml_value "registry_url" /dev/stdin)
                ;;
            "Harbor")
                export IDP_HARBOR_URL=$(grep -A15 "container_registry:" "$CONFIG_FILE" | grep -A5 "harbor:" | parse_yaml_value "server_url" /dev/stdin)
                export IDP_HARBOR_USERNAME=$(grep -A15 "container_registry:" "$CONFIG_FILE" | grep -A5 "harbor:" | parse_yaml_value "username" /dev/stdin)
                ;;
        esac
    else
        export IDP_EXTERNAL_REGISTRY_ENABLED=false
        # Use LocalStack ECR as default
        export IDP_REGISTRY_TYPE="LocalStack ECR"
        export IDP_ECR_REGISTRY_URL="000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566"
    fi
    
    # Parse identity provider configuration
    if grep -A10 "external_systems:" "$CONFIG_FILE" | grep -A5 "identity_provider:" | grep -q "enabled: true"; then
        export IDP_EXTERNAL_AUTH_ENABLED=true
        export IDP_AUTH_PROVIDER=$(grep -A10 "identity_provider:" "$CONFIG_FILE" | parse_yaml_value "type" /dev/stdin)
        
        case "$IDP_AUTH_PROVIDER" in
            "AWS Cognito")
                export IDP_COGNITO_USER_POOL_ID=$(grep -A15 "identity_provider:" "$CONFIG_FILE" | grep -A5 "aws_cognito:" | parse_yaml_value "user_pool_id" /dev/stdin)
                export IDP_COGNITO_CLIENT_ID=$(grep -A15 "identity_provider:" "$CONFIG_FILE" | grep -A5 "aws_cognito:" | parse_yaml_value "client_id" /dev/stdin)
                export IDP_COGNITO_REGION=$(grep -A15 "identity_provider:" "$CONFIG_FILE" | grep -A5 "aws_cognito:" | parse_yaml_value "region" /dev/stdin)
                ;;
            "Okta")
                export IDP_OKTA_DOMAIN=$(grep -A15 "identity_provider:" "$CONFIG_FILE" | grep -A5 "okta:" | parse_yaml_value "domain" /dev/stdin)
                export IDP_OKTA_CLIENT_ID=$(grep -A15 "identity_provider:" "$CONFIG_FILE" | grep -A5 "okta:" | parse_yaml_value "client_id" /dev/stdin)
                ;;
        esac
    else
        export IDP_EXTERNAL_AUTH_ENABLED=false
        # Use default LocalStack Cognito
        export IDP_AUTH_PROVIDER="LocalStack Cognito"
    fi
    
    # Parse monitoring configuration
    if grep -A10 "external_systems:" "$CONFIG_FILE" | grep -A5 "monitoring:" | grep -q "enabled: true"; then
        export IDP_EXTERNAL_MONITORING_ENABLED=true
    else
        export IDP_EXTERNAL_MONITORING_ENABLED=false
    fi
    
    # Set component flags
    export IDP_ARGOCD_ENABLED=true
    export IDP_BACKSTAGE_ENABLED=true
    export IDP_ISTIO_ENABLED=true
    export IDP_CROSSPLANE_ENABLED=true
    export IDP_EXTERNAL_SECRETS_ENABLED=true
    export IDP_PROMETHEUS_ENABLED=true
    export IDP_GRAFANA_ENABLED=true
    
    print_status "Configuration loaded successfully"
    return 0
}

# Function to show current configuration
show_config() {
    export_config
    
    echo ""
    echo -e "${BLUE}IDP Platform Configuration:${NC}"
    echo -e "  Platform Name: ${GREEN}${IDP_PLATFORM_NAME:-Not set}${NC}"
    echo -e "  Platform Mode: ${GREEN}${IDP_PLATFORM_MODE:-Not set}${NC}"
    echo -e "  Domain: ${GREEN}${IDP_PLATFORM_DOMAIN:-Not set}${NC}"
    echo -e "  Namespace: ${GREEN}${IDP_PLATFORM_NAMESPACE:-Not set}${NC}"
    echo ""
    echo -e "${BLUE}Resource Limits:${NC}"
    echo -e "  CPU Limit: ${GREEN}${IDP_CPU_LIMIT:-2}${NC}"
    echo -e "  Memory Limit: ${GREEN}${IDP_MEMORY_LIMIT:-4Gi}${NC}"
    echo ""
    echo -e "${BLUE}Data Protection:${NC}"
    echo -e "  Enabled: ${GREEN}$([ "$IDP_DATA_PROTECTION_ENABLED" = true ] && echo "Yes" || echo "No")${NC}"
    echo ""
    echo -e "${BLUE}External Systems:${NC}"
    echo -e "  Security Tools: ${GREEN}$([ "$IDP_EXTERNAL_SECURITY_ENABLED" = true ] && echo "Enabled" || echo "Disabled")${NC}"
    echo -e "  Container Registry: ${GREEN}$([ "$IDP_EXTERNAL_REGISTRY_ENABLED" = true ] && echo "$IDP_REGISTRY_TYPE" || echo "LocalStack ECR")${NC}"
    echo -e "  Identity Provider: ${GREEN}$([ "$IDP_EXTERNAL_AUTH_ENABLED" = true ] && echo "$IDP_AUTH_PROVIDER" || echo "LocalStack Cognito")${NC}"
    echo -e "  External Monitoring: ${GREEN}$([ "$IDP_EXTERNAL_MONITORING_ENABLED" = true ] && echo "Enabled" || echo "Disabled")${NC}"
}

# Function to validate configuration
validate_config() {
    export_config
    
    local validation_passed=true
    
    print_status "Validating IDP configuration..."
    
    # Validate required fields
    if [ -z "$IDP_PLATFORM_NAME" ]; then
        print_error "Platform name is required"
        validation_passed=false
    fi
    
    if [ -z "$IDP_PLATFORM_NAMESPACE" ]; then
        print_error "Platform namespace is required"
        validation_passed=false
    fi
    
    if [ -z "$IDP_PLATFORM_DOMAIN" ]; then
        print_error "Platform domain is required"
        validation_passed=false
    fi
    
    # Validate external system configurations
    if [ "$IDP_EXTERNAL_REGISTRY_ENABLED" = true ]; then
        case "$IDP_REGISTRY_TYPE" in
            "AWS ECR")
                if [ -z "$IDP_ECR_REGISTRY_URL" ]; then
                    print_error "ECR registry URL is required when using AWS ECR"
                    validation_passed=false
                fi
                ;;
            "Harbor")
                if [ -z "$IDP_HARBOR_URL" ]; then
                    print_error "Harbor server URL is required when using Harbor"
                    validation_passed=false
                fi
                ;;
        esac
    fi
    
    if [ "$IDP_EXTERNAL_AUTH_ENABLED" = true ]; then
        case "$IDP_AUTH_PROVIDER" in
            "AWS Cognito")
                if [ -z "$IDP_COGNITO_USER_POOL_ID" ] || [ -z "$IDP_COGNITO_CLIENT_ID" ]; then
                    print_error "Cognito User Pool ID and Client ID are required when using AWS Cognito"
                    validation_passed=false
                fi
                ;;
            "Okta")
                if [ -z "$IDP_OKTA_DOMAIN" ] || [ -z "$IDP_OKTA_CLIENT_ID" ]; then
                    print_error "Okta domain and client ID are required when using Okta"
                    validation_passed=false
                fi
                ;;
        esac
    fi
    
    if [ "$validation_passed" = true ]; then
        echo -e "${GREEN}✓ Configuration validation passed${NC}"
        return 0
    else
        echo -e "${RED}✗ Configuration validation failed${NC}"
        return 1
    fi
}

# Main execution based on parameters
case "$1" in
    "export")
        export_config
        ;;
    "show")
        show_config
        ;;
    "validate")
        validate_config
        ;;
    *)
        echo "Usage: $0 {export|show|validate}"
        echo "  export   - Export configuration as environment variables"
        echo "  show     - Display current configuration"
        echo "  validate - Validate configuration"
        exit 1
        ;;
esac