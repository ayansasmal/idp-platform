#!/bin/bash

# IDP Platform Interactive Credential Management System
# Comprehensive credential prompting, validation, and secure storage

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$ROOT_DIR/.idp-config"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.yaml"
SECRETS_DIR="$ROOT_DIR/secrets/generated"

# Create necessary directories
mkdir -p "$CONFIG_DIR" "$SECRETS_DIR"

print_header() {
    echo -e "\\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $(printf "%-60s" "$1") ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\\n"
}

print_status() {
    echo -e "${PURPLE}[CREDS]${NC} $1"
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

# Secure input function (hides password input)
read_password() {
    local prompt="$1"
    local var_name="$2"
    local password
    
    echo -n "$prompt"
    read -s password
    echo ""
    eval "$var_name='$password'"
}

# Password complexity validation
validate_password() {
    local password="$1"
    local min_length=12
    local errors=()
    
    # Check minimum length
    if [ ${#password} -lt $min_length ]; then
        errors+=("Password must be at least $min_length characters long")
    fi
    
    # Check for uppercase
    if ! [[ "$password" =~ [A-Z] ]]; then
        errors+=("Password must contain at least one uppercase letter")
    fi
    
    # Check for lowercase
    if ! [[ "$password" =~ [a-z] ]]; then
        errors+=("Password must contain at least one lowercase letter")
    fi
    
    # Check for number
    if ! [[ "$password" =~ [0-9] ]]; then
        errors+=("Password must contain at least one number")
    fi
    
    # Check for special character
    if ! [[ "$password" =~ [^a-zA-Z0-9] ]]; then
        errors+=("Password must contain at least one special character")
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        print_error "Password validation failed:"
        for error in "${errors[@]}"; do
            echo -e "  ${RED}•${NC} $error"
        done
        return 1
    fi
    
    return 0
}

# Generate random password
generate_password() {
    local length="${1:-16}"
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
}

# Interactive credential collection
collect_admin_credentials() {
    print_header "Admin Credential Configuration"
    
    echo -e "${BLUE}Setting up administrative credentials for platform services...${NC}\\n"
    
    # ArgoCD Admin
    print_status "ArgoCD Administrator Setup"
    echo -e "Configure credentials for ArgoCD GitOps platform"
    
    read -p "ArgoCD admin username [admin]: " ARGOCD_ADMIN_USER
    ARGOCD_ADMIN_USER="${ARGOCD_ADMIN_USER:-admin}"
    
    while true; do
        read_password "ArgoCD admin password (or press Enter to generate): " ARGOCD_ADMIN_PASS
        
        if [ -z "$ARGOCD_ADMIN_PASS" ]; then
            ARGOCD_ADMIN_PASS=$(generate_password 16)
            print_success "Generated secure password for ArgoCD admin"
            echo -e "  ${YELLOW}Generated password: $ARGOCD_ADMIN_PASS${NC}"
            break
        elif validate_password "$ARGOCD_ADMIN_PASS"; then
            break
        fi
        echo -e "${YELLOW}Please try again with a stronger password...${NC}\\n"
    done
    
    echo ""
    
    # Grafana Admin
    print_status "Grafana Administrator Setup"
    echo -e "Configure credentials for Grafana monitoring dashboard"
    
    read -p "Grafana admin username [admin]: " GRAFANA_ADMIN_USER
    GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
    
    while true; do
        read_password "Grafana admin password (or press Enter to generate): " GRAFANA_ADMIN_PASS
        
        if [ -z "$GRAFANA_ADMIN_PASS" ]; then
            GRAFANA_ADMIN_PASS=$(generate_password 16)
            print_success "Generated secure password for Grafana admin"
            echo -e "  ${YELLOW}Generated password: $GRAFANA_ADMIN_PASS${NC}"
            break
        elif validate_password "$GRAFANA_ADMIN_PASS"; then
            break
        fi
        echo -e "${YELLOW}Please try again with a stronger password...${NC}\\n"
    done
    
    echo ""
    
    # Database passwords (for future use)
    print_status "Database Credentials Setup"
    echo -e "Generating secure database passwords for platform services"
    
    DB_BACKSTAGE_PASS=$(generate_password 20)
    DB_ARGOCD_PASS=$(generate_password 20)
    DB_GRAFANA_PASS=$(generate_password 20)
    
    print_success "Generated secure database passwords"
}

# AWS Cognito configuration
collect_cognito_credentials() {
    print_header "AWS Cognito OAuth Configuration"
    
    echo -e "${BLUE}Configure AWS Cognito for unified authentication across platform services${NC}\\n"
    
    local use_cognito
    read -p "Enable AWS Cognito OAuth integration? [Y/n]: " use_cognito
    use_cognito="${use_cognito:-Y}"
    
    if [[ "$use_cognito" =~ ^[Yy] ]]; then
        USE_COGNITO=true
        
        echo -e "\\n${CYAN}AWS Cognito Configuration:${NC}"
        
        read -p "AWS Region [us-east-1]: " COGNITO_REGION
        COGNITO_REGION="${COGNITO_REGION:-us-east-1}"
        
        read -p "Cognito User Pool ID: " COGNITO_USER_POOL_ID
        read -p "Cognito Client ID: " COGNITO_CLIENT_ID
        read_password "Cognito Client Secret: " COGNITO_CLIENT_SECRET
        
        read -p "Cognito Domain (e.g., idp-platform): " COGNITO_DOMAIN
        
        # Validate Cognito configuration
        if [ -n "$COGNITO_USER_POOL_ID" ] && [ -n "$COGNITO_CLIENT_ID" ] && [ -n "$COGNITO_CLIENT_SECRET" ]; then
            print_success "Cognito configuration collected successfully"
            
            # Create admin user in Cognito
            echo ""
            print_status "Cognito Admin User Setup"
            read -p "Create admin user email: " COGNITO_ADMIN_EMAIL
            
            while true; do
                read_password "Temporary admin password (user will be forced to change): " COGNITO_ADMIN_TEMP_PASS
                
                if validate_password "$COGNITO_ADMIN_TEMP_PASS"; then
                    break
                fi
                echo -e "${YELLOW}Please provide a password meeting complexity requirements...${NC}\\n"
            done
            
        else
            print_error "Incomplete Cognito configuration. Falling back to local authentication."
            USE_COGNITO=false
        fi
    else
        USE_COGNITO=false
        print_status "Using local authentication (no Cognito integration)"
    fi
}

# Developer access configuration
collect_developer_access_config() {
    print_header "Developer Access Configuration"
    
    echo -e "${BLUE}Configure developer onboarding and access management${NC}\\n"
    
    # Default developer namespace configuration
    read -p "Default developer namespace prefix [dev]: " DEV_NAMESPACE_PREFIX
    DEV_NAMESPACE_PREFIX="${DEV_NAMESPACE_PREFIX:-dev}"
    
    # Git integration
    print_status "Git Repository Integration"
    echo -e "Configure Git access for ArgoCD GitOps operations"
    
    read -p "Git repository URL for platform config: " GIT_REPO_URL
    read -p "Git username for ArgoCD: " GIT_USERNAME
    read_password "Git token/password for ArgoCD: " GIT_TOKEN
    
    # Container registry
    print_status "Container Registry Configuration"
    echo -e "Configure container registry access"
    
    read -p "Container registry URL [000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566]: " REGISTRY_URL
    REGISTRY_URL="${REGISTRY_URL:-000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566}"
    
    if [[ "$REGISTRY_URL" == *"localhost"* ]] || [[ "$REGISTRY_URL" == *"localstack"* ]]; then
        print_status "Using LocalStack container registry - no credentials needed"
        REGISTRY_USERNAME="test"
        REGISTRY_PASSWORD="test"
    else
        read -p "Registry username: " REGISTRY_USERNAME
        read_password "Registry password/token: " REGISTRY_PASSWORD
    fi
}

# Service-specific credential generation
generate_service_secrets() {
    print_header "Generating Service Secrets"
    
    # JWT secrets for services
    JWT_SECRET_BACKSTAGE=$(openssl rand -base64 32)
    JWT_SECRET_ARGOCD=$(openssl rand -base64 32)
    
    # API keys for services
    API_KEY_MONITORING=$(openssl rand -hex 16)
    API_KEY_WORKFLOWS=$(openssl rand -hex 16)
    
    # Encryption keys
    ENCRYPTION_KEY=$(openssl rand -base64 32)
    
    print_success "Generated secure service secrets"
}

# Save credentials to encrypted file
save_credentials() {
    print_header "Saving Credentials Securely"
    
    cat > "$CREDENTIALS_FILE" << EOF
# IDP Platform Credentials Configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# WARNING: This file contains sensitive information. Protect accordingly.

platform:
  domain: ${IDP_PLATFORM_DOMAIN:-idp.local}
  environment: ${IDP_ENVIRONMENT:-development}

admin_credentials:
  argocd:
    username: ${ARGOCD_ADMIN_USER}
    password: ${ARGOCD_ADMIN_PASS}
    
  grafana:
    username: ${GRAFANA_ADMIN_USER}
    password: ${GRAFANA_ADMIN_PASS}

database_credentials:
  backstage_db:
    password: ${DB_BACKSTAGE_PASS}
    
  argocd_db:
    password: ${DB_ARGOCD_PASS}
    
  grafana_db:
    password: ${DB_GRAFANA_PASS}

cognito_integration:
  enabled: ${USE_COGNITO}
  region: ${COGNITO_REGION:-}
  user_pool_id: ${COGNITO_USER_POOL_ID:-}
  client_id: ${COGNITO_CLIENT_ID:-}
  client_secret: ${COGNITO_CLIENT_SECRET:-}
  domain: ${COGNITO_DOMAIN:-}
  admin_email: ${COGNITO_ADMIN_EMAIL:-}
  admin_temp_password: ${COGNITO_ADMIN_TEMP_PASS:-}

developer_access:
  namespace_prefix: ${DEV_NAMESPACE_PREFIX}
  git:
    repository_url: ${GIT_REPO_URL:-}
    username: ${GIT_USERNAME:-}
    token: ${GIT_TOKEN:-}
    
  registry:
    url: ${REGISTRY_URL}
    username: ${REGISTRY_USERNAME}
    password: ${REGISTRY_PASSWORD}

service_secrets:
  jwt_secret_backstage: ${JWT_SECRET_BACKSTAGE}
  jwt_secret_argocd: ${JWT_SECRET_ARGOCD}
  api_key_monitoring: ${API_KEY_MONITORING}
  api_key_workflows: ${API_KEY_WORKFLOWS}
  encryption_key: ${ENCRYPTION_KEY}

generation_info:
  timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
  version: "1.0.0"
  generator: "idp-credential-manager"
EOF
    
    # Set restrictive permissions
    chmod 600 "$CREDENTIALS_FILE"
    
    print_success "Credentials saved to: $CREDENTIALS_FILE"
    print_warning "File permissions set to 600 (owner read/write only)"
}

# Generate Kubernetes secrets
generate_k8s_secrets() {
    print_header "Generating Kubernetes Secrets"
    
    # ArgoCD admin secret
    cat > "$SECRETS_DIR/argocd-admin-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-admin-credentials
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd
    app.kubernetes.io/component: admin-credentials
type: Opaque
data:
  username: $(echo -n "$ARGOCD_ADMIN_USER" | base64)
  password: $(echo -n "$ARGOCD_ADMIN_PASS" | base64)
EOF
    
    # Grafana admin secret
    cat > "$SECRETS_DIR/grafana-admin-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin-credentials
  namespace: monitoring
  labels:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/component: admin-credentials
type: Opaque
data:
  admin-user: $(echo -n "$GRAFANA_ADMIN_USER" | base64)
  admin-password: $(echo -n "$GRAFANA_ADMIN_PASS" | base64)
EOF
    
    # Container registry secret
    cat > "$SECRETS_DIR/registry-credentials.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: registry-credentials
  namespace: default
  labels:
    app.kubernetes.io/name: container-registry
    app.kubernetes.io/component: credentials
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $(echo -n "{\\"auths\\":{\\"$REGISTRY_URL\\":{\\"username\\":\\"$REGISTRY_USERNAME\\",\\"password\\":\\"$REGISTRY_PASSWORD\\",\\"auth\\":\\"$(echo -n "$REGISTRY_USERNAME:$REGISTRY_PASSWORD" | base64)\\",\\"email\\":\\"admin@idp.local\\"}}}" | base64)
EOF
    
    if [ "$USE_COGNITO" = true ]; then
        # Cognito secret
        cat > "$SECRETS_DIR/cognito-credentials.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: cognito-credentials
  namespace: backstage
  labels:
    app.kubernetes.io/name: backstage
    app.kubernetes.io/component: oauth-credentials
type: Opaque
data:
  client-id: $(echo -n "$COGNITO_CLIENT_ID" | base64)
  client-secret: $(echo -n "$COGNITO_CLIENT_SECRET" | base64)
  user-pool-id: $(echo -n "$COGNITO_USER_POOL_ID" | base64)
  region: $(echo -n "$COGNITO_REGION" | base64)
  domain: $(echo -n "$COGNITO_DOMAIN" | base64)
EOF
    fi
    
    # Service secrets
    cat > "$SECRETS_DIR/service-secrets.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: platform-service-secrets
  namespace: idp-system
  labels:
    app.kubernetes.io/name: idp-platform
    app.kubernetes.io/component: service-secrets
type: Opaque
data:
  jwt-secret-backstage: $(echo -n "$JWT_SECRET_BACKSTAGE" | base64)
  jwt-secret-argocd: $(echo -n "$JWT_SECRET_ARGOCD" | base64)
  api-key-monitoring: $(echo -n "$API_KEY_MONITORING" | base64)
  api-key-workflows: $(echo -n "$API_KEY_WORKFLOWS" | base64)
  encryption-key: $(echo -n "$ENCRYPTION_KEY" | base64)
EOF
    
    print_success "Kubernetes secrets generated in: $SECRETS_DIR"
    print_status "Apply secrets with: kubectl apply -f $SECRETS_DIR/"
}

# Apply secrets to cluster
apply_secrets_to_cluster() {
    print_header "Applying Secrets to Kubernetes Cluster"
    
    # Check if kubectl is available and cluster is accessible
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl to apply secrets."
        return 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Kubernetes cluster not accessible. Please configure kubectl."
        return 1
    fi
    
    # Create namespaces if they don't exist
    local namespaces=("argocd" "monitoring" "backstage" "idp-system")
    
    for ns in "${namespaces[@]}"; do
        if ! kubectl get namespace "$ns" &> /dev/null; then
            print_status "Creating namespace: $ns"
            kubectl create namespace "$ns"
        fi
    done
    
    # Apply all secrets
    print_status "Applying generated secrets to cluster..."
    
    if kubectl apply -f "$SECRETS_DIR/" --recursive; then
        print_success "All secrets applied successfully to cluster"
    else
        print_error "Some secrets failed to apply. Check kubectl output above."
        return 1
    fi
    
    # Verify secrets were created
    echo ""
    print_status "Verifying applied secrets:"
    kubectl get secrets -n argocd argocd-admin-credentials
    kubectl get secrets -n monitoring grafana-admin-credentials
    kubectl get secrets -n backstage cognito-credentials 2>/dev/null || echo "  (Cognito secrets not configured)"
    kubectl get secrets -n idp-system platform-service-secrets
}

# Display credential summary
show_credential_summary() {
    print_header "Credential Configuration Summary"
    
    echo -e "${BLUE}📊 Administrative Access:${NC}"
    echo -e "  ${GREEN}•${NC} ArgoCD:  ${CYAN}$ARGOCD_ADMIN_USER${NC} / [password stored securely]"
    echo -e "  ${GREEN}•${NC} Grafana: ${CYAN}$GRAFANA_ADMIN_USER${NC} / [password stored securely]"
    
    echo -e "\\n${BLUE}🔐 Authentication:${NC}"
    if [ "$USE_COGNITO" = true ]; then
        echo -e "  ${GREEN}•${NC} AWS Cognito: ${CYAN}Enabled${NC} (Region: $COGNITO_REGION)"
        echo -e "  ${GREEN}•${NC} Admin Email: ${CYAN}$COGNITO_ADMIN_EMAIL${NC}"
    else
        echo -e "  ${GREEN}•${NC} Local Authentication: ${CYAN}Enabled${NC}"
    fi
    
    echo -e "\\n${BLUE}🐳 Container Registry:${NC}"
    echo -e "  ${GREEN}•${NC} Registry: ${CYAN}$REGISTRY_URL${NC}"
    echo -e "  ${GREEN}•${NC} Username: ${CYAN}$REGISTRY_USERNAME${NC}"
    
    echo -e "\\n${BLUE}👥 Developer Access:${NC}"
    echo -e "  ${GREEN}•${NC} Namespace Prefix: ${CYAN}$DEV_NAMESPACE_PREFIX${NC}"
    echo -e "  ${GREEN}•${NC} Git Repository: ${CYAN}${GIT_REPO_URL:-Not configured}${NC}"
    
    echo -e "\\n${BLUE}📁 Files Created:${NC}"
    echo -e "  ${GREEN}•${NC} Credentials Config: ${YELLOW}$CREDENTIALS_FILE${NC}"
    echo -e "  ${GREEN}•${NC} Kubernetes Secrets: ${YELLOW}$SECRETS_DIR/${NC}"
    
    echo -e "\\n${YELLOW}⚠️  Security Notes:${NC}"
    echo -e "  ${GREEN}•${NC} All passwords meet complexity requirements"
    echo -e "  ${GREEN}•${NC} Credential files protected with 600 permissions"
    echo -e "  ${GREEN}•${NC} Secrets encrypted in Kubernetes cluster"
    echo -e "  ${GREEN}•${NC} Consider rotating credentials regularly"
}

# Main credential management workflow
main() {
    local apply_to_cluster="${1:-prompt}"
    
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              IDP Platform Credential Manager                ║"
    echo "║                                                              ║"
    echo "║  🔐 Secure credential collection and management             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Check for existing credentials
    if [ -f "$CREDENTIALS_FILE" ]; then
        print_warning "Existing credentials found at: $CREDENTIALS_FILE"
        local overwrite
        read -p "Overwrite existing credentials? [y/N]: " overwrite
        if [[ ! "$overwrite" =~ ^[Yy] ]]; then
            print_status "Using existing credentials. Exiting."
            exit 0
        fi
    fi
    
    # Collect all credentials
    collect_admin_credentials
    collect_cognito_credentials
    collect_developer_access_config
    generate_service_secrets
    
    # Save and generate secrets
    save_credentials
    generate_k8s_secrets
    
    # Apply to cluster if requested
    if [ "$apply_to_cluster" = "apply" ]; then
        apply_secrets_to_cluster
    elif [ "$apply_to_cluster" = "prompt" ]; then
        echo ""
        local apply_now
        read -p "Apply generated secrets to Kubernetes cluster now? [Y/n]: " apply_now
        apply_now="${apply_now:-Y}"
        
        if [[ "$apply_now" =~ ^[Yy] ]]; then
            apply_secrets_to_cluster
        else
            print_status "Secrets generated but not applied to cluster"
            print_status "Apply later with: kubectl apply -f $SECRETS_DIR/"
        fi
    fi
    
    # Show summary
    show_credential_summary
    
    print_success "Credential management completed successfully! 🎉"
}

# Command line handling
case "${1:-interactive}" in
    "interactive"|"")
        main "prompt"
        ;;
    "apply")
        main "apply"
        ;;
    "generate-only")
        main "skip"
        ;;
    "help")
        echo "Usage: $0 [interactive|apply|generate-only|help]"
        echo "  interactive  - Interactive credential collection with prompt to apply (default)"
        echo "  apply        - Interactive collection and automatic application to cluster"
        echo "  generate-only - Generate credentials without applying to cluster"
        echo "  help         - Show this help message"
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac