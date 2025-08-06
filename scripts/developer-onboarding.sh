#!/bin/bash

# IDP Platform Developer Onboarding Automation
# Streamlined developer setup with AWS Cognito integration and namespace provisioning

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

print_header() {
    echo -e "\\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $(printf "%-60s" "$1") ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\\n"
}

print_status() {
    echo -e "${PURPLE}[ONBOARD]${NC} $1"
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

# Load platform configuration
load_config() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        print_error "Credentials file not found. Run './scripts/credential-manager.sh' first."
        exit 1
    fi
    
    # Load configuration values (simplified YAML parsing)
    COGNITO_ENABLED=$(grep -A 5 "cognito_integration:" "$CREDENTIALS_FILE" | grep "enabled:" | cut -d':' -f2 | xargs)
    DEV_NAMESPACE_PREFIX=$(grep -A 10 "developer_access:" "$CREDENTIALS_FILE" | grep "namespace_prefix:" | cut -d':' -f2 | xargs)
    
    if [ "$COGNITO_ENABLED" = "true" ]; then
        COGNITO_USER_POOL_ID=$(grep -A 10 "cognito_integration:" "$CREDENTIALS_FILE" | grep "user_pool_id:" | cut -d':' -f2 | xargs)
        COGNITO_REGION=$(grep -A 10 "cognito_integration:" "$CREDENTIALS_FILE" | grep "region:" | cut -d':' -f2 | xargs)
    fi
}

# Validate prerequisites
check_prerequisites() {
    local errors=0
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is required but not installed"
        ((errors++))
    fi
    
    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Kubernetes cluster not accessible"
        ((errors++))
    fi
    
    # Check AWS CLI if Cognito is enabled
    if [ "$COGNITO_ENABLED" = "true" ] && ! command -v aws &> /dev/null; then
        print_warning "AWS CLI not found. Cognito user creation will be skipped."
        print_status "Install AWS CLI for full Cognito integration: https://aws.amazon.com/cli/"
    fi
    
    return $errors
}

# Create Cognito user
create_cognito_user() {
    local username="$1"
    local email="$2"
    local temp_password="$3"
    local user_groups="$4"
    
    if [ "$COGNITO_ENABLED" != "true" ] || ! command -v aws &> /dev/null; then
        print_warning "Skipping Cognito user creation (not configured or AWS CLI unavailable)"
        return 0
    fi
    
    print_status "Creating user in AWS Cognito User Pool..."
    
    # Create user
    if aws cognito-idp admin-create-user \\
        --user-pool-id "$COGNITO_USER_POOL_ID" \\
        --username "$username" \\
        --user-attributes Name=email,Value="$email" Name=email_verified,Value=true \\
        --temporary-password "$temp_password" \\
        --message-action SUPPRESS \\
        --region "$COGNITO_REGION" &> /dev/null; then
        
        print_success "Cognito user created: $username"
        
        # Add user to groups
        if [ -n "$user_groups" ]; then
            IFS=',' read -ra GROUPS <<< "$user_groups"
            for group in "${GROUPS[@]}"; do
                group=$(echo "$group" | xargs)  # trim whitespace
                if aws cognito-idp admin-add-user-to-group \\
                    --user-pool-id "$COGNITO_USER_POOL_ID" \\
                    --username "$username" \\
                    --group-name "$group" \\
                    --region "$COGNITO_REGION" &> /dev/null; then
                    print_success "Added user to group: $group"
                else
                    print_warning "Failed to add user to group: $group (group may not exist)"
                fi
            done
        fi
        
        return 0
    else
        print_error "Failed to create Cognito user"
        return 1
    fi
}

# Create Kubernetes namespace for developer
create_developer_namespace() {
    local username="$1"
    local namespace="${DEV_NAMESPACE_PREFIX:-dev}-$username"
    
    print_status "Creating developer namespace: $namespace"
    
    # Create namespace
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
  labels:
    app.kubernetes.io/managed-by: idp-platform
    idp.platform/developer: $username
    idp.platform/namespace-type: developer
    istio-injection: enabled
  annotations:
    idp.platform/created-by: developer-onboarding
    idp.platform/created-at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    print_success "Developer namespace created: $namespace"
    
    return 0
}

# Create RBAC resources for developer
create_developer_rbac() {
    local username="$1"
    local namespace="${DEV_NAMESPACE_PREFIX:-dev}-$username"
    
    print_status "Creating RBAC resources for developer: $username"
    
    # Create Role for namespace access
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $namespace
  name: developer-$username
  labels:
    app.kubernetes.io/managed-by: idp-platform
    idp.platform/developer: $username
rules:
- apiGroups: [""]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["apps"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["networking.k8s.io"]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["platform.idp"]
  resources: ["webapplications"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-$username-binding
  namespace: $namespace
  labels:
    app.kubernetes.io/managed-by: idp-platform
    idp.platform/developer: $username
subjects:
- kind: User
  name: $username
  apiGroup: rbac.authorization.k8s.io
- kind: User
  name: $username@idp.local
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer-$username
  apiGroup: rbac.authorization.k8s.io
EOF
    
    # Create ClusterRoleBinding for limited cluster access
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: developer-$username-cluster-access
  labels:
    app.kubernetes.io/managed-by: idp-platform
    idp.platform/developer: $username
subjects:
- kind: User
  name: $username
  apiGroup: rbac.authorization.k8s.io
- kind: User
  name: $username@idp.local
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
EOF
    
    print_success "RBAC resources created for developer: $username"
    
    return 0
}

# Create Backstage user entity
create_backstage_entity() {
    local username="$1"
    local email="$2"
    local full_name="$3"
    local namespace="${DEV_NAMESPACE_PREFIX:-dev}-$username"
    
    print_status "Creating Backstage user entity for: $username"
    
    # Create user entity YAML
    cat > "/tmp/backstage-user-$username.yaml" <<EOF
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: $username
  namespace: default
  labels:
    idp.platform/developer: $username
    idp.platform/onboarded: "true"
  annotations:
    idp.platform/created-by: developer-onboarding
    idp.platform/created-at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
    idp.platform/namespace: $namespace
spec:
  profile:
    displayName: $full_name
    email: $email
    picture: https://gravatar.com/avatar/$(echo -n "$email" | md5sum | cut -d' ' -f1)?d=identicon
  memberOf:
    - developers
    - namespace-$namespace-users
---
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: namespace-$namespace-users
  namespace: default
  labels:
    idp.platform/namespace: $namespace
    idp.platform/developer: $username
spec:
  type: team
  profile:
    displayName: $namespace Users
    description: Users with access to $namespace namespace
  children: []
  members:
    - $username
EOF
    
    # Apply to cluster (Backstage will discover it)
    if kubectl apply -f "/tmp/backstage-user-$username.yaml"; then
        print_success "Backstage user entity created: $username"
        rm -f "/tmp/backstage-user-$username.yaml"
    else
        print_error "Failed to create Backstage user entity"
        return 1
    fi
    
    return 0
}

# Create resource quotas for developer namespace
create_resource_quotas() {
    local username="$1"
    local namespace="${DEV_NAMESPACE_PREFIX:-dev}-$username"
    
    print_status "Creating resource quotas for namespace: $namespace"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: developer-quota
  namespace: $namespace
  labels:
    app.kubernetes.io/managed-by: idp-platform
    idp.platform/developer: $username
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "10"
    persistentvolumeclaims: "5"
    services: "5"
    secrets: "10"
    configmaps: "10"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: developer-limits
  namespace: $namespace
  labels:
    app.kubernetes.io/managed-by: idp-platform
    idp.platform/developer: $username
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
EOF
    
    print_success "Resource quotas created for namespace: $namespace"
    
    return 0
}

# Generate developer welcome information
generate_welcome_info() {
    local username="$1"
    local email="$2"
    local temp_password="$3"
    local namespace="${DEV_NAMESPACE_PREFIX:-dev}-$username"
    
    print_header "Developer Onboarding Complete"
    
    echo -e "${GREEN}🎉 Welcome to the IDP Platform, $username!${NC}\\n"
    
    echo -e "${BLUE}📊 Your Development Environment:${NC}"
    echo -e "  ${GREEN}•${NC} Username: ${CYAN}$username${NC}"
    echo -e "  ${GREEN}•${NC} Email: ${CYAN}$email${NC}"
    echo -e "  ${GREEN}•${NC} Kubernetes Namespace: ${CYAN}$namespace${NC}"
    echo -e "  ${GREEN}•${NC} Backstage Profile: ${CYAN}Created${NC}"
    
    if [ "$COGNITO_ENABLED" = "true" ] && [ -n "$temp_password" ]; then
        echo -e "\\n${BLUE}🔐 Authentication:${NC}"
        echo -e "  ${GREEN}•${NC} AWS Cognito: ${CYAN}Enabled${NC}"
        echo -e "  ${GREEN}•${NC} Temporary Password: ${YELLOW}$temp_password${NC}"
        echo -e "  ${RED}⚠️${NC}  You will be required to change your password on first login"
    fi
    
    echo -e "\\n${BLUE}🌐 Platform Access:${NC}"
    echo -e "  ${GREEN}•${NC} Backstage Portal: ${YELLOW}http://localhost:3000${NC}"
    echo -e "  ${GREEN}•${NC} ArgoCD GitOps: ${YELLOW}http://localhost:8080${NC}"
    echo -e "  ${GREEN}•${NC} Grafana Monitoring: ${YELLOW}http://localhost:3001${NC}"
    
    echo -e "\\n${BLUE}🛠️ Development Resources:${NC}"
    echo -e "  ${GREEN}•${NC} CPU Quota: ${CYAN}2 cores (request) / 4 cores (limit)${NC}"
    echo -e "  ${GREEN}•${NC} Memory Quota: ${CYAN}4Gi (request) / 8Gi (limit)${NC}"
    echo -e "  ${GREEN}•${NC} Max Pods: ${CYAN}10${NC}"
    echo -e "  ${GREEN}•${NC} Max Services: ${CYAN}5${NC}"
    
    echo -e "\\n${BLUE}🚀 Next Steps:${NC}"
    echo -e "  ${GREEN}1.${NC} Login to Backstage at http://localhost:3000"
    if [ "$COGNITO_ENABLED" = "true" ]; then
        echo -e "  ${GREEN}2.${NC} Change your temporary password when prompted"
        echo -e "  ${GREEN}3.${NC} Complete your user profile in Backstage"
        echo -e "  ${GREEN}4.${NC} Explore the software catalog and create your first component"
    else
        echo -e "  ${GREEN}2.${NC} Complete your user profile in Backstage"
        echo -e "  ${GREEN}3.${NC} Explore the software catalog and create your first component"
    fi
    
    echo -e "\\n${BLUE}📚 Documentation:${NC}"
    echo -e "  ${GREEN}•${NC} Developer Guide: ${YELLOW}docs/tutorials/getting-started.md${NC}"
    echo -e "  ${GREEN}•${NC} Platform API: ${YELLOW}docs/api/platform-crds.md${NC}"
    echo -e "  ${GREEN}•${NC} CI/CD Workflows: ${YELLOW}docs/tutorials/argo-workflows-ci-cd.md${NC}"
    
    echo -e "\\n${GREEN}Happy coding! 🎯${NC}\\n"
}

# Main onboarding function
onboard_developer() {
    local username="$1"
    local email="$2"
    local full_name="$3"
    local user_groups="$4"
    local temp_password="$5"
    
    print_header "Developer Onboarding: $username"
    
    # Generate temporary password if not provided
    if [ -z "$temp_password" ]; then
        temp_password=$(openssl rand -base64 12 | tr -d "=+/")
        print_status "Generated temporary password: $temp_password"
    fi
    
    # Step 1: Create Cognito user (if enabled)
    if [ "$COGNITO_ENABLED" = "true" ]; then
        create_cognito_user "$username" "$email" "$temp_password" "$user_groups"
    fi
    
    # Step 2: Create Kubernetes namespace
    create_developer_namespace "$username"
    
    # Step 3: Create RBAC resources
    create_developer_rbac "$username"
    
    # Step 4: Create resource quotas
    create_resource_quotas "$username"
    
    # Step 5: Create Backstage user entity
    create_backstage_entity "$username" "$email" "$full_name"
    
    # Step 6: Generate welcome information
    generate_welcome_info "$username" "$email" "$temp_password"
    
    return 0
}

# Interactive developer onboarding
interactive_onboarding() {
    print_header "Interactive Developer Onboarding"
    
    echo -e "${BLUE}Collect new developer information...${NC}\\n"
    
    # Collect developer information
    read -p "Developer username (lowercase, no spaces): " username
    read -p "Developer email address: " email
    read -p "Developer full name: " full_name
    
    if [ "$COGNITO_ENABLED" = "true" ]; then
        read -p "Cognito groups (comma-separated) [developers]: " user_groups
        user_groups="${user_groups:-developers}"
        
        local temp_password
        read -p "Temporary password (leave empty to generate): " temp_password
    else
        user_groups="developers"
        temp_password=""
    fi
    
    # Validate input
    if [ -z "$username" ] || [ -z "$email" ] || [ -z "$full_name" ]; then
        print_error "Username, email, and full name are required"
        exit 1
    fi
    
    # Confirm onboarding
    echo ""
    print_status "Developer onboarding summary:"
    echo -e "  • Username: $username"
    echo -e "  • Email: $email"
    echo -e "  • Full Name: $full_name"
    echo -e "  • Groups: $user_groups"
    echo -e "  • Cognito: $([ "$COGNITO_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")"
    
    echo ""
    local confirm
    read -p "Proceed with developer onboarding? [Y/n]: " confirm
    confirm="${confirm:-Y}"
    
    if [[ "$confirm" =~ ^[Yy] ]]; then
        onboard_developer "$username" "$email" "$full_name" "$user_groups" "$temp_password"
    else
        print_status "Developer onboarding cancelled"
        exit 0
    fi
}

# Batch onboarding from file
batch_onboarding() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        print_error "Batch file not found: $file"
        exit 1
    fi
    
    print_header "Batch Developer Onboarding"
    print_status "Processing batch file: $file"
    
    local count=0
    while IFS=',' read -r username email full_name user_groups temp_password; do
        # Skip header line and empty lines
        if [ "$username" = "username" ] || [ -z "$username" ]; then
            continue
        fi
        
        ((count++))
        echo ""
        print_status "Onboarding developer $count: $username"
        
        if onboard_developer "$username" "$email" "$full_name" "$user_groups" "$temp_password"; then
            print_success "Developer $username onboarded successfully"
        else
            print_error "Failed to onboard developer: $username"
        fi
    done < "$file"
    
    print_success "Batch onboarding completed. Processed $count developers."
}

# Remove/offboard developer
offboard_developer() {
    local username="$1"
    local namespace="${DEV_NAMESPACE_PREFIX:-dev}-$username"
    
    print_header "Developer Offboarding: $username"
    
    local confirm
    read -p "Are you sure you want to offboard developer $username? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_status "Offboarding cancelled"
        return 0
    fi
    
    print_status "Removing developer resources..."
    
    # Remove Cognito user
    if [ "$COGNITO_ENABLED" = "true" ] && command -v aws &> /dev/null; then
        if aws cognito-idp admin-delete-user \\
            --user-pool-id "$COGNITO_USER_POOL_ID" \\
            --username "$username" \\
            --region "$COGNITO_REGION" &> /dev/null; then
            print_success "Removed Cognito user: $username"
        else
            print_warning "Failed to remove Cognito user (may not exist)"
        fi
    fi
    
    # Remove Kubernetes resources
    kubectl delete namespace "$namespace" --ignore-not-found=true
    kubectl delete clusterrolebinding "developer-$username-cluster-access" --ignore-not-found=true
    kubectl delete -f - <<EOF || true
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: $username
  namespace: default
EOF
    
    print_success "Developer $username offboarded successfully"
}

# Main script
main() {
    local command="${1:-interactive}"
    
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              IDP Platform Developer Onboarding              ║"
    echo "║                                                              ║"
    echo "║  👥 Streamlined developer setup and access management       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Load configuration
    load_config
    
    # Check prerequisites
    if ! check_prerequisites; then
        print_error "Prerequisites not met"
        exit 1
    fi
    
    case "$command" in
        "interactive"|"")
            interactive_onboarding
            ;;
        "batch")
            if [ -z "$2" ]; then
                print_error "Batch file required. Usage: $0 batch <file.csv>"
                exit 1
            fi
            batch_onboarding "$2"
            ;;
        "offboard")
            if [ -z "$2" ]; then
                print_error "Username required. Usage: $0 offboard <username>"
                exit 1
            fi
            offboard_developer "$2"
            ;;
        "help")
            echo "Usage: $0 [interactive|batch <file>|offboard <user>|help]"
            echo ""
            echo "Commands:"
            echo "  interactive  - Interactive developer onboarding (default)"
            echo "  batch <file> - Batch onboarding from CSV file"
            echo "  offboard <user> - Remove developer and their resources"
            echo "  help         - Show this help message"
            echo ""
            echo "CSV format for batch onboarding:"
            echo "  username,email,full_name,groups,temp_password"
            echo "  john.doe,john@company.com,John Doe,developers,"
            ;;
        *)
            print_error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"