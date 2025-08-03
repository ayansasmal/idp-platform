#!/bin/bash

# AWS Cognito Authentication Setup Script for IDP Platform
# This script sets up complete AWS Cognito OAuth/OIDC integration

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is required but not installed"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot access Kubernetes cluster"
        exit 1
    fi
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Create Cognito User Pool
create_cognito_user_pool() {
    print_status "Creating Cognito User Pool..."
    
    # Create user pool
    USER_POOL_ID=$(aws cognito-idp create-user-pool \
        --pool-name "idp-platform-users" \
        --policies '{"PasswordPolicy":{"MinimumLength":8,"RequireUppercase":true,"RequireLowercase":true,"RequireNumbers":true,"RequireSymbols":false}}' \
        --auto-verified-attributes email \
        --username-attributes email \
        --email-configuration 'SourceArn=arn:aws:ses:us-west-2:123456789012:identity/noreply@yourdomain.com,EmailSendingAccount=DEVELOPER' \
        --admin-create-user-config '{"AllowAdminCreateUserOnly":false}' \
        --user-pool-tags 'Environment=production,Project=idp-platform' \
        --query 'UserPool.Id' \
        --output text)
    
    print_success "User Pool created: $USER_POOL_ID"
    
    # Create user pool domain
    DOMAIN_NAME="idp-platform-auth-$(date +%s)"
    aws cognito-idp create-user-pool-domain \
        --domain "$DOMAIN_NAME" \
        --user-pool-id "$USER_POOL_ID"
    
    print_success "User Pool domain created: $DOMAIN_NAME"
    
    # Create user pool client
    CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id "$USER_POOL_ID" \
        --client-name "idp-platform-client" \
        --generate-secret \
        --callback-urls "https://backstage.idp.local/api/auth/cognito/handler/frame" "https://auth.idp.local/oauth2/callback" \
        --logout-urls "https://backstage.idp.local" "https://auth.idp.local" \
        --allowed-o-auth-flows "code" \
        --allowed-o-auth-scopes "openid" "email" "profile" \
        --allowed-o-auth-flows-user-pool-client \
        --supported-identity-providers "COGNITO" \
        --explicit-auth-flows "ADMIN_NO_SRP_AUTH" "USER_PASSWORD_AUTH" \
        --query 'UserPoolClient.ClientId' \
        --output text)
    
    print_success "User Pool Client created: $CLIENT_ID"
    
    # Get client secret
    CLIENT_SECRET=$(aws cognito-idp describe-user-pool-client \
        --user-pool-id "$USER_POOL_ID" \
        --client-id "$CLIENT_ID" \
        --query 'UserPoolClient.ClientSecret' \
        --output text)
    
    # Export variables for later use
    export COGNITO_USER_POOL_ID="$USER_POOL_ID"
    export COGNITO_CLIENT_ID="$CLIENT_ID"
    export COGNITO_CLIENT_SECRET="$CLIENT_SECRET"
    export COGNITO_DOMAIN="$DOMAIN_NAME.auth.us-west-2.amazoncognito.com"
    export AWS_REGION="us-west-2"
    
    print_success "Cognito configuration completed"
}

# Update Kubernetes secrets with Cognito configuration
update_k8s_secrets() {
    print_status "Updating Kubernetes secrets with Cognito configuration..."
    
    # Create authentication namespace if it doesn't exist
    kubectl create namespace authentication --dry-run=client -o yaml | kubectl apply -f -
    
    # Update cognito-config secret
    kubectl create secret generic cognito-config \
        --namespace=authentication \
        --from-literal=user-pool-id="$COGNITO_USER_POOL_ID" \
        --from-literal=client-id="$COGNITO_CLIENT_ID" \
        --from-literal=client-secret="$COGNITO_CLIENT_SECRET" \
        --from-literal=region="$AWS_REGION" \
        --from-literal=domain="$COGNITO_DOMAIN" \
        --from-literal=issuer-url="https://cognito-idp.$AWS_REGION.amazonaws.com/$COGNITO_USER_POOL_ID" \
        --from-literal=jwks-uri="https://cognito-idp.$AWS_REGION.amazonaws.com/$COGNITO_USER_POOL_ID/.well-known/jwks.json" \
        --from-literal=callback-url="https://backstage.idp.local/api/auth/cognito/handler/frame" \
        --from-literal=logout-url="https://backstage.idp.local" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Update Backstage secrets
    kubectl create namespace backstage --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create secret generic backstage-secrets \
        --namespace=backstage \
        --from-literal=COGNITO_CLIENT_ID="$COGNITO_CLIENT_ID" \
        --from-literal=COGNITO_CLIENT_SECRET="$COGNITO_CLIENT_SECRET" \
        --from-literal=COGNITO_USER_POOL_ID="$COGNITO_USER_POOL_ID" \
        --from-literal=POSTGRES_HOST="postgresql.database.svc.cluster.local" \
        --from-literal=POSTGRES_PORT="5432" \
        --from-literal=POSTGRES_USER="backstage" \
        --from-literal=POSTGRES_PASSWORD="backstage-password" \
        --from-literal=POSTGRES_DB="backstage" \
        --from-literal=GITHUB_TOKEN="your-github-token" \
        --from-literal=ARGOCD_USERNAME="admin" \
        --from-literal=ARGOCD_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)" \
        --from-literal=BACKEND_SECRET="$(openssl rand -base64 32)" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Kubernetes secrets updated"
}

