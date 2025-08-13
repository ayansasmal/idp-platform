#!/bin/bash

# IDP Platform Master Script
# One unified script to rule them all - with async execution support
# Supports background tasks to prevent blocking IDP-agent interactions

set -euo pipefail

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

# Configuration defaults
BACKSTAGE_REPO_URL="https://github.com/ayansasmal/idp-backstage-app.git"
BACKSTAGE_BRANCH="main"
IMAGE_NAME="idp/backstage-app"
IMAGE_TAG="latest"
VERSIONS_FILE="$ROOT_DIR/platform-versions.yaml"
CHARTS_DIR="$ROOT_DIR/charts"

# Async execution support
ASYNC_MODE=false
JSON_OUTPUT=false
TASK_MANAGER="$SCRIPT_DIR/async-task-manager.sh"
WITH_WINDMILL=false

# Load configuration if available
load_config() {
    if [ -f "$CONFIG_DIR/idp-config.yaml" ]; then
        # Simple yaml parsing for key values
        while IFS=':' read -r key value; do
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            case "$key" in
                "name") export IDP_PLATFORM_NAME="$value" ;;
                "namespace") export IDP_PLATFORM_NAMESPACE="$value" ;;
                "domain") export IDP_PLATFORM_DOMAIN="$value" ;;
            esac
        done < <(grep -E '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*:' "$CONFIG_DIR/idp-config.yaml" | head -20)
    fi
}

print_header() {
    if [ "$JSON_OUTPUT" = "false" ]; then
        echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC} $(printf "%-60s" "$1") ${BLUE}║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    fi
}

print_status() {
    if [ "$JSON_OUTPUT" = "false" ]; then
        echo -e "${PURPLE}[INFO]${NC} $1"
    fi
}

print_success() {
    if [ "$JSON_OUTPUT" = "false" ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

print_error() {
    if [ "$JSON_OUTPUT" = "false" ]; then
        echo -e "${RED}[ERROR]${NC} $1"
    fi
}

print_warning() {
    if [ "$JSON_OUTPUT" = "false" ]; then
        echo -e "${YELLOW}[WARNING]${NC} $1"
    fi
}

# JSON output functions
output_json() {
    local status="$1"
    local message="$2"
    local data="${3:-{}}"
    
    echo "{\"status\": \"$status\", \"message\": \"$message\", \"data\": $data, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
}

output_json_success() {
    output_json "success" "$1" "${2:-{}}"
}

output_json_error() {
    output_json "error" "$1" "${2:-{}}"
}

output_json_info() {
    output_json "info" "$1" "${2:-{}}"
}

# Async execution wrapper
execute_async() {
    local task_name="$1"
    shift
    local command="$@"
    
    if [ "$ASYNC_MODE" = "true" ] && [ -x "$TASK_MANAGER" ]; then
        # Execute in background using task manager
        local result
        result=$("$TASK_MANAGER" run "$task_name" "$command" 2>&1)
        
        if [ "$JSON_OUTPUT" = "true" ]; then
            echo "$result"
        else
            print_status "Task '$task_name' started in background"
            echo "$result" | grep -E "(task_id|pid)" || true
        fi
        return 0
    else
        # Execute synchronously
        eval "$command"
    fi
}

# Check if running in async mode
is_async_mode() {
    [ "$ASYNC_MODE" = "true" ]
}

# Check prerequisites
check_prerequisites() {
    local errors=0
    
    # Check required tools
    for tool in kubectl docker; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is required but not installed"
            ((errors++))
        fi
    done
    
    # Check Kubernetes cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Kubernetes cluster not accessible"
        ((errors++))
    fi
    
    return $errors
}

# Parse command line arguments
parse_arguments() {
    PARSED_ARGS=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --async)
                ASYNC_MODE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --sync)
                ASYNC_MODE=false
                shift
                ;;
            --with-windmill)
                WITH_WINDMILL=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                PARSED_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# Usage information
show_usage() {
    cat << EOF
IDP Platform Master Script

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    setup                    Setup IDP platform
    setup-windmill           Setup Windmill workflow orchestration
    start                    Start platform services
    stop                     Stop platform services
    restart                  Restart platform services
    status                   Show platform status
    build-backstage          Build Backstage application
    build-unleash            Build and deploy Unleash OSS feature flag service
    task-status TASK_NAME    Check async task status
    task-list                List all async tasks
    task-cancel TASK_NAME    Cancel running task
    task-logs TASK_NAME      Show task logs

OPTIONS:
    --async                  Execute long-running tasks in background
    --json                   Output results in JSON format
    --sync                   Force synchronous execution (default)
    --with-windmill          Include Windmill setup in platform setup
    --help                   Show this help message

EXAMPLES:
    $0 setup --async --json              # Setup in background with JSON output
    $0 setup --with-windmill             # Setup platform including Windmill
    $0 setup-windmill                    # Setup Windmill workflow orchestration
    $0 status --json                     # Get status in JSON format
    $0 task-status platform-setup        # Check async task status
    $0 build-backstage --async           # Build Backstage in background
    $0 build-unleash                     # Build and deploy Unleash OSS

EOF
}

# Setup IDP platform (sync version)
setup_platform_sync() {
    print_header "Setting up IDP Platform"
    
    print_status "Checking prerequisites..."
    if ! check_prerequisites; then
        print_error "Prerequisites not met. Please install required tools."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
    
    # Setup LocalStack for development (if script exists)
    if [ -f "$SCRIPT_DIR/setup-external-localstack.sh" ]; then
        print_status "Setting up LocalStack..."
        "$SCRIPT_DIR/setup-external-localstack.sh"
    else
        print_warning "LocalStack setup script not found, skipping..."
    fi
    
    # Setup infrastructure (LocalStack + OPA)
    if [ -f "$SCRIPT_DIR/infrastructure-setup.sh" ]; then
        print_status "Setting up infrastructure (LocalStack + OPA)..."
        "$SCRIPT_DIR/infrastructure-setup.sh" setup-infrastructure || {
            print_warning "Failed to setup infrastructure, but continuing..."
        }
        print_success "Infrastructure setup completed"
    fi

    # Setup authentication personas (if LocalStack is available)
    if [ -f "$SCRIPT_DIR/auth-management.sh" ] && curl -s http://localhost:4566/health > /dev/null 2>&1; then
        print_status "Setting up AWS Cognito personas and test users..."
        "$SCRIPT_DIR/auth-management.sh" setup-full || {
            print_warning "Failed to setup authentication, but continuing..."
        }
        print_success "Authentication setup completed"
    elif [ ! -f "$SCRIPT_DIR/auth-management.sh" ]; then
        print_warning "Authentication management script not found, skipping..."
    else
        print_warning "LocalStack not available, skipping authentication setup..."
    fi
    
    # Install Istio service mesh first (required for platform)
    print_status "Installing Istio service mesh..."
    if [ -d "$ROOT_DIR/istio-1.26.3" ]; then
        "$ROOT_DIR/istio-1.26.3/bin/istioctl" install --set values.defaultRevision=default -y
        print_success "Istio service mesh installed"
        
        # Install observability addons (Prometheus, Grafana, Jaeger, Kiali)
        print_status "Installing Istio observability addons..."
        kubectl apply -f "$ROOT_DIR/istio-1.26.3/samples/addons/" || {
            print_warning "Some addons failed to install, but continuing..."
        }
        print_success "Istio observability addons installed"
    else
        print_error "Istio installation directory not found. Please ensure Istio 1.26.3 is available."
        return 1
    fi
    
    # Deploy ArgoCD
    print_status "Deploying ArgoCD..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    print_status "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s || {
        print_warning "ArgoCD deployment timeout, but continuing..."
    }
    
    # Note: Argo Workflows will be deployed via ArgoCD application (Helm chart)
    # Setup S3 artifacts for Argo Workflows (if script exists)
    if [ -f "$SCRIPT_DIR/setup-argo-artifacts.sh" ]; then
        print_status "Setting up Argo Workflows S3 artifacts..."
        "$SCRIPT_DIR/setup-argo-artifacts.sh" || print_warning "Failed to setup S3 artifacts"
    fi
    
    # Apply GitOps applications (if they exist)
    if [ -f "$ROOT_DIR/applications/argocd/argocd-apps.yaml" ]; then
        print_status "Applying GitOps applications..."
        kubectl apply -f "$ROOT_DIR/applications/argocd/argocd-apps.yaml" || {
            print_warning "Failed to apply GitOps applications, but continuing..."
        }
    else
        print_warning "GitOps applications not found, skipping..."
    fi
    
    # Deploy platform services (monitoring, backstage, etc.)
    if [ -f "$ROOT_DIR/applications/platform-services-apps.yaml" ]; then
        print_status "Deploying platform services (monitoring, backstage, workflows)..."
        kubectl apply -f "$ROOT_DIR/applications/platform-services-apps.yaml" || {
            print_warning "Failed to deploy platform services, but continuing..."
        }
        
        # Wait for Istio addons to be ready
        print_status "Waiting for observability services to be ready..."
        kubectl wait --for=condition=Available deployment/grafana -n istio-system --timeout=120s || print_warning "Grafana not ready"
        kubectl wait --for=condition=Available deployment/prometheus -n istio-system --timeout=120s || print_warning "Prometheus not ready"
        
        # Deploy Unleash OSS feature flag service
        print_status "Deploying Unleash OSS feature flag service..."
        if [ -f "$ROOT_DIR/applications/unleash/unleash-app.yaml" ]; then
            kubectl apply -f "$ROOT_DIR/applications/unleash/unleash-app.yaml" || {
                print_warning "Failed to deploy Unleash application, but continuing..."
            }
            print_success "Unleash ArgoCD application created"
        else
            print_warning "Unleash application manifest not found, skipping..."
        fi
        
        # Trigger sync of platform applications
        print_status "Syncing platform applications..."
        sleep 10  # Wait for applications to be created
        
        # Handle Argo Workflows deployment conflicts (common issue)
        print_status "Resolving potential Argo Workflows deployment conflicts..."
        # Remove any existing conflicting deployments that might have immutable fields
        kubectl delete deployment argo-workflows-server argo-workflows-workflow-controller -n argo-workflows --ignore-not-found=true
        kubectl delete configmap workflow-controller-configmap -n argo-workflows --ignore-not-found=true
        
        # Sync core applications first
        for app in monitoring-platform argocd-ui; do
            kubectl patch application $app -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge 2>/dev/null || true
        done
        
        # Force sync Argo Workflows with clean slate
        kubectl patch application argo-workflows -n argocd -p '{"spec":{"syncPolicy":null}}' --type merge 2>/dev/null || true
        kubectl patch application argo-workflows -n argocd -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{},"apply":{"force":true}}}}}' --type merge 2>/dev/null || true
        
        # Wait for Argo Workflows to be ready before deploying templates
        print_status "Waiting for Argo Workflows to be ready..."
        kubectl wait --for=condition=Available deployment/argo-workflows-server -n argo-workflows --timeout=120s || print_warning "Argo Workflows server not ready"
        
        # Deploy workflow templates using dedicated script (more reliable than ArgoCD app)
        if [ -f "$SCRIPT_DIR/deploy-workflow-templates.sh" ]; then
            "$SCRIPT_DIR/deploy-workflow-templates.sh" || print_warning "Some workflow templates failed to deploy"
        else
            print_warning "Workflow templates deployment script not found"
        fi
        
        # Sync remaining applications
        for app in backstage-platform; do
            kubectl patch application $app -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge 2>/dev/null || true
        done
    else
        print_warning "Platform services applications not found, skipping..."
    fi
    
    # Optional Windmill setup
    if [ "$WITH_WINDMILL" = "true" ]; then
        print_header "Setting up Windmill Orchestration"
        if [ -f "$SCRIPT_DIR/setup-windmill.sh" ]; then
            print_status "Setting up Windmill workflow orchestration..."
            "$SCRIPT_DIR/setup-windmill.sh" setup
            print_success "Windmill orchestration setup completed"
            print_status "Access Windmill at: http://localhost:8000"
        else
            print_error "Windmill setup script not found at $SCRIPT_DIR/setup-windmill.sh"
        fi
    fi
    
    print_success "Platform setup completed"
}

# Trigger Backstage build via IDP workflows
build_backstage_actual() {
    print_header "Building Backstage via IDP Workflows"
    
    # Check if Argo Workflows is ready
    if ! kubectl get namespace argo-workflows &> /dev/null; then
        print_error "Argo Workflows not found. Run 'setup' first."
        exit 1
    fi
    
    print_status "Submitting Backstage build workflow..."
    
    # Submit the stable Backstage build workflow
    kubectl apply -f - << EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: backstage-build-
  namespace: argo-workflows
spec:
  entrypoint: build-backstage
  serviceAccountName: argo-workflows-workflow-controller
  arguments:
    parameters:
    - name: repo-url
      value: "${BACKSTAGE_REPO_URL}"
    - name: branch
      value: "${BACKSTAGE_BRANCH}"
    - name: image-name
      value: "${IMAGE_NAME}"
    - name: image-tag
      value: "${IMAGE_TAG}"

  templates:
  - name: build-backstage
    dag:
      tasks:
      - name: clone-repo
        template: git-clone
      - name: build-image
        template: build-and-push
        dependencies: [clone-repo]
      - name: verify-build
        template: verify-success
        dependencies: [build-image]
      - name: trigger-deployment
        template: trigger-argocd-sync
        dependencies: [verify-build]

  - name: git-clone
    container:
      image: alpine/git:latest
      command: [sh, -c]
      args:
        - |
          echo "🚀 Starting Backstage build workflow"
          echo "Cloning repository: {{workflow.parameters.repo-url}}"
          git clone {{workflow.parameters.repo-url}} /workspace
          cd /workspace
          git checkout {{workflow.parameters.branch}}
          echo "✅ Repository cloned successfully"
      volumeMounts:
      - name: workspace
        mountPath: /workspace
    volumes:
    - name: workspace
      emptyDir: {}

  - name: build-and-push
    container:
      image: gcr.io/kaniko-project/executor:debug
      command: ["/kaniko/executor"]
      args:
        - "--dockerfile=/workspace/Dockerfile"
        - "--context=/workspace"
        - "--destination=000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566/{{workflow.parameters.image-name}}:{{workflow.parameters.image-tag}}"
        - "--insecure"
        - "--skip-tls-verify"
        - "--insecure-registry=000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566"
        - "--cache=false"
      volumeMounts:
      - name: workspace
        mountPath: /workspace
      env:
      - name: AWS_ACCESS_KEY_ID
        value: "test"
      - name: AWS_SECRET_ACCESS_KEY
        value: "test"
      - name: AWS_DEFAULT_REGION
        value: "us-east-1"
    volumes:
    - name: workspace
      emptyDir: {}

  - name: verify-success
    container:
      image: alpine:latest
      command: [sh, -c]
      args:
        - |
          echo "🎉 Backstage build completed successfully!"
          echo "📦 Image built: 000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566/{{workflow.parameters.image-name}}:{{workflow.parameters.image-tag}}"

  - name: trigger-argocd-sync
    container:
      image: bitnami/kubectl:latest
      command: [sh, -c]
      args:
        - |
          echo "🔄 Triggering ArgoCD sync for Backstage deployment..."
          kubectl patch application backstage-platform -n argocd -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge || echo "ArgoCD sync trigger failed"
          echo "✅ Deployment sync triggered"

  volumes:
  - name: workspace
    emptyDir: {}
EOF
    
    print_success "Backstage build workflow submitted"
    print_status "Monitor progress with: kubectl get workflows -n argo-workflows"
    print_status "View logs with: kubectl logs -n argo-workflows -l workflows.argoproj.io/workflow"
}

# Start services with intelligent discovery
start_services_actual() {
    print_header "Starting Platform Services"
    
    # Build and deploy Unleash if not already running
    if ! kubectl get deployment unleash -n unleash &>/dev/null || \
       [ "$(kubectl get pods -n unleash -l app=unleash --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)" -eq 0 ]; then
        print_status "Building and deploying Unleash OSS feature flags..."
        
        # Trigger Unleash build workflow (async)
        if kubectl get workflowtemplate unleash-build-deploy -n argo-workflows &>/dev/null; then
            print_status "Submitting Unleash build workflow..."
            if kubectl create -f - << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: unleash-build-
  namespace: argo-workflows
spec:
  workflowTemplateRef:
    name: unleash-build-deploy
  arguments:
    parameters:
    - name: unleash-version
      value: "5.7.0"
    - name: image-tag
      value: "latest"
    - name: ecr-registry
      value: "000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566"
    - name: aws-region
      value: "us-east-1"
EOF
            then
                print_success "Unleash build workflow submitted"
            else
                print_warning "Unleash workflow submission failed, deploying static manifests instead"
            fi
            sleep 5  # Brief wait for workflow to start
        else
            print_warning "Unleash workflow template not found, using static deployment..."
        fi
        
        # Deploy static manifests as fallback or primary method
        print_status "Ensuring Unleash deployment via GitOps..."
        if [ -f "$ROOT_DIR/applications/unleash/unleash-deployment.yaml" ]; then
            kubectl apply -f "$ROOT_DIR/applications/unleash/unleash-deployment.yaml" &>/dev/null || true
            kubectl apply -f "$ROOT_DIR/applications/unleash/unleash-virtualservice.yaml" &>/dev/null || true
        fi
        
        print_success "Unleash deployment initiated"
    else
        print_status "Unleash already running, skipping build..."
    fi
    
    # Service port-forward configurations (using simple approach for sh compatibility)
    SERVICES_LIST="
argocd:argocd:argocd-server:8080:443
backstage:backstage:backstage:3000:80
workflows:argo-workflows:argo-workflows-server:4000:2746
grafana:istio-system:grafana:3001:3000
prometheus:istio-system:prometheus:9090:9090
jaeger:istio-system:tracing:16686:80
kiali:istio-system:kiali:20001:20001
monitoring:istio-system:monitoring-dashboard:3002:80
unleash:unleash:unleash:4243:4242
"
    
    local pids_file="$SCRIPT_DIR/.port-forward-pids"
    
    # Stop existing port forwards
    if [ -f "$pids_file" ]; then
        print_status "Stopping existing port forwards..."
        while read -r pid; do
            kill "$pid" 2>/dev/null || true
        done < "$pids_file"
        rm -f "$pids_file"
    fi
    
    print_status "Starting port forwards for available services..."
    
    echo "$SERVICES_LIST" | while IFS=':' read -r service_name namespace svc local_port remote_port; do
        # Skip empty lines
        [ -z "$service_name" ] && continue
        
        # Check if service exists
        if kubectl get namespace "$namespace" &> /dev/null && \
           kubectl get service "$svc" -n "$namespace" &> /dev/null; then
            
            print_status "Starting port-forward for $service_name ($namespace/$svc)"
            kubectl port-forward -n "$namespace" "svc/$svc" "$local_port:$remote_port" &
            echo $! >> "$pids_file"
            
            # Brief wait to establish connection
            sleep 2
            
            # Verify port is responding
            if curl -s --connect-timeout 2 "http://localhost:$local_port" &>/dev/null || \
               nc -z localhost "$local_port" 2>/dev/null; then
                print_success "$service_name ready on http://localhost:$local_port"
            else
                print_warning "$service_name port-forward started but not yet ready"
            fi
        else
            print_warning "$service_name not available (namespace: $namespace, service: $svc)"
        fi
    done
    
    print_header "Platform Services Started"
    echo -e "${GREEN}🎉 IDP Platform is running!${NC}\n"
    
    echo -e "${BLUE}🔗 Available Services:${NC}"
    echo -e "  • ArgoCD (GitOps):         ${YELLOW}https://localhost:8080${NC}"
    echo -e "  • Backstage (Portal):      ${YELLOW}http://localhost:3000${NC}"
    echo -e "  • Argo Workflows (CI/CD):  ${YELLOW}http://localhost:4000${NC}"
    echo -e "  • Grafana (Monitoring):    ${YELLOW}http://localhost:3001${NC}"
    echo -e "  • Prometheus (Metrics):    ${YELLOW}http://localhost:9090${NC}"
    echo -e "  • Jaeger (Tracing):        ${YELLOW}http://localhost:16686${NC}"
    echo -e "  • Kiali (Service Mesh):    ${YELLOW}http://localhost:20001${NC}"
    echo -e "  • Unleash (Feature Flags): ${YELLOW}http://localhost:4243${NC}"
    echo -e "  • Monitoring Dashboard:    ${YELLOW}http://localhost:3002${NC}\n"
    
    echo -e "${BLUE}🔐 Default Credentials:${NC}"
    echo -e "  • ArgoCD: admin / $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo 'admin')"
    echo -e "  • Grafana: admin / admin"
    echo -e "  • Unleash: admin / unleash4all\n"
    
    echo -e "${YELLOW}⚠️  Keep this terminal open to maintain services${NC}"
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop all services${NC}\n"
}

# Stop all services
stop_services() {
    print_header "Stopping Platform Services"
    
    local pids_file="$SCRIPT_DIR/.port-forward-pids"
    
    if [ -f "$pids_file" ]; then
        print_status "Stopping port forwards..."
        while read -r pid; do
            kill "$pid" 2>/dev/null && print_status "Stopped process $pid" || true
        done < "$pids_file"
        rm -f "$pids_file"
        print_success "All port forwards stopped"
    else
        print_warning "No active port forwards found"
    fi
}

# Check platform status
check_status() {
    print_header "Platform Status"
    
    echo -e "${BLUE}🔍 Checking Kubernetes resources...${NC}\n"
    
    # Check namespaces
    echo -e "${PURPLE}Namespaces:${NC}"
    kubectl get namespaces | grep -E "(argocd|backstage|argo-workflows|istio-system|unleash)" || echo "No platform namespaces found"
    echo ""
    
    # Check ArgoCD applications
    echo -e "${PURPLE}ArgoCD Applications:${NC}"
    kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD not found or no applications"
    echo ""
    
    # Check Workflows
    echo -e "${PURPLE}Argo Workflows:${NC}"
    kubectl get workflows -n argo-workflows 2>/dev/null | tail -5 || echo "No workflows found"
    echo ""
    
    # Check running pods
    echo -e "${PURPLE}Platform Pods:${NC}"
    for ns in argocd backstage argo-workflows istio-system unleash; do
        if kubectl get namespace "$ns" &> /dev/null; then
            echo -e "${CYAN}$ns:${NC}"
            kubectl get pods -n "$ns" | head -5 2>/dev/null || echo "  No pods found"
        fi
    done
}

# Show usage
show_usage() {
    echo -e "${BLUE}IDP Platform Manager${NC}\n"
    echo -e "${PURPLE}Usage:${NC} $0 <command> [options]\n"
    echo -e "${PURPLE}Platform Management Commands:${NC}"
    echo -e "  ${GREEN}setup${NC}           Set up the IDP platform (one-time)"
    echo -e "  ${GREEN}setup-windmill${NC}  Set up Windmill workflow orchestration ${CYAN}[NEW]${NC}"
    echo -e "  ${GREEN}start${NC}           Start platform services with port-forwards"
    echo -e "  ${GREEN}stop${NC}            Stop all platform services"
    echo -e "  ${GREEN}restart${NC}         Restart platform services"
    echo -e "  ${GREEN}status${NC} [comp]   Check platform status (optionally for specific component)"
    echo -e "  ${GREEN}config${NC}          Run configuration wizard"
    echo -e ""
    echo -e "${PURPLE}Application Management Commands:${NC}"
    echo -e "  ${GREEN}build-backstage${NC}     Build Backstage app using IDP workflows"
    echo -e "  ${GREEN}build-unleash${NC}       Build and deploy Unleash OSS feature flag service"
    echo -e "  ${GREEN}deploy-templates${NC}    Deploy/redeploy Argo Workflows templates"
    echo -e ""
    echo -e "${PURPLE}Credential Management Commands:${NC} ${CYAN}[NEW]${NC}"
    echo -e "  ${GREEN}credentials${NC} [setup|apply|generate]  Interactive credential setup and management"
    echo -e ""
    echo -e "${PURPLE}Version Management Commands:${NC}"
    echo -e "  ${GREEN}versions${NC} [comp]  List versions for all components or specific component"
    echo -e "  ${GREEN}update${NC} <comp> --version <ver> [--dry-run]  Update component to version"
    echo -e "  ${GREEN}rollback${NC} <comp> [--steps <n>]              Rollback component"
    echo -e ""
    echo -e "  ${GREEN}help${NC}            Show this help message\n"
    echo -e "${PURPLE}Examples:${NC}"
    echo -e "  $0 setup                                    # Initial platform setup"
    echo -e "  $0 setup --with-windmill                    # Setup platform including Windmill"
    echo -e "  $0 setup-windmill                           # Setup Windmill orchestration only"
    echo -e "  $0 credentials setup                        # Interactive credential configuration"
    echo -e "  $0 start                                    # Start all services"
    echo -e "  $0 versions                                 # List all component versions"
    echo -e "  $0 versions monitoring-stack                # List versions for monitoring stack"
    echo -e "  $0 update monitoring-stack --version 1.1.0 # Update monitoring to v1.1.0"
    echo -e "  $0 update istio-config --version 1.20.1 --dry-run  # Dry run update"
    echo -e "  $0 rollback monitoring-stack --steps 1     # Rollback monitoring 1 step"
    echo -e "  $0 status monitoring-stack                  # Check specific component status"
    echo -e "  $0 build-backstage                          # Build and deploy Backstage"
    echo -e "  $0 build-unleash                            # Build and deploy Unleash OSS"
    echo -e "  $0 deploy-templates                         # Deploy Argo Workflows templates\n"
}

# Cleanup function
cleanup() {
    print_status "Cleaning up..."
    stop_services
    exit 0
}

# Handle Ctrl+C gracefully
trap cleanup INT

# Versioning and rollback functions
get_component_info() {
    local component="$1"
    if ! command -v yq &> /dev/null; then
        # Fallback to basic grep parsing if yq not available
        grep -A 10 "$component:" "$VERSIONS_FILE" 2>/dev/null || return 1
    else
        yq eval ".spec.components.*.${component}" "$VERSIONS_FILE" 2>/dev/null || return 1
    fi
}

list_versions() {
    local component="${1:-}"
    
    print_header "Component Versions"
    
    if [ -n "$component" ]; then
        # Show specific component versions
        print_status "Versions for component: $component"
        local current available
        if command -v yq &> /dev/null; then
            current=$(yq eval ".spec.components.*.${component}.current" "$VERSIONS_FILE" 2>/dev/null)
            available=$(yq eval ".spec.components.*.${component}.available[]" "$VERSIONS_FILE" 2>/dev/null)
        else
            # Fallback parsing
            current=$(grep -A 5 "${component}:" "$VERSIONS_FILE" | grep "current:" | cut -d'"' -f2)
            available=$(grep -A 10 "${component}:" "$VERSIONS_FILE" | grep -A 5 "available:" | grep -E "^\s*-" | cut -d'"' -f2)
        fi
        
        echo -e "${BLUE}Current Version:${NC} ${GREEN}$current${NC}"
        echo -e "${BLUE}Available Versions:${NC}"
        echo "$available" | while read -r version; do
            [ "$version" = "$current" ] && marker="${GREEN}★${NC}" || marker=" "
            echo -e "  $marker ${CYAN}$version${NC}"
        done
    else
        # Show all components
        print_status "All platform component versions:"
        echo ""
        
        # Parse and display component versions
        if command -v yq &> /dev/null; then
            yq eval '.spec.components | keys | .[]' "$VERSIONS_FILE" 2>/dev/null | while read -r category; do
                echo -e "${PURPLE}$category:${NC}"
                yq eval ".spec.components.${category} | keys | .[]" "$VERSIONS_FILE" 2>/dev/null | while read -r comp; do
                    local current_ver=$(yq eval ".spec.components.${category}.${comp}.current" "$VERSIONS_FILE" 2>/dev/null)
                    echo -e "  ${CYAN}$comp${NC}: ${GREEN}$current_ver${NC}"
                done
                echo ""
            done
        else
            # Fallback display
            echo -e "${CYAN}Use 'yq' tool for detailed version information${NC}"
            echo -e "${YELLOW}Install with: pip install yq${NC}"
        fi
    fi
}

