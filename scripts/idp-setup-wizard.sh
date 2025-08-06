#!/bin/bash

# IDP Platform Setup Wizard
# Comprehensive setup with external dependencies management and data loss protection

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/.idp-config"

# Create configuration directory
mkdir -p "$CONFIG_DIR"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              IDP Platform Setup Wizard                      ║"
echo "║                                                              ║"
echo "║  🔧 Configure your Integrated Developer Platform            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print status
print_header() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_status() {
    echo -e "${PURPLE}[INFO]${NC} $1"
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

# Function to get user input with default
get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " input
        eval "$var_name=\"\${input:-$default}\""
    else
        read -p "$prompt: " input
        eval "$var_name=\"$input\""
    fi
}

# Function to get yes/no input
get_yes_no() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    while true; do
        if [ "$default" = "y" ]; then
            read -p "$prompt [Y/n]: " yn
            yn=${yn:-y}
        else
            read -p "$prompt [y/N]: " yn
            yn=${yn:-n}
        fi
        
        case $yn in
            [Yy]* ) eval "$var_name=true"; break;;
            [Nn]* ) eval "$var_name=false"; break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Function to select from options
select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local var_name="${options[-1]}"
    unset 'options[-1]'  # Remove variable name from options
    
    echo -e "\n${BLUE}$prompt${NC}"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[i]}"
    done
    
    while true; do
        read -p "Select option (1-${#options[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            eval "$var_name=\"${options[$((choice-1))]}\""
            break
        else
            echo "Invalid choice. Please select 1-${#options[@]}."
        fi
    done
}

# Initialize configuration variables
IDP_MODE=""
ENABLE_DATA_PROTECTION=true
USE_EXTERNAL_SECURITY=false
USE_EXTERNAL_REGISTRY=false
USE_EXTERNAL_AUTH=false
USE_EXTERNAL_MONITORING=false

# Step 1: Welcome and Prerequisites
print_header "Welcome to IDP Platform Setup"

echo -e "${BLUE}This wizard will guide you through setting up your Integrated Developer Platform.${NC}"
echo -e "${BLUE}You can configure the platform for different environments and integration needs.${NC}"
echo ""
echo -e "${YELLOW}Prerequisites Check:${NC}"

# Check prerequisites
PREREQUISITES_MET=true

# Check Docker
if command -v docker &> /dev/null; then
    print_success "Docker is installed"
else
    print_error "Docker is required but not installed"
    PREREQUISITES_MET=false
fi

# Check kubectl
if command -v kubectl &> /dev/null; then
    print_success "kubectl is installed"
else
    print_error "kubectl is required but not installed"
    PREREQUISITES_MET=false
fi

# Check Kubernetes cluster
if kubectl cluster-info &> /dev/null; then
    print_success "Kubernetes cluster is accessible"
else
    print_warning "Kubernetes cluster not accessible (you can set this up later)"
fi

# Check available resources
if [ "$PREREQUISITES_MET" = false ]; then
    echo ""
    echo -e "${RED}❌ Prerequisites not met. Please install required tools before continuing.${NC}"
    echo -e "${BLUE}Installation guides:${NC}"
    echo -e "  • Docker: https://docs.docker.com/get-docker/"
    echo -e "  • kubectl: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

echo ""
get_yes_no "Continue with IDP setup?" "y" CONTINUE_SETUP

if [ "$CONTINUE_SETUP" = false ]; then
    echo "Setup cancelled."
    exit 0
fi

# Step 2: IDP Mode Selection
print_header "IDP Configuration Mode"

echo -e "${BLUE}Choose your IDP configuration mode based on your requirements:${NC}"
echo ""
echo -e "${GREEN}1. Fully Self-Contained Mode${NC}"
echo -e "   • All components hosted locally within your infrastructure"
echo -e "   • Maximum data protection and air-gap capability"
echo -e "   • Includes: Local security tools, artifact repositories, monitoring"
echo ""
echo -e "${GREEN}2. Enterprise Integration Mode${NC}"
echo -e "   • Integration with existing enterprise systems"
echo -e "   • Leverage existing security tools, artifact repositories, identity providers"
echo -e "   • Suitable for large organizations with established toolchains"
echo ""
echo -e "${GREEN}3. Hybrid Mode${NC}"
echo -e "   • Mix of local and external systems based on your needs"
echo -e "   • Flexible configuration for specific requirements"
echo -e "   • Balance between self-containment and enterprise integration"

select_option "Select your IDP mode:" "Fully Self-Contained Mode" "Enterprise Integration Mode" "Hybrid Mode" IDP_MODE

# Step 3: Data Loss Protection Settings
print_header "Data Loss Protection Configuration"

echo -e "${BLUE}Configure data loss protection policies for your IDP platform:${NC}"
echo ""
echo -e "${YELLOW}Data Loss Protection includes:${NC}"
echo -e "  • Build output isolation within controlled infrastructure"
echo -e "  • Network policies preventing unauthorized external communication"
echo -e "  • Complete audit logging of external system interactions"
echo -e "  • Encryption in transit with customer-managed certificates"

get_yes_no "Enable comprehensive data loss protection?" "y" ENABLE_DATA_PROTECTION

if [ "$ENABLE_DATA_PROTECTION" = true ]; then
    print_status "Data loss protection will be enabled with:"
    echo -e "  ✓ Network policies for traffic isolation"
    echo -e "  ✓ Audit logging for all external communications"
    echo -e "  ✓ Encrypted communication channels"
    echo -e "  ✓ Build artifact isolation"
fi

# Step 4: External System Configuration (if not fully self-contained)
if [ "$IDP_MODE" != "Fully Self-Contained Mode" ]; then
    print_header "External System Integration"
    
    echo -e "${BLUE}Configure integration with external systems:${NC}"
    echo ""
    
    # Security Tools
    echo -e "${CYAN}Security Scanning Tools:${NC}"
    get_yes_no "Integrate with external security scanning tools (Fortify, Veracode, Checkmarx)?" "n" USE_EXTERNAL_SECURITY
    
    # Container Registry
    echo -e "${CYAN}Container Registry:${NC}"
    get_yes_no "Use external container registry (JFrog Artifactory, AWS ECR, Azure ACR)?" "n" USE_EXTERNAL_REGISTRY
    
    # Authentication
    echo -e "${CYAN}Identity Provider:${NC}"
    get_yes_no "Integrate with external identity provider (Active Directory, Okta, Azure AD)?" "n" USE_EXTERNAL_AUTH
    
    # Monitoring
    echo -e "${CYAN}Monitoring and Observability:${NC}"
    get_yes_no "Use external monitoring systems (Datadog, New Relic, Splunk)?" "n" USE_EXTERNAL_MONITORING
fi

# Step 5: Detailed Configuration Collection
print_header "Detailed Configuration"

# Platform Configuration
get_input "Platform name" "idp-platform" PLATFORM_NAME
get_input "Platform namespace" "idp-system" PLATFORM_NAMESPACE
get_input "Domain for platform services" "idp.local" PLATFORM_DOMAIN

# Resource Configuration
get_input "CPU limit for platform services" "2" PLATFORM_CPU_LIMIT
get_input "Memory limit for platform services (Gi)" "4" PLATFORM_MEMORY_LIMIT

# Step 6: External System Specific Configuration
if [ "$USE_EXTERNAL_SECURITY" = true ]; then
    print_header "Security Tools Configuration"
    
    echo -e "${BLUE}Configure external security scanning tools:${NC}"
    
    get_yes_no "Configure Fortify Static Code Analyzer?" "n" USE_FORTIFY
    if [ "$USE_FORTIFY" = true ]; then
        get_input "Fortify server URL" "" FORTIFY_SERVER_URL
        get_input "Fortify username" "" FORTIFY_USERNAME
    fi
    
    get_yes_no "Configure Veracode scanning?" "n" USE_VERACODE
    if [ "$USE_VERACODE" = true ]; then
        get_input "Veracode API ID" "" VERACODE_API_ID
    fi
fi

if [ "$USE_EXTERNAL_REGISTRY" = true ]; then
    print_header "Container Registry Configuration"
    
    select_option "Select container registry type:" "AWS ECR" "Azure Container Registry" "JFrog Artifactory" "Harbor" REGISTRY_TYPE
    
    case "$REGISTRY_TYPE" in
        "AWS ECR")
            get_input "AWS region" "us-east-1" AWS_REGION
            get_input "ECR registry URL" "" ECR_REGISTRY_URL
            ;;
        "Azure Container Registry")
            get_input "ACR registry name" "" ACR_REGISTRY_NAME
            get_input "Azure tenant ID" "" AZURE_TENANT_ID
            ;;
        "JFrog Artifactory")
            get_input "Artifactory server URL" "" ARTIFACTORY_URL
            get_input "Artifactory username" "" ARTIFACTORY_USERNAME
            ;;
        "Harbor")
            get_input "Harbor server URL" "" HARBOR_URL
            get_input "Harbor username" "" HARBOR_USERNAME
            ;;
    esac
fi

if [ "$USE_EXTERNAL_AUTH" = true ]; then
    print_header "Identity Provider Configuration"
    
    select_option "Select identity provider:" "AWS Cognito" "Azure Active Directory" "Okta" "LDAP/Active Directory" AUTH_PROVIDER
    
    case "$AUTH_PROVIDER" in
        "AWS Cognito")
            get_input "Cognito User Pool ID" "" COGNITO_USER_POOL_ID
            get_input "Cognito Client ID" "" COGNITO_CLIENT_ID
            get_input "AWS region" "us-east-1" COGNITO_REGION
            ;;
        "Azure Active Directory")
            get_input "Azure tenant ID" "" AZURE_TENANT_ID
            get_input "Azure client ID" "" AZURE_CLIENT_ID
            ;;
        "Okta")
            get_input "Okta domain" "" OKTA_DOMAIN
            get_input "Okta client ID" "" OKTA_CLIENT_ID
            ;;
        "LDAP/Active Directory")
            get_input "LDAP server URL" "" LDAP_SERVER_URL
            get_input "LDAP bind DN" "" LDAP_BIND_DN
            ;;
    esac
fi

# Step 7: Generate Configuration
print_header "Configuration Generation"

print_status "Generating IDP configuration files..."

# Create main configuration file
cat > "$CONFIG_DIR/idp-config.yaml" << EOF
# IDP Platform Configuration
# Generated by IDP Setup Wizard

platform:
  name: ${PLATFORM_NAME}
  namespace: ${PLATFORM_NAMESPACE}
  domain: ${PLATFORM_DOMAIN}
  mode: ${IDP_MODE}

resources:
  cpu_limit: ${PLATFORM_CPU_LIMIT}
  memory_limit: ${PLATFORM_MEMORY_LIMIT}Gi

data_protection:
  enabled: ${ENABLE_DATA_PROTECTION}
  network_policies: ${ENABLE_DATA_PROTECTION}
  audit_logging: ${ENABLE_DATA_PROTECTION}
  encryption_in_transit: ${ENABLE_DATA_PROTECTION}

external_systems:
  security_tools:
    enabled: ${USE_EXTERNAL_SECURITY}
EOF

if [ "$USE_FORTIFY" = true ]; then
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    fortify:
      enabled: true
      server_url: ${FORTIFY_SERVER_URL}
      username: ${FORTIFY_USERNAME}
EOF
fi

if [ "$USE_VERACODE" = true ]; then
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    veracode:
      enabled: true
      api_id: ${VERACODE_API_ID}
EOF
fi

cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
  
  container_registry:
    enabled: ${USE_EXTERNAL_REGISTRY}
EOF

if [ "$USE_EXTERNAL_REGISTRY" = true ]; then
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    type: ${REGISTRY_TYPE}
EOF

case "$REGISTRY_TYPE" in
    "AWS ECR")
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    aws_ecr:
      region: ${AWS_REGION}
      registry_url: ${ECR_REGISTRY_URL}
EOF
        ;;
    "Azure Container Registry")
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    azure_acr:
      registry_name: ${ACR_REGISTRY_NAME}
      tenant_id: ${AZURE_TENANT_ID}
EOF
        ;;
    "JFrog Artifactory")
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    artifactory:
      server_url: ${ARTIFACTORY_URL}
      username: ${ARTIFACTORY_USERNAME}
EOF
        ;;
    "Harbor")
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    harbor:
      server_url: ${HARBOR_URL}
      username: ${HARBOR_USERNAME}
EOF
        ;;
esac
fi

cat >> "$CONFIG_DIR/idp-config.yaml" << EOF

  identity_provider:
    enabled: ${USE_EXTERNAL_AUTH}
EOF

if [ "$USE_EXTERNAL_AUTH" = true ]; then
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    type: ${AUTH_PROVIDER}
EOF

case "$AUTH_PROVIDER" in
    "AWS Cognito")
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    aws_cognito:
      user_pool_id: ${COGNITO_USER_POOL_ID}
      client_id: ${COGNITO_CLIENT_ID}
      region: ${COGNITO_REGION}
EOF
        ;;
    "Azure Active Directory")
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    azure_ad:
      tenant_id: ${AZURE_TENANT_ID}
      client_id: ${AZURE_CLIENT_ID}
EOF
        ;;
    "Okta")
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    okta:
      domain: ${OKTA_DOMAIN}
      client_id: ${OKTA_CLIENT_ID}
EOF
        ;;
    "LDAP/Active Directory")
cat >> "$CONFIG_DIR/idp-config.yaml" << EOF
    ldap:
      server_url: ${LDAP_SERVER_URL}
      bind_dn: ${LDAP_BIND_DN}
EOF
        ;;
esac
fi

cat >> "$CONFIG_DIR/idp-config.yaml" << EOF

  monitoring:
    enabled: ${USE_EXTERNAL_MONITORING}

# Component Configuration
components:
  argocd:
    enabled: true
    namespace: argocd
  
  backstage:
    enabled: true
    namespace: backstage
    external_repo: true
  
  istio:
    enabled: true
    namespace: istio-system
  
  crossplane:
    enabled: true
    namespace: crossplane-system
  
  external_secrets:
    enabled: true
    namespace: external-secrets
  
  monitoring:
    prometheus:
      enabled: true
      namespace: monitoring
    grafana:
      enabled: true
      namespace: monitoring
EOF

print_success "Configuration generated at: $CONFIG_DIR/idp-config.yaml"

# Generate deployment scripts
print_status "Generating deployment scripts..."

cat > "$CONFIG_DIR/deploy-idp.sh" << 'EOF'
#!/bin/bash

# IDP Platform Deployment Script
# Generated by IDP Setup Wizard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Starting IDP Platform deployment..."

# Load configuration
if [ -f "$SCRIPT_DIR/idp-config.yaml" ]; then
    echo "✓ Loading configuration from idp-config.yaml"
else
    echo "❌ Configuration file not found. Please run the setup wizard first."
    exit 1
fi

# Deploy based on configuration
echo "📦 Deploying platform components..."

# Setup LocalStack if self-contained mode
echo "🔧 Setting up LocalStack..."
"$ROOT_DIR/scripts/setup-external-localstack.sh"

# Setup external Backstage
echo "🏗️ Setting up Backstage application..."
"$ROOT_DIR/scripts/setup-backstage-external.sh"

# Start platform services
echo "🚀 Starting platform services..."
"$ROOT_DIR/scripts/quick-start.sh"

echo "✅ IDP Platform deployment completed!"
echo ""
echo "🔗 Access your platform:"
echo "  • ArgoCD: http://localhost:8080"
echo "  • Backstage: http://localhost:3000"
echo "  • Grafana: http://localhost:3001"

EOF

chmod +x "$CONFIG_DIR/deploy-idp.sh"

print_success "Deployment script generated at: $CONFIG_DIR/deploy-idp.sh"

# Step 8: Summary and Next Steps
print_header "Setup Complete"

echo -e "${GREEN}🎉 IDP Platform setup wizard completed successfully!${NC}"
echo ""
echo -e "${BLUE}Configuration Summary:${NC}"
echo -e "  • Platform Mode: ${GREEN}$IDP_MODE${NC}"
echo -e "  • Data Protection: ${GREEN}$([ "$ENABLE_DATA_PROTECTION" = true ] && echo "Enabled" || echo "Disabled")${NC}"
echo -e "  • External Security: ${GREEN}$([ "$USE_EXTERNAL_SECURITY" = true ] && echo "Enabled" || echo "Disabled")${NC}"
echo -e "  • External Registry: ${GREEN}$([ "$USE_EXTERNAL_REGISTRY" = true ] && echo "Enabled" || echo "Disabled")${NC}"
echo -e "  • External Auth: ${GREEN}$([ "$USE_EXTERNAL_AUTH" = true ] && echo "Enabled" || echo "Disabled")${NC}"
echo ""
echo -e "${BLUE}Generated Files:${NC}"
echo -e "  • Configuration: ${YELLOW}$CONFIG_DIR/idp-config.yaml${NC}"
echo -e "  • Deployment Script: ${YELLOW}$CONFIG_DIR/deploy-idp.sh${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo -e "  1. Review the generated configuration file"
echo -e "  2. Run the deployment script: ${YELLOW}$CONFIG_DIR/deploy-idp.sh${NC}"
echo -e "  3. Access your platform services once deployment completes"
echo ""
echo -e "${YELLOW}Note: You can re-run this wizard anytime to update your configuration.${NC}"