# Update configuration files with actual Cognito values
update_config_files() {
    print_status "Updating configuration files with Cognito values..."
    
    # Update cognito-setup.yaml
    sed -i.bak "s/us-west-2_XXXXXXXXX/$COGNITO_USER_POOL_ID/g" infrastructure/authentication/cognito-setup.yaml
    sed -i.bak "s/your-cognito-client-id/$COGNITO_CLIENT_ID/g" infrastructure/authentication/cognito-setup.yaml
    sed -i.bak "s/your-cognito-client-secret/$COGNITO_CLIENT_SECRET/g" infrastructure/authentication/cognito-setup.yaml
    sed -i.bak "s/your-idp-auth\.auth\.us-west-2\.amazoncognito\.com/$COGNITO_DOMAIN/g" infrastructure/authentication/cognito-setup.yaml
    
    # Update istio-auth-policies.yaml
    sed -i.bak "s/us-west-2_XXXXXXXXX/$COGNITO_USER_POOL_ID/g" infrastructure/authentication/istio-auth-policies.yaml
    sed -i.bak "s/your-cognito-client-id/$COGNITO_CLIENT_ID/g" infrastructure/authentication/istio-auth-policies.yaml
    
    # Update backstage-auth-config.yaml
    sed -i.bak "s/us-west-2_XXXXXXXXX/$COGNITO_USER_POOL_ID/g" infrastructure/authentication/backstage-auth-config.yaml
    sed -i.bak "s/your-cognito-client-id/$COGNITO_CLIENT_ID/g" infrastructure/authentication/backstage-auth-config.yaml
    sed -i.bak "s/your-cognito-client-secret/$COGNITO_CLIENT_SECRET/g" infrastructure/authentication/backstage-auth-config.yaml
    
    # Clean up backup files
    find infrastructure/authentication -name "*.bak" -delete
    
    print_success "Configuration files updated"
}

# Deploy authentication infrastructure
deploy_auth_infrastructure() {
    print_status "Deploying authentication infrastructure..."
    
    # Apply authentication manifests
    kubectl apply -f infrastructure/authentication/cognito-setup.yaml
    kubectl apply -f infrastructure/authentication/istio-auth-policies.yaml
    kubectl apply -f infrastructure/authentication/backstage-auth-config.yaml
    
    # Wait for deployments to be ready
    print_status "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/oauth2-proxy -n authentication
    kubectl wait --for=condition=available --timeout=300s deployment/redis -n authentication
    
    print_success "Authentication infrastructure deployed"
}

# Create initial admin user
create_admin_user() {
    print_status "Creating initial admin user..."
    
    read -p "Enter admin email: " ADMIN_EMAIL
    read -s -p "Enter admin password: " ADMIN_PASSWORD
    echo
    
    # Create admin user
    aws cognito-idp admin-create-user \
        --user-pool-id "$COGNITO_USER_POOL_ID" \
        --username "$ADMIN_EMAIL" \
        --user-attributes Name=email,Value="$ADMIN_EMAIL" Name=email_verified,Value=true \
        --temporary-password "$ADMIN_PASSWORD" \
        --message-action SUPPRESS
    
    # Set permanent password
    aws cognito-idp admin-set-user-password \
        --user-pool-id "$COGNITO_USER_POOL_ID" \
        --username "$ADMIN_EMAIL" \
        --password "$ADMIN_PASSWORD" \
        --permanent
    
    print_success "Admin user created: $ADMIN_EMAIL"
}

# Validate authentication setup
validate_setup() {
    print_status "Validating authentication setup..."
    
    # Check if pods are running
    if kubectl get pods -n authentication | grep -E "(Running|Ready)"; then
        print_success "Authentication pods are running"
    else
        print_error "Some authentication pods are not running"
        return 1
    fi
    
    # Check OAuth2 proxy health
    if kubectl exec -n authentication deployment/oauth2-proxy -- curl -f http://localhost:4180/ping &> /dev/null; then
        print_success "OAuth2 proxy is healthy"
    else
        print_warning "OAuth2 proxy health check failed"
    fi
    
    # Check Cognito configuration
    if aws cognito-idp describe-user-pool --user-pool-id "$COGNITO_USER_POOL_ID" &> /dev/null; then
        print_success "Cognito User Pool is accessible"
    else
        print_error "Cognito User Pool is not accessible"
        return 1
    fi
    
    print_success "Authentication setup validation completed"
}

# Display setup summary
display_summary() {
    echo
    echo "=================================="
    echo "AWS Cognito Authentication Setup Complete"
    echo "=================================="
    echo
    echo "Cognito Configuration:"
    echo "  User Pool ID: $COGNITO_USER_POOL_ID"
    echo "  Client ID: $COGNITO_CLIENT_ID"
    echo "  Domain: $COGNITO_DOMAIN"
    echo "  Region: $AWS_REGION"
    echo
    echo "Access URLs:"
    echo "  Auth Gateway: https://auth.idp.local"
    echo "  Backstage: https://backstage.idp.local"
    echo "  ArgoCD: https://argocd.idp.local"
    echo "  Grafana: https://grafana.idp.local"
    echo
    echo "Next Steps:"
    echo "1. Configure DNS to point *.idp.local to your ingress"
    echo "2. Test authentication by accessing https://backstage.idp.local"
    echo "3. Configure additional users in Cognito User Pool"
    echo "4. Set up group-based authorization policies"
    echo
}

# Main execution
main() {
    print_status "Starting AWS Cognito Authentication Setup"
    
    check_prerequisites
    create_cognito_user_pool
    update_k8s_secrets
    update_config_files
    deploy_auth_infrastructure
    create_admin_user
    validate_setup
    display_summary
    
    print_success "AWS Cognito authentication setup completed successfully!"
}

# Check if running directly or being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi