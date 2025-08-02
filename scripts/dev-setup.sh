#!/bin/bash

# IDP Platform Development Setup Script
# Sets up the development environment with all necessary tools

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Platform info
PLATFORM_NAME="IDP Platform"
PLATFORM_VERSION="1.0.0"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               IDP Platform Development Setup                 ║"
echo "║                                                              ║"
echo "║  🔧 Setting up your development environment...               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if we're in the right directory
if [[ ! -f "CLAUDE.md" ]] || [[ ! -d "applications" ]]; then
    echo -e "${RED}Error: Please run this script from the IDP platform root directory${NC}"
    exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install missing tools
install_tools() {
    echo -e "\n${BLUE}📦 Checking required tools...${NC}"
    
    local missing_tools=()
    
    # Check kubectl
    if ! command_exists kubectl; then
        missing_tools+=("kubectl")
    else
        echo -e "${GREEN}✓${NC} kubectl: $(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo 'installed')"
    fi
    
    # Check docker
    if ! command_exists docker; then
        missing_tools+=("docker")
    else
        echo -e "${GREEN}✓${NC} docker: $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'installed')"
    fi
    
    # Check helm
    if ! command_exists helm; then
        missing_tools+=("helm")
    else
        echo -e "${GREEN}✓${NC} helm: $(helm version --short 2>/dev/null || echo 'installed')"
    fi
    
    # Check istioctl
    if ! command_exists istioctl; then
        missing_tools+=("istioctl")
    else
        echo -e "${GREEN}✓${NC} istioctl: $(istioctl version --short 2>/dev/null | head -1 || echo 'installed')"
    fi
    
    # Check argocd CLI (optional)
    if ! command_exists argocd; then
        echo -e "${YELLOW}○${NC} argocd CLI: not installed (optional)"
    else
        echo -e "${GREEN}✓${NC} argocd CLI: $(argocd version --client --short 2>/dev/null || echo 'installed')"
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}Missing tools: ${missing_tools[*]}${NC}"
        echo -e "Please install them manually or visit: https://docs.idp-platform.dev/setup"
        return 1
    fi
    
    echo -e "\n${GREEN}✓ All required tools are installed${NC}"
    return 0
}

# Function to check cluster connectivity
check_cluster() {
    echo -e "\n${BLUE}🔗 Checking Kubernetes cluster connectivity...${NC}"
    
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
        echo -e "${YELLOW}Please ensure your cluster is running:${NC}"
        echo -e "  • Docker Desktop: Enable Kubernetes in settings"
        echo -e "  • Kind: kind create cluster"
        echo -e "  • Minikube: minikube start"
        return 1
    fi
    
    local cluster_info=$(kubectl cluster-info --short 2>/dev/null)
    echo -e "${GREEN}✓${NC} Connected to cluster: $(echo "$cluster_info" | head -1 | cut -d' ' -f6-)"
    
    # Check node status
    local nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    echo -e "${GREEN}✓${NC} Cluster has $nodes node(s) ready"
    
    return 0
}

# Function to setup aliases and shortcuts
setup_aliases() {
    echo -e "\n${BLUE}⚡ Setting up development aliases...${NC}"
    
    local aliases_file="$HOME/.idp_aliases"
    
    cat > "$aliases_file" << 'EOF'
# IDP Platform Development Aliases

# Quick platform management
alias idp-start='./scripts/quick-start.sh'
alias idp-stop='./scripts/start-platform.sh stop'
alias idp-status='./scripts/start-platform.sh status'
alias idp-health='./scripts/start-platform.sh health'
alias idp-restart='./scripts/start-platform.sh restart'

# Service access shortcuts
alias idp-argocd='open http://localhost:8080'
alias idp-backstage='open http://localhost:3000'
alias idp-workflows='open http://localhost:4000'
alias idp-grafana='open http://localhost:3001'
alias idp-prometheus='open http://localhost:9090'
alias idp-jaeger='open http://localhost:16686'
alias idp-kiali='open http://localhost:20001'

# Kubernetes shortcuts for IDP
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kga='kubectl get all'
alias kdp='kubectl describe pod'
alias kds='kubectl describe svc'
alias klogs='kubectl logs'

# ArgoCD shortcuts
alias argocd-login='argocd login localhost:8080 --insecure'
alias argocd-apps='argocd app list'
alias argocd-sync='argocd app sync'

# Platform specific shortcuts
alias idp-pods='kubectl get pods --all-namespaces | grep -E "(argocd|backstage|argo-workflows|istio|grafana|prometheus)"'
alias idp-apps='kubectl get applications -n argocd'
alias idp-logs-argocd='kubectl logs -n argocd deployment/argocd-server -f'
alias idp-logs-backstage='kubectl logs -n backstage deployment/backstage -f'
alias idp-logs-workflows='kubectl logs -n argo-workflows deployment/argo-server -f'

# Development helpers
alias idp-port-forward='./scripts/start-platform.sh start'
alias idp-tunnel='kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80'
EOF

    echo -e "${GREEN}✓${NC} Created aliases file: $aliases_file"
    
    # Add to shell profile if not already present
    local shell_profile=""
    if [[ -n "$ZSH_VERSION" ]]; then
        shell_profile="$HOME/.zshrc"
    elif [[ -n "$BASH_VERSION" ]]; then
        shell_profile="$HOME/.bashrc"
    fi
    
    if [[ -n "$shell_profile" ]] && [[ -f "$shell_profile" ]]; then
        if ! grep -q "source.*\.idp_aliases" "$shell_profile"; then
            echo "" >> "$shell_profile"
            echo "# IDP Platform aliases" >> "$shell_profile"
            echo "source $aliases_file" >> "$shell_profile"
            echo -e "${GREEN}✓${NC} Added aliases to $shell_profile"
            echo -e "${YELLOW}  Run 'source $shell_profile' or restart your terminal to use aliases${NC}"
        else
            echo -e "${GREEN}✓${NC} Aliases already configured in $shell_profile"
        fi
    fi
}

# Function to create development configuration
create_dev_config() {
    echo -e "\n${BLUE}⚙️  Creating development configuration...${NC}"
    
    # Create .env file for development
    cat > .env << 'EOF'
# IDP Platform Development Configuration

# Default ports for services
ARGOCD_PORT=8080
BACKSTAGE_PORT=3000
GRAFANA_PORT=3001
PROMETHEUS_PORT=9090
JAEGER_PORT=16686
KIALI_PORT=20001
MONITORING_PORT=8090

# Development settings
DEV_MODE=true
LOG_LEVEL=debug

# Local registry settings (if using kind/minikube)
LOCAL_REGISTRY=localhost:5000

# Platform metadata
PLATFORM_NAME="IDP Platform"
PLATFORM_VERSION="1.0.0"
EOF

    echo -e "${GREEN}✓${NC} Created .env file with development configuration"
    
    # Create gitignore entries for development files
    if [[ -f .gitignore ]]; then
        if ! grep -q "scripts/\.port-forward-pids" .gitignore; then
            echo "" >> .gitignore
            echo "# IDP Platform development files" >> .gitignore
            echo "scripts/.port-forward-pids" >> .gitignore
            echo ".env.local" >> .gitignore
            echo -e "${GREEN}✓${NC} Updated .gitignore with development entries"
        fi
    fi
}

# Function to test the setup
test_setup() {
    echo -e "\n${BLUE}🧪 Testing platform setup...${NC}"
    
    # Test script permissions
    if [[ -x "scripts/start-platform.sh" ]] && [[ -x "scripts/quick-start.sh" ]]; then
        echo -e "${GREEN}✓${NC} Platform scripts are executable"
    else
        echo -e "${RED}✗${NC} Platform scripts are not executable"
        chmod +x scripts/*.sh
        echo -e "${GREEN}✓${NC} Fixed script permissions"
    fi
    
    # Test kubectl access to critical namespaces
    local namespaces=("argocd" "backstage" "istio-system")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pod_count=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
            echo -e "${GREEN}✓${NC} Namespace $ns: $pod_count running pods"
        else
            echo -e "${YELLOW}○${NC} Namespace $ns: not found (will be created when needed)"
        fi
    done
}

# Function to show next steps
show_next_steps() {
    echo -e "\n${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                     Setup Complete! 🎉                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BLUE}🚀 Ready to start developing!${NC}\n"
    
    echo -e "${BLUE}Quick Start:${NC}"
    echo -e "  ${GREEN}1.${NC} Start the platform:  ${YELLOW}./scripts/quick-start.sh${NC}"
    echo -e "  ${GREEN}2.${NC} Access ArgoCD:       ${YELLOW}http://localhost:8080${NC}"
    echo -e "  ${GREEN}3.${NC} Access Backstage:    ${YELLOW}http://localhost:3000${NC}"
    
    echo -e "\n${BLUE}Development Commands:${NC}"
    echo -e "  ${GREEN}•${NC} Start all services:   ${YELLOW}idp-start${NC}"
    echo -e "  ${GREEN}•${NC} Check status:         ${YELLOW}idp-status${NC}"
    echo -e "  ${GREEN}•${NC} View health:          ${YELLOW}idp-health${NC}"
    echo -e "  ${GREEN}•${NC} Stop all services:    ${YELLOW}idp-stop${NC}"
    
    echo -e "\n${BLUE}Documentation:${NC}"
    echo -e "  ${GREEN}•${NC} Getting Started:      ${YELLOW}docs/tutorials/getting-started.md${NC}"
    echo -e "  ${GREEN}•${NC} Platform Access:      ${YELLOW}access-guide.md${NC}"
    echo -e "  ${GREEN}•${NC} Architecture:         ${YELLOW}docs/architecture/platform-overview.md${NC}"
    
    echo -e "\n${YELLOW}💡 Pro Tips:${NC}"
    echo -e "  ${GREEN}•${NC} Source your shell profile to use aliases: ${YELLOW}source ~/.zshrc${NC} (or ~/.bashrc)"
    echo -e "  ${GREEN}•${NC} Keep the quick-start terminal open for port forwards"
    echo -e "  ${GREEN}•${NC} Use ${YELLOW}kubectl get applications -n argocd${NC} to see GitOps status"
    
    echo -e "\n${PURPLE}Happy coding! 🚀${NC}\n"
}

# Main execution
main() {
    echo -e "${BLUE}Setting up IDP Platform development environment...${NC}\n"
    
    # Run setup steps
    install_tools || {
        echo -e "\n${RED}Setup failed: Missing required tools${NC}"
        exit 1
    }
    
    check_cluster || {
        echo -e "\n${RED}Setup failed: Cluster connectivity issues${NC}"
        exit 1
    }
    
    setup_aliases
    create_dev_config
    test_setup
    
    show_next_steps
}

# Run main function
main "$@"