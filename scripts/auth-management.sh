#!/bin/bash

# IDP Authentication Management Script
# Consolidated script for managing AWS Cognito authentication and RBAC personas
# Combines functionality from setup-cognito-auth.sh and setup-cognito-personas.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
AWS_REGION="${AWS_REGION:-us-east-1}"
USER_POOL_NAME="${COGNITO_USER_POOL_NAME:-idp-user-pool}"
CLIENT_NAME="${COGNITO_CLIENT_NAME:-idp-backstage-client}"
TEMP_PASSWORD="TempPassword123!"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Usage information
usage() {
    cat << EOF
IDP Authentication Management Script

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    setup-cognito           Set up AWS Cognito User Pool and Client
    create-personas         Create predefined user personas and groups
    setup-full             Complete setup (Cognito + personas)
    status                 Show authentication status
    cleanup                Clean up authentication resources
    test-auth              Test authentication with sample users

OPTIONS:
    --localstack           Use LocalStack for local development (default)
    --aws                  Use real AWS (requires AWS credentials)
    --user-pool-name NAME  Custom user pool name (default: idp-user-pool)
    --region REGION        AWS region (default: us-east-1)
    --help                 Show this help message

EXAMPLES:
    $0 setup-full                    # Complete setup with LocalStack
    $0 setup-cognito --aws          # Setup Cognito in real AWS
    $0 create-personas              # Create personas in existing pool
    $0 status                       # Check authentication status

EOF
}

# Check prerequisites
check_prerequisites() {
    local errors=0
    
    # Check required tools
    for tool in kubectl awslocal; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
            ((errors++))
        fi
    done
    
    return $errors
}

# Check if LocalStack is running
check_localstack() {
    if ! curl -s "$LOCALSTACK_ENDPOINT/health" > /dev/null; then
        error "LocalStack is not running at $LOCALSTACK_ENDPOINT"
        error "Please start LocalStack first"
        return 1
    fi
    log "LocalStack is running and accessible"
    return 0
}

# Setup User Pool
setup_user_pool() {
    log "Setting up AWS Cognito User Pool..."
    
    # Check if user pool exists
    USER_POOL_ID=$(awslocal cognito-idp list-user-pools --max-results 60 --region $AWS_REGION \
        --query "UserPools[?Name=='$USER_POOL_NAME'].Id" --output text 2>/dev/null || echo "")
    
    if [[ -z "$USER_POOL_ID" || "$USER_POOL_ID" == "None" ]]; then
        info "Creating new User Pool: $USER_POOL_NAME"
        
        USER_POOL_ID=$(awslocal cognito-idp create-user-pool \
            --pool-name "$USER_POOL_NAME" \
            --region $AWS_REGION \
            --policies '{
                "PasswordPolicy": {
                    "MinimumLength": 8,
                    "RequireUppercase": true,
                    "RequireLowercase": true,
                    "RequireNumbers": true,
                    "RequireSymbols": false,
                    "TemporaryPasswordValidityDays": 7
                }
            }' \
            --auto-verified-attributes email \
            --username-attributes email \
            --schema '[
                {
                    "Name": "email",
                    "AttributeDataType": "String",
                    "Required": true,
                    "Mutable": true
                },
                {
                    "Name": "given_name",
                    "AttributeDataType": "String",
                    "Required": false,
                    "Mutable": true
                },
                {
                    "Name": "family_name",
                    "AttributeDataType": "String",
                    "Required": false,
                    "Mutable": true
                }
            ]' \
            --query 'UserPool.Id' --output text)
        
        log "Created User Pool with ID: $USER_POOL_ID"
    else
        log "Using existing User Pool with ID: $USER_POOL_ID"
    fi
    
    export USER_POOL_ID
}

