#!/bin/bash

# IDP Infrastructure Setup Script
# Consolidated script for setting up core infrastructure components
# Combines LocalStack setup and OPA policy management

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"

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
IDP Infrastructure Setup Script

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    setup-localstack        Set up LocalStack for local AWS services
    setup-opa              Set up Open Policy Agent for authorization
    setup-infrastructure   Complete infrastructure setup (LocalStack + OPA)
    status                 Show infrastructure status
    cleanup                Clean up infrastructure resources
    test-connectivity      Test connectivity to services

OPTIONS:
    --localstack-port PORT  LocalStack port (default: 4566)
    --skip-docker          Skip Docker container checks
    --help                 Show this help message

EXAMPLES:
    $0 setup-infrastructure     # Complete infrastructure setup
    $0 status                   # Check infrastructure status
    $0 test-connectivity        # Test service connectivity

EOF
}

# Check prerequisites
check_prerequisites() {
    local errors=0
    
    # Check required tools
    for tool in kubectl docker; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
            ((errors++))
        fi
    done
    
    # Check Kubernetes cluster
    if ! kubectl cluster-info &> /dev/null; then
        error "Kubernetes cluster not accessible"
        ((errors++))
    fi
    
    return $errors
}

# Setup LocalStack
setup_localstack() {
    log "Setting up LocalStack for local AWS services..."
    
    # Check if LocalStack is already running
    if curl -s "$LOCALSTACK_ENDPOINT/health" > /dev/null 2>&1; then
        info "LocalStack already running at $LOCALSTACK_ENDPOINT"
        return 0
    fi
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        error "Docker is not running. Please start Docker first."
        return 1
    fi
    
    # Create LocalStack configuration
    create_localstack_config
    
    # Start LocalStack using docker-compose if available, otherwise docker run
    if [ -f "$ROOT_DIR/docker-compose.yml" ] || [ -f "$ROOT_DIR/docker-compose.yaml" ]; then
        info "Starting LocalStack using docker-compose..."
        cd "$ROOT_DIR"
        docker-compose up -d localstack || docker compose up -d localstack
    else
        info "Starting LocalStack using Docker..."
        docker run -d \
            --name localstack-idp \
            -p 4566:4566 \
            -e SERVICES=cognito,ecr,rds,secretsmanager,s3 \
            -e DEBUG=1 \
            -e DOCKER_HOST=unix:///var/run/docker.sock \
            -e HOST_TMP_FOLDER="$(pwd)/tmp/localstack" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$(pwd)/tmp/localstack:/tmp/localstack" \
            localstack/localstack:latest
    fi
    
    # Wait for LocalStack to be ready
    info "Waiting for LocalStack to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "$LOCALSTACK_ENDPOINT/health" > /dev/null 2>&1; then
            log "✅ LocalStack is ready at $LOCALSTACK_ENDPOINT"
            break
        fi
        
        sleep 2
        ((attempt++))
        
        if [ $attempt -eq $max_attempts ]; then
            error "LocalStack failed to start within timeout"
            return 1
        fi
    done
    
    # Configure LocalStack services
    configure_localstack_services
}

# Create LocalStack configuration
create_localstack_config() {
    info "Creating LocalStack configuration..."
    
    mkdir -p "$ROOT_DIR/tmp/localstack"
    
    # Create LocalStack init script if it doesn't exist
    if [ ! -f "$ROOT_DIR/tmp/localstack/init-localstack.sh" ]; then
        cat > "$ROOT_DIR/tmp/localstack/init-localstack.sh" << 'EOF'
#!/bin/bash

# LocalStack initialization script for IDP platform
echo "Initializing LocalStack services for IDP..."

# Wait for services to be ready
sleep 10

# Create S3 buckets for Argo Workflows
awslocal s3 mb s3://argo-artifacts --region us-east-1 || true
awslocal s3 mb s3://idp-storage --region us-east-1 || true

echo "LocalStack initialization complete"
EOF
        chmod +x "$ROOT_DIR/tmp/localstack/init-localstack.sh"
    fi
}

# Configure LocalStack services
configure_localstack_services() {
    log "Configuring LocalStack services..."
    
    # Create S3 buckets for IDP
    info "Creating S3 buckets..."
    awslocal s3 mb s3://argo-artifacts --region us-east-1 2>/dev/null || true
    awslocal s3 mb s3://idp-storage --region us-east-1 2>/dev/null || true
    awslocal s3 mb s3://idp-backups --region us-east-1 2>/dev/null || true
    
    # Create ECR repository
    info "Creating ECR repository..."
    awslocal ecr create-repository \
        --repository-name idp/backstage-app \
        --region us-east-1 2>/dev/null || true
    
    log "LocalStack services configured successfully"
}

# Setup OPA (Open Policy Agent)
setup_opa() {
    log "Setting up Open Policy Agent for authorization..."
    
    # Create OPA namespace
    kubectl create namespace opa-system --dry-run=client -o yaml | kubectl apply -f - || true
    
    # Apply OPA configuration if files exist
    if [ -f "$ROOT_DIR/infrastructure/authorization/opa-setup.yaml" ]; then
        info "Applying OPA setup configuration..."
        kubectl apply -f "$ROOT_DIR/infrastructure/authorization/opa-setup.yaml"
    else
        warn "OPA setup configuration not found, creating basic setup..."
        create_basic_opa_setup
    fi
    
    # Apply OPA policies
    if [ -d "$ROOT_DIR/infrastructure/authorization" ]; then
        info "Applying OPA policies..."
        for policy_file in "$ROOT_DIR/infrastructure/authorization"/*.yaml; do
            if [ -f "$policy_file" ] && [[ "$policy_file" != *"opa-setup.yaml" ]]; then
                kubectl apply -f "$policy_file" || warn "Failed to apply $policy_file"
            fi
        done
    fi
    
    log "OPA setup completed"
}

# Create basic OPA setup if files don't exist
create_basic_opa_setup() {
    info "Creating basic OPA configuration..."
    
    # Create basic OPA deployment
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: opa
  namespace: opa-system
  labels:
    app: opa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: opa
  template:
    metadata:
      labels:
        app: opa
    spec:
      containers:
      - name: opa
        image: openpolicyagent/opa:latest-envoy
        ports:
        - containerPort: 8181
        args:
          - "run"
          - "--server"
          - "--addr=0.0.0.0:8181"
          - "--diagnostic-addr=0.0.0.0:8282"
          - "--set=plugins.envoy_ext_authz_grpc.addr=:9191"
          - "--set=plugins.envoy_ext_authz_grpc.query=data.envoy.authz.allow"
          - "--set=decision_logs.console=true"
          - "/policies"
        volumeMounts:
        - name: opa-policies
          mountPath: /policies
      volumes:
      - name: opa-policies
        configMap:
          name: opa-policies
---
apiVersion: v1
kind: Service
metadata:
  name: opa
  namespace: opa-system
  labels:
    app: opa
spec:
  selector:
    app: opa
  ports:
  - name: http
    port: 8181
    targetPort: 8181
  - name: grpc
    port: 9191
    targetPort: 9191
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: opa-policies
  namespace: opa-system
data:
  policy.rego: |
    package envoy.authz

    import rego.v1

    default allow := false

    allow if {
        input.attributes.request.http.method == "GET"
        input.attributes.request.http.path == "/health"
    }

    allow if {
        input.attributes.request.http.headers["authorization"]
        input.attributes.request.http.path != "/admin"
    }
EOF
}

# Show infrastructure status
show_status() {
    log "Checking IDP Infrastructure Status..."
    
    # Check LocalStack
    if curl -s "$LOCALSTACK_ENDPOINT/health" > /dev/null 2>&1; then
        info "✅ LocalStack is running at $LOCALSTACK_ENDPOINT"
        
        # Check LocalStack services
        local services
        services=$(curl -s "$LOCALSTACK_ENDPOINT/health" | jq -r '.services // empty' 2>/dev/null || echo "")
        if [ -n "$services" ]; then
            info "📦 LocalStack services: $services"
        fi
    else
        warn "❌ LocalStack is not accessible"
    fi
    
    # Check OPA
    if kubectl get namespace opa-system > /dev/null 2>&1; then
        info "✅ OPA namespace exists"
        
        # Check OPA deployment
        if kubectl get deployment opa -n opa-system > /dev/null 2>&1; then
            local ready_replicas
            ready_replicas=$(kubectl get deployment opa -n opa-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            info "🛡️  OPA deployment: $ready_replicas/1 replicas ready"
        else
            warn "❌ OPA deployment not found"
        fi
    else
        warn "❌ OPA namespace not found"
    fi
    
    # Check Kubernetes cluster
    if kubectl cluster-info > /dev/null 2>&1; then
        info "✅ Kubernetes cluster accessible"
    else
        error "❌ Kubernetes cluster not accessible"
    fi
}

# Test connectivity to services
test_connectivity() {
    log "Testing connectivity to infrastructure services..."
    
    local tests_passed=0
    local total_tests=0
    
    # Test LocalStack
    info "Testing LocalStack connectivity..."
    ((total_tests++))
    if curl -s "$LOCALSTACK_ENDPOINT/health" > /dev/null; then
        log "✅ LocalStack health check passed"
        ((tests_passed++))
    else
        error "❌ LocalStack health check failed"
    fi
    
    # Test S3 service
    info "Testing LocalStack S3 service..."
    ((total_tests++))
    if awslocal s3 ls > /dev/null 2>&1; then
        log "✅ LocalStack S3 service accessible"
        ((tests_passed++))
    else
        error "❌ LocalStack S3 service failed"
    fi
    
    # Test OPA service (if deployed)
    if kubectl get service opa -n opa-system > /dev/null 2>&1; then
        info "Testing OPA service..."
        ((total_tests++))
        if kubectl port-forward service/opa 8181:8181 -n opa-system --timeout=5s > /dev/null 2>&1 & then
            local pf_pid=$!
            sleep 2
            if curl -s http://localhost:8181/health > /dev/null 2>&1; then
                log "✅ OPA service accessible"
                ((tests_passed++))
            else
                error "❌ OPA service not accessible"
            fi
            kill $pf_pid 2>/dev/null || true
        else
            error "❌ Could not port-forward to OPA service"
        fi
    fi
    
    log "Connectivity tests: $tests_passed/$total_tests passed"
    
    if [ $tests_passed -eq $total_tests ]; then
        log "🎉 All infrastructure services are accessible"
        return 0
    else
        error "⚠️  Some infrastructure services have connectivity issues"
        return 1
    fi
}

# Cleanup infrastructure
cleanup_infrastructure() {
    warn "This will stop LocalStack and remove OPA components. Are you sure? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log "Cleaning up infrastructure..."
        
        # Stop LocalStack
        info "Stopping LocalStack..."
        docker stop localstack-idp 2>/dev/null || true
        docker rm localstack-idp 2>/dev/null || true
        
        # Remove OPA
        info "Removing OPA components..."
        kubectl delete namespace opa-system --ignore-not-found=true
        
        log "Infrastructure cleanup completed"
    else
        info "Cleanup cancelled"
    fi
}

# Main command handler
main() {
    case "${1:-}" in
        setup-localstack)
            log "Setting up LocalStack..."
            check_prerequisites || exit 1
            setup_localstack
            ;;
        setup-opa)
            log "Setting up Open Policy Agent..."
            check_prerequisites || exit 1
            setup_opa
            ;;
        setup-infrastructure)
            log "Setting up complete infrastructure (LocalStack + OPA)..."
            check_prerequisites || exit 1
            setup_localstack
            setup_opa
            ;;
        status)
            show_status
            ;;
        test-connectivity)
            test_connectivity
            ;;
        cleanup)
            cleanup_infrastructure
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