update_component() {
    local component="$1"
    local target_version="$2"
    local dry_run="${3:-false}"
    
    if [ -z "$component" ] || [ -z "$target_version" ]; then
        print_error "Usage: update <component> --version <version> [--dry-run]"
        return 1
    fi
    
    print_header "Updating Component: $component"
    
    # Check if component exists
    if ! get_component_info "$component" > /dev/null; then
        print_error "Component '$component' not found in platform versions"
        return 1
    fi
    
    # Get current version and available versions
    local current_version available_versions namespace chart_path
    if command -v yq &> /dev/null; then
        current_version=$(yq eval ".spec.components.*.${component}.current" "$VERSIONS_FILE" 2>/dev/null)
        available_versions=$(yq eval ".spec.components.*.${component}.available[]" "$VERSIONS_FILE" 2>/dev/null)
        namespace=$(yq eval ".spec.components.*.${component}.namespace" "$VERSIONS_FILE" 2>/dev/null)
        chart_path=$(yq eval ".spec.components.*.${component}.chart" "$VERSIONS_FILE" 2>/dev/null)
    else
        print_error "yq tool required for component updates. Install with: pip install yq"
        return 1
    fi
    
    print_status "Current version: $current_version"
    print_status "Target version: $target_version"
    
    # Validate target version is available
    if ! echo "$available_versions" | grep -q "^$target_version$"; then
        print_error "Version $target_version not available for $component"
        print_status "Available versions:"
        echo "$available_versions" | sed 's/^/  /'
        return 1
    fi
    
    if [ "$current_version" = "$target_version" ]; then
        print_warning "Component $component already at version $target_version"
        return 0
    fi
    
    if [ "$dry_run" = "true" ]; then
        print_status "DRY RUN: Would update $component from $current_version to $target_version"
        print_status "Namespace: $namespace"
        print_status "Chart path: $chart_path"
        return 0
    fi
    
    # Backup current state
    print_status "Creating backup of current state..."
    local backup_file="$CONFIG_DIR/backups/${component}-${current_version}-$(date +%Y%m%d_%H%M%S).yaml"
    mkdir -p "$CONFIG_DIR/backups"
    
    if kubectl get applications -n argocd "$component" -o yaml > "$backup_file" 2>/dev/null; then
        print_success "Backup created: $backup_file"
    else
        print_warning "Could not create ArgoCD application backup"
    fi
    
    # Update via ArgoCD application
    print_status "Updating ArgoCD application..."
    
    # Create temporary patch file
    local patch_file="/tmp/${component}-update.yaml"
    cat > "$patch_file" << EOF
spec:
  source:
    targetRevision: "$target_version"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF
    
    if kubectl patch application "$component" -n argocd --patch-file "$patch_file" --type merge; then
        print_success "ArgoCD application updated"
        
        # Trigger sync
        print_status "Triggering ArgoCD sync..."
        kubectl patch application "$component" -n argocd \
            -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge
        
        # Wait for sync to complete
        print_status "Waiting for sync to complete..."
        local timeout=300  # 5 minutes
        local elapsed=0
        
        while [ $elapsed -lt $timeout ]; do
            local sync_status=$(kubectl get application "$component" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
            local health_status=$(kubectl get application "$component" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
            
            if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
                print_success "Component $component successfully updated to $target_version"
                
                # Update versions file
                if command -v yq &> /dev/null; then
                    yq eval ".spec.components.*.${component}.current = \"$target_version\"" -i "$VERSIONS_FILE"
                    yq eval ".status.lastUpdate.component = \"$component\"" -i "$VERSIONS_FILE"
                    yq eval ".status.lastUpdate.version = \"$target_version\"" -i "$VERSIONS_FILE"
                    yq eval ".status.lastUpdate.timestamp = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" -i "$VERSIONS_FILE"
                    yq eval ".status.lastUpdate.status = \"success\"" -i "$VERSIONS_FILE"
                fi
                
                return 0
            fi
            
            sleep 5
            ((elapsed += 5))
            echo -n "."
        done
        
        echo ""
        print_error "Update timed out. Component may still be updating."
        print_status "Check status with: ./scripts/idp.sh status $component"
        return 1
        
    else
        print_error "Failed to update ArgoCD application"
        return 1
    fi
    
    rm -f "$patch_file"
}

rollback_component() {
    local component="$1"
    local steps="${2:-1}"
    
    if [ -z "$component" ]; then
        print_error "Usage: rollback <component> [--steps <n>]"
        return 1
    fi
    
    print_header "Rolling Back Component: $component"
    
    # Check if component exists
    if ! get_component_info "$component" > /dev/null; then
        print_error "Component '$component' not found in platform versions"
        return 1
    fi
    
    print_status "Rolling back $steps step(s)..."
    
    # Use ArgoCD rollback capability
    if kubectl get application "$component" -n argocd > /dev/null 2>&1; then
        print_status "Performing ArgoCD rollback..."
        
        # Get revision history
        local revisions=$(kubectl get application "$component" -n argocd -o jsonpath='{.status.history}')
        
        if [ -n "$revisions" ]; then
            # Trigger rollback via ArgoCD CLI if available, otherwise use manual approach
            if command -v argocd &> /dev/null; then
                argocd app rollback "$component" --revision $((-$steps)) || {
                    print_warning "ArgoCD CLI rollback failed, trying manual approach..."
                    kubectl patch application "$component" -n argocd \
                        -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge
                }
            else
                print_status "ArgoCD CLI not available, using kubectl approach..."
                kubectl patch application "$component" -n argocd \
                    -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge
            fi
            
            print_success "Rollback initiated for $component"
            print_status "Monitor progress with: kubectl get application $component -n argocd"
        else
            print_error "No revision history available for rollback"
            return 1
        fi
    else
        print_error "ArgoCD application '$component' not found"
        return 1
    fi
}

component_status() {
    local component="${1:-}"
    
    print_header "Component Status"
    
    if [ -n "$component" ]; then
        # Show specific component status
        print_status "Status for component: $component"
        
        if kubectl get application "$component" -n argocd > /dev/null 2>&1; then
            echo -e "${BLUE}ArgoCD Application:${NC}"
            kubectl get application "$component" -n argocd -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision"
            
            echo -e "\n${BLUE}Kubernetes Resources:${NC}"
            local namespace=$(yq eval ".spec.components.*.${component}.namespace" "$VERSIONS_FILE" 2>/dev/null)
            if [ -n "$namespace" ] && [ "$namespace" != "null" ]; then
                kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$component" 2>/dev/null || \
                    echo "No pods found for component $component in namespace $namespace"
            fi
        else
            print_warning "ArgoCD application '$component' not found"
        fi
    else
        # Show all components status
        print_status "All platform component status:"
        echo ""
        
        echo -e "${BLUE}ArgoCD Applications:${NC}"
        kubectl get applications -n argocd -o custom-columns="NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision" 2>/dev/null || \
            echo "ArgoCD not available or no applications found"
    fi
}

# Async wrapper functions  
setup_platform() {
    if is_async_mode; then
        execute_async "platform-setup" "$0 setup --sync"
    else
        setup_platform_sync
    fi
}

start_services_main() {
    if is_async_mode; then
        execute_async "platform-start" "$0 start --sync" 
    else
        start_services_actual
    fi
}

build_backstage_main() {
    if is_async_mode; then
        execute_async "backstage-build" "$0 build-backstage --sync"
    else
        build_backstage_actual
    fi
}

# Trigger Unleash build via IDP workflows
build_unleash_actual() {
    print_header "Building Unleash OSS via IDP Workflows"
    
    # Check if Argo Workflows is ready
    if ! kubectl get namespace argo-workflows &> /dev/null; then
        print_error "Argo Workflows not found. Run 'setup' first."
        exit 1
    fi
    
    print_status "Submitting Unleash build workflow..."
    
    # Submit the Unleash build workflow
    kubectl create -f - << EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: unleash-build-
  namespace: argo-workflows
spec:
  workflowTemplateRef:
    name: unleash-build-deploy
  arguments:
    parameters:
    - name: unleash-version
      value: "5.7.0"
    - name: image-tag
      value: "latest"
    - name: ecr-registry
      value: "000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566"
    - name: aws-region
      value: "us-east-1"
EOF
    
    if [ $? -eq 0 ]; then
        print_success "Unleash build workflow submitted successfully"
        print_status "Monitor progress: kubectl get workflows -n argo-workflows"
        print_status "View logs: argo logs -n argo-workflows @latest"
        print_status "Access Unleash after deployment: http://localhost:4243"
    else
        print_error "Failed to submit Unleash build workflow"
        exit 1
    fi
    
    if [ "$JSON_OUTPUT" = "true" ]; then
        output_json_success "Unleash build workflow submitted" "{\"namespace\": \"argo-workflows\", \"access_url\": \"http://localhost:4243\"}"
    fi
}

build_unleash_main() {
    if is_async_mode; then
        execute_async "unleash-build" "$0 build-unleash --sync"
    else
        build_unleash_actual
    fi
}

# Task management commands
handle_task_command() {
    local task_cmd="$1"
    local task_name="${2:-}"
    
    if [ ! -x "$TASK_MANAGER" ]; then
        if [ "$JSON_OUTPUT" = "true" ]; then
            output_json_error "Task manager not available"
        else
            print_error "Task manager not available at $TASK_MANAGER"
        fi
        exit 1
    fi
    
    case "$task_cmd" in
        "status")
            if [ -z "$task_name" ]; then
                if [ "$JSON_OUTPUT" = "true" ]; then
                    output_json_error "Task name required"
                else
                    print_error "Please specify task name"
                fi
                exit 1
            fi
            "$TASK_MANAGER" status "$task_name" $([ "$JSON_OUTPUT" = "true" ] && echo "--json")
            ;;
        "list") 
            "$TASK_MANAGER" list $([ "$JSON_OUTPUT" = "true" ] && echo "--json")
            ;;
        "cancel")
            if [ -z "$task_name" ]; then
                if [ "$JSON_OUTPUT" = "true" ]; then
                    output_json_error "Task name required"
                else
                    print_error "Please specify task name"
                fi
                exit 1
            fi
            "$TASK_MANAGER" cancel "$task_name"
            ;;
        "logs")
            if [ -z "$task_name" ]; then
                if [ "$JSON_OUTPUT" = "true" ]; then
                    output_json_error "Task name required"
                else
                    print_error "Please specify task name"
                fi
                exit 1
            fi
            "$TASK_MANAGER" logs "$task_name"
            ;;
        *)
            if [ "$JSON_OUTPUT" = "true" ]; then
                output_json_error "Unknown task command: $task_cmd"
            else
                print_error "Unknown task command: $task_cmd"
            fi
            exit 1
            ;;
    esac
}

# Load configuration and parse arguments
load_config
parse_arguments "$@"

# Main command processing
case "${PARSED_ARGS[0]:-help}" in
    "setup")
        setup_platform
        ;;
    "setup-windmill")
        "$SCRIPT_DIR/setup-windmill.sh" setup
        ;;
    "start")
        start_services_main
        # Keep running until interrupted
        while true; do
            sleep 10
        done
        ;;
    "stop")
        stop_services
        ;;
    "restart")
        stop_services
        sleep 2
        start_services_main
        ;;
    "status")
        if [ -n "${PARSED_ARGS[1]:-}" ]; then
            component_status "${PARSED_ARGS[1]}"
        else
            check_status
        fi
        ;;
    "build-backstage")
        build_backstage_main
        ;;
    "build-unleash")
        build_unleash_main
        ;;
    "deploy-templates")
        if [ -f "$SCRIPT_DIR/deploy-workflow-templates.sh" ]; then
            "$SCRIPT_DIR/deploy-workflow-templates.sh"
        else
            print_error "Workflow templates deployment script not found"
            exit 1
        fi
        ;;
    "config")
        "$SCRIPT_DIR/idp-setup-wizard.sh"
        ;;
    "credentials")
        case "${PARSED_ARGS[1]:-}" in
            "setup"|"")
                "$SCRIPT_DIR/credential-manager.sh" interactive
                ;;
            "apply")
                "$SCRIPT_DIR/credential-manager.sh" apply
                ;;
            "generate")
                "$SCRIPT_DIR/credential-manager.sh" generate-only
                ;;
            *)
                print_error "Usage: $0 credentials [setup|apply|generate]"
                exit 1
                ;;
        esac
        ;;
    "versions")
        case "${PARSED_ARGS[1]:-}" in
            "list")
                list_versions "${PARSED_ARGS[2]:-}"
                ;;
            *)
                list_versions "${PARSED_ARGS[1]:-}"
                ;;
        esac
        ;;
    "update")
        if [ "${PARSED_ARGS[2]:-}" = "--version" ] && [ -n "${PARSED_ARGS[3]:-}" ]; then
            if [ "${PARSED_ARGS[4]:-}" = "--dry-run" ]; then
                update_component "${PARSED_ARGS[1]}" "${PARSED_ARGS[3]}" "true"
            else
                update_component "${PARSED_ARGS[1]}" "${PARSED_ARGS[3]}" "false"
            fi
        else
            print_error "Usage: $0 update <component> --version <version> [--dry-run]"
            exit 1
        fi
        ;;
    "rollback")
        if [ "${PARSED_ARGS[2]:-}" = "--steps" ] && [ -n "${PARSED_ARGS[3]:-}" ]; then
            rollback_component "${PARSED_ARGS[1]}" "${PARSED_ARGS[3]}"
        else
            rollback_component "${PARSED_ARGS[1]}"
        fi
        ;;
    "task-status")
        handle_task_command "status" "${PARSED_ARGS[1]:-}"
        ;;
    "task-list")
        handle_task_command "list"
        ;;
    "task-cancel")
        handle_task_command "cancel" "${PARSED_ARGS[1]:-}"
        ;;
    "task-logs")
        handle_task_command "logs" "${PARSED_ARGS[1]:-}"
        ;;
    "help"|"--help"|"-h")
        show_usage
        ;;
    *)
        print_error "Unknown command: ${PARSED_ARGS[0]:-}"
        show_usage
        exit 1
        ;;
esac