# Setup User Pool Client
setup_user_pool_client() {
    log "Setting up User Pool Client..."
    
    CLIENT_ID=$(awslocal cognito-idp list-user-pool-clients \
        --user-pool-id "$USER_POOL_ID" \
        --region $AWS_REGION \
        --query "UserPoolClients[?ClientName=='$CLIENT_NAME'].ClientId" --output text 2>/dev/null || echo "")
    
    if [[ -z "$CLIENT_ID" || "$CLIENT_ID" == "None" ]]; then
        info "Creating new User Pool Client: $CLIENT_NAME"
        
        CLIENT_ID=$(awslocal cognito-idp create-user-pool-client \
            --user-pool-id "$USER_POOL_ID" \
            --client-name "$CLIENT_NAME" \
            --region $AWS_REGION \
            --generate-secret \
            --supported-identity-providers COGNITO \
            --callback-urls "http://localhost:3000/api/auth/cognito/handler/frame,http://localhost:7007/api/auth/cognito/handler/frame" \
            --logout-urls "http://localhost:3000,http://localhost:7007" \
            --allowed-o-auth-flows "authorization_code" \
            --allowed-o-auth-scopes "openid" "email" "profile" \
            --allowed-o-auth-flows-user-pool-client \
            --explicit-auth-flows "ADMIN_NO_SRP_AUTH" "ALLOW_USER_PASSWORD_AUTH" "ALLOW_REFRESH_TOKEN_AUTH" \
            --query 'UserPoolClient.ClientId' --output text)
        
        log "Created User Pool Client with ID: $CLIENT_ID"
    else
        log "Using existing User Pool Client with ID: $CLIENT_ID"
    fi
    
    export CLIENT_ID
    
    # Get client secret
    CLIENT_SECRET=$(awslocal cognito-idp describe-user-pool-client \
        --user-pool-id "$USER_POOL_ID" \
        --client-id "$CLIENT_ID" \
        --region $AWS_REGION \
        --query 'UserPoolClient.ClientSecret' --output text)
    
    export CLIENT_SECRET
}

# Setup User Pool Domain
setup_domain() {
    log "Setting up User Pool Domain..."
    
    DOMAIN_NAME="idp-auth"
    
    if awslocal cognito-idp describe-user-pool-domain \
        --domain "$DOMAIN_NAME" \
        --region $AWS_REGION >/dev/null 2>&1; then
        info "Domain '$DOMAIN_NAME' already exists"
    else
        awslocal cognito-idp create-user-pool-domain \
            --domain "$DOMAIN_NAME" \
            --user-pool-id "$USER_POOL_ID" \
            --region $AWS_REGION >/dev/null
        
        log "Created domain: $DOMAIN_NAME"
    fi
    
    export DOMAIN_NAME
}

# Create IDP Groups (Personas)
create_groups() {
    log "Creating IDP persona groups..."
    
    declare -A GROUPS=(
        ["idp-platform-admin"]="Full platform administration capabilities"
        ["idp-platform-operator"]="Platform operations and monitoring access"
        ["idp-security-admin"]="Security policies and compliance management"
        ["idp-senior-developer"]="Full development capabilities with mentoring permissions"
        ["idp-developer"]="Standard development access to services and resources"
        ["idp-junior-developer"]="Limited development access with approval workflows"
        ["idp-product-manager"]="Product oversight and business metrics access"
        ["idp-business-stakeholder"]="Read-only access to business metrics and reports"
        ["idp-service-account"]="Automated systems and CI/CD service access"
    )
    
    for group_name in "${!GROUPS[@]}"; do
        description="${GROUPS[$group_name]}"
        
        if awslocal cognito-idp get-group \
            --group-name "$group_name" \
            --user-pool-id "$USER_POOL_ID" \
            --region $AWS_REGION >/dev/null 2>&1; then
            info "Group '$group_name' already exists"
        else
            awslocal cognito-idp create-group \
                --group-name "$group_name" \
                --user-pool-id "$USER_POOL_ID" \
                --description "$description" \
                --region $AWS_REGION >/dev/null
            
            log "Created group: $group_name"
        fi
    done
}

# Create predefined test users
create_users() {
    log "Creating predefined test users..."
    
    declare -A USERS=(
        ["admin@idp.local"]="idp-platform-admin,idp-security-admin"
        ["platform-ops@idp.local"]="idp-platform-operator"
        ["lead-dev@idp.local"]="idp-senior-developer"
        ["developer@idp.local"]="idp-developer"
        ["junior-dev@idp.local"]="idp-junior-developer"
        ["pm@idp.local"]="idp-product-manager"
        ["stakeholder@idp.local"]="idp-business-stakeholder"
        ["service-account@idp.local"]="idp-service-account"
    )
    
    for username in "${!USERS[@]}"; do
        groups="${USERS[$username]}"
        
        # Extract name parts for attributes
        local_part=$(echo "$username" | cut -d'@' -f1)
        given_name=$(echo "$local_part" | cut -d'-' -f1 | sed 's/.*/\u&/')
        family_name="User"
        
        if [[ "$local_part" == *"-"* ]]; then
            given_name=$(echo "$local_part" | sed 's/-/ /g' | sed 's/.*/\u&/' | sed 's/ \(.\)/\u\1/g')
        fi
        
        # Check if user exists
        if awslocal cognito-idp admin-get-user \
            --user-pool-id "$USER_POOL_ID" \
            --username "$username" \
            --region $AWS_REGION >/dev/null 2>&1; then
            info "User '$username' already exists"
        else
            # Create user
            awslocal cognito-idp admin-create-user \
                --user-pool-id "$USER_POOL_ID" \
                --username "$username" \
                --user-attributes \
                    Name=email,Value="$username" \
                    Name=given_name,Value="$given_name" \
                    Name=family_name,Value="$family_name" \
                    Name=email_verified,Value=true \
                --temporary-password "$TEMP_PASSWORD" \
                --message-action SUPPRESS \
                --region $AWS_REGION >/dev/null
            
            # Set permanent password
            awslocal cognito-idp admin-set-user-password \
                --user-pool-id "$USER_POOL_ID" \
                --username "$username" \
                --password "$TEMP_PASSWORD" \
                --permanent \
                --region $AWS_REGION >/dev/null
            
            log "Created user: $username"
        fi
        
        # Add user to groups
        IFS=',' read -ra GROUP_LIST <<< "$groups"
        for group in "${GROUP_LIST[@]}"; do
            if ! awslocal cognito-idp admin-list-groups-for-user \
                --user-pool-id "$USER_POOL_ID" \
                --username "$username" \
                --region $AWS_REGION \
                --query "Groups[?GroupName=='$group']" --output text | grep -q "$group"; then
                
                awslocal cognito-idp admin-add-user-to-group \
                    --user-pool-id "$USER_POOL_ID" \
                    --username "$username" \
                    --group-name "$group" \
                    --region $AWS_REGION >/dev/null
                
                info "Added $username to group: $group"
            fi
        done
    done
}

# Output configuration
output_config() {
    log "Authentication setup complete!"
    echo ""
    info "Environment Variables (add to your .env file):"
    echo "export AUTH_COGNITO_CLIENT_ID=\"${CLIENT_ID}\""
    echo "export AUTH_COGNITO_CLIENT_SECRET=\"${CLIENT_SECRET}\""
    echo "export AUTH_COGNITO_USER_POOL_ID=\"${USER_POOL_ID}\""
    echo "export AUTH_COGNITO_ISSUER=\"https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}\""
    echo "export AUTH_COGNITO_DOMAIN=\"https://${DOMAIN_NAME}.auth.${AWS_REGION}.localhost.localstack.cloud:4566\""
    echo ""
    
    info "Test Users (password: ${TEMP_PASSWORD}):"
    declare -A USER_DESCRIPTIONS=(
        ["admin@idp.local"]="Platform Administrator"
        ["platform-ops@idp.local"]="Platform Operator"
        ["lead-dev@idp.local"]="Senior Developer"
        ["developer@idp.local"]="Developer"
        ["junior-dev@idp.local"]="Junior Developer"
        ["pm@idp.local"]="Product Manager"
        ["stakeholder@idp.local"]="Business Stakeholder"
        ["service-account@idp.local"]="Service Account"
    )
    
    for username in "${!USER_DESCRIPTIONS[@]}"; do
        description="${USER_DESCRIPTIONS[$username]}"
        echo "  $username - $description"
    done
}

# Show authentication status
show_status() {
    log "Checking IDP Authentication Status..."
    
    if ! check_localstack; then
        error "LocalStack not available - cannot check status"
        return 1
    fi
    
    # Check user pool
    if USER_POOL_ID=$(awslocal cognito-idp list-user-pools --max-results 60 --region $AWS_REGION \
        --query "UserPools[?Name=='$USER_POOL_NAME'].Id" --output text 2>/dev/null) && \
       [[ -n "$USER_POOL_ID" && "$USER_POOL_ID" != "None" ]]; then
        info "✅ User Pool exists: $USER_POOL_ID"
        
        # Count users
        user_count=$(awslocal cognito-idp list-users --user-pool-id "$USER_POOL_ID" --region $AWS_REGION \
            --query 'Users | length(@)' --output text 2>/dev/null || echo "0")
        info "👥 Users: $user_count"
        
        # Count groups
        group_count=$(awslocal cognito-idp list-groups --user-pool-id "$USER_POOL_ID" --region $AWS_REGION \
            --query 'Groups | length(@)' --output text 2>/dev/null || echo "0")
        info "🏷️  Groups: $group_count"
    else
        warn "❌ User Pool not found"
    fi
}

# Cleanup authentication resources
cleanup_auth() {
    warn "This will delete all authentication resources. Are you sure? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log "Cleaning up authentication resources..."
        
        if USER_POOL_ID=$(awslocal cognito-idp list-user-pools --max-results 60 --region $AWS_REGION \
            --query "UserPools[?Name=='$USER_POOL_NAME'].Id" --output text 2>/dev/null) && \
           [[ -n "$USER_POOL_ID" && "$USER_POOL_ID" != "None" ]]; then
            
            awslocal cognito-idp delete-user-pool --user-pool-id "$USER_POOL_ID" --region $AWS_REGION
            log "Deleted User Pool: $USER_POOL_ID"
        fi
    else
        info "Cleanup cancelled"
    fi
}

# Test authentication
test_auth() {
    log "Testing authentication configuration..."
    
    if ! check_localstack; then
        return 1
    fi
    
    # Test if user pool exists and is accessible
    if USER_POOL_ID=$(awslocal cognito-idp list-user-pools --max-results 60 --region $AWS_REGION \
        --query "UserPools[?Name=='$USER_POOL_NAME'].Id" --output text 2>/dev/null) && \
       [[ -n "$USER_POOL_ID" && "$USER_POOL_ID" != "None" ]]; then
        
        log "✅ User Pool accessible: $USER_POOL_ID"
        
        # Test authentication with a sample user
        if awslocal cognito-idp admin-get-user \
            --user-pool-id "$USER_POOL_ID" \
            --username "admin@idp.local" \
            --region $AWS_REGION >/dev/null 2>&1; then
            log "✅ Sample user 'admin@idp.local' exists and is accessible"
        else
            warn "❌ Sample user not found - run 'create-personas' first"
        fi
    else
        error "❌ User Pool not found - run 'setup-cognito' first"
        return 1
    fi
}

# Main command handler
main() {
    case "${1:-}" in
        setup-cognito)
            log "Setting up AWS Cognito User Pool and Client..."
            check_prerequisites || exit 1
            check_localstack || exit 1
            setup_user_pool
            setup_user_pool_client
            setup_domain
            output_config
            ;;
        create-personas)
            log "Creating predefined user personas and groups..."
            check_prerequisites || exit 1
            check_localstack || exit 1
            setup_user_pool  # Ensure pool exists
            create_groups
            create_users
            output_config
            ;;
        setup-full)
            log "Complete authentication setup (Cognito + personas)..."
            check_prerequisites || exit 1
            check_localstack || exit 1
            setup_user_pool
            setup_user_pool_client
            setup_domain
            create_groups
            create_users
            output_config
            ;;
        status)
            show_status
            ;;
        cleanup)
            cleanup_auth
            ;;
        test-auth)
            test_auth
            ;;
        --help|help)
            usage
            ;;
        *)
            error "Unknown command: ${1:-}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"