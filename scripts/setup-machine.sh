#!/bin/bash

# Complete Machine Setup Script for IDP Platform
# Sets up everything needed for the IDP platform on a fresh machine

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

print_header() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $(printf "%-60s" "$1") ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
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

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            echo "ubuntu"
        elif command -v yum &> /dev/null; then
            echo "centos"
        else
            echo "linux"
        fi
    else
        echo "unknown"
    fi
}

# Install prerequisites based on OS
install_prerequisites() {
    local os=$(detect_os)
    print_status "Installing prerequisites for $os..."
    
    case $os in
        "macos")
            install_macos_prerequisites
            ;;
        "ubuntu")
            install_ubuntu_prerequisites
            ;;
        "centos")
            install_centos_prerequisites
            ;;
        *)
            print_error "Unsupported operating system: $os"
            print_status "Please install the following manually:"
            print_status "- Docker Desktop with Kubernetes enabled"
            print_status "- kubectl"
            print_status "- curl, jq"
            print_status "- Node.js 16+ and npm/yarn"
            print_status "- Git"
            exit 1
            ;;
    esac
}

install_macos_prerequisites() {
    print_status "Installing macOS prerequisites..."
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        print_status "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Install packages
    brew update
    
    # Docker Desktop (user needs to install manually)
    if ! command -v docker &> /dev/null; then
        print_warning "Docker Desktop not found. Please install manually:"
        print_status "1. Download from: https://www.docker.com/products/docker-desktop/"
        print_status "2. Enable Kubernetes in Docker Desktop settings"
        print_status "3. Re-run this script after installation"
        exit 1
    fi
    
    # Other tools
    brew install kubectl curl jq node git awscli
    
    # Helm
    if ! command -v helm &> /dev/null; then
        brew install helm
    fi
    
    print_success "macOS prerequisites installed"
}

install_ubuntu_prerequisites() {
    print_status "Installing Ubuntu prerequisites..."
    
    sudo apt-get update
    
    # Docker
    if ! command -v docker &> /dev/null; then
        print_status "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
        
        # Docker Compose
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    
    # kubectl
    if ! command -v kubectl &> /dev/null; then
        print_status "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    fi
    
    # Other tools
    sudo apt-get install -y curl jq git
    
    # Node.js
    if ! command -v node &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    
    # AWS CLI
    if ! command -v aws &> /dev/null; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
    fi
    
    # Helm
    if ! command -v helm &> /dev/null; then
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    
    print_success "Ubuntu prerequisites installed"
    print_warning "Please logout and login again for Docker group changes to take effect"
}

install_centos_prerequisites() {
    print_status "Installing CentOS/RHEL prerequisites..."
    
    sudo yum update -y
    
    # Docker
    if ! command -v docker &> /dev/null; then
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
    fi
    
    # kubectl
    if ! command -v kubectl &> /dev/null; then
        cat << 'EOF' | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
        sudo yum install -y kubectl
    fi
    
    # Other tools
    sudo yum install -y curl jq git
    
    # Node.js
    if ! command -v node &> /dev/null; then
        curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
        sudo yum install -y nodejs
    fi
    
    print_success "CentOS prerequisites installed"
}

# Setup Kubernetes cluster
setup_kubernetes() {
    print_status "Setting up Kubernetes cluster..."
    
    # Check if kubectl can connect to a cluster
    if kubectl cluster-info &> /dev/null; then
        print_success "Kubernetes cluster is already accessible"
        kubectl cluster-info
    else
        print_status "No Kubernetes cluster found. Options:"
        echo "1. Docker Desktop - Enable Kubernetes in settings"
        echo "2. Kind - Lightweight local cluster"
        echo "3. Minikube - VM-based local cluster"
        echo ""
        
        read -p "Would you like to set up Kind cluster? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            setup_kind_cluster
        else
            print_warning "Please set up a Kubernetes cluster manually and re-run setup"
            exit 1
        fi
    fi
}

setup_kind_cluster() {
    print_status "Setting up Kind cluster..."
    
    # Install Kind
    if ! command -v kind &> /dev/null; then
        print_status "Installing Kind..."
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
    fi
    
    # Create cluster
    if ! kind get clusters | grep -q "idp-cluster"; then
        print_status "Creating Kind cluster..."
        cat << 'EOF' > /tmp/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 8080
    hostPort: 8080
    protocol: TCP
  - containerPort: 3000
    hostPort: 3000
    protocol: TCP
EOF
        
        kind create cluster --config /tmp/kind-config.yaml --name idp-cluster
        rm /tmp/kind-config.yaml
        
        # Set kubectl context
        kubectl cluster-info --context kind-idp-cluster
    fi
    
    print_success "Kind cluster ready"
}

# Install development tools
install_dev_tools() {
    print_status "Installing development tools..."
    
    # Install awslocal (LocalStack CLI)
    if ! command -v awslocal &> /dev/null; then
        pip3 install awscli-local || {
            print_warning "Could not install awslocal via pip3"
            print_status "You can install it later with: pip3 install awslocal"
        }
    fi
    
    # Install additional tools
    if command -v npm &> /dev/null; then
        # Windmill CLI
        npm install -g windmill-cli@1.150.0 || print_warning "Could not install Windmill CLI"
        
        # Yarn (preferred for Backstage)
        npm install -g yarn || print_warning "Could not install Yarn"
    fi
    
    print_success "Development tools installed"
}

# Verify installation
verify_installation() {
    print_header "Verifying Installation"
    
    local errors=0
    
    # Check required tools
    local tools=("docker" "kubectl" "curl" "jq" "git" "node" "npm")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            local version=$("$tool" --version 2>/dev/null | head -n1)
            print_success "$tool: $version"
        else
            print_error "$tool not found"
            ((errors++))
        fi
    done
    
    # Check Kubernetes
    if kubectl cluster-info &> /dev/null; then
        print_success "Kubernetes cluster accessible"
    else
        print_error "Kubernetes cluster not accessible"
        ((errors++))
    fi
    
    # Check Docker
    if docker ps &> /dev/null; then
        print_success "Docker daemon running"
    else
        print_error "Docker daemon not running"
        ((errors++))
    fi
    
    return $errors
}

# Main setup function
main() {
    print_header "IDP Platform Machine Setup"
    
    print_status "This script will install all prerequisites for the IDP platform"
    print_warning "This may modify your system configuration"
    echo ""
    
    read -p "Continue with installation? (y/n): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Setup cancelled"
        exit 0
    fi
    
    # Install prerequisites
    install_prerequisites
    
    # Setup Kubernetes
    setup_kubernetes
    
    # Install development tools
    install_dev_tools
    
    # Verify installation
    if verify_installation; then
        print_header "Setup Complete"
        echo -e "${GREEN}🎉 Your machine is ready for the IDP platform!${NC}\n"
        echo -e "${BLUE}Next steps:${NC}"
        echo -e "  1. ${YELLOW}./scripts/idp.sh setup${NC}          # Setup the IDP platform"
        echo -e "  2. ${YELLOW}./scripts/idp.sh setup-windmill${NC} # Setup Windmill orchestration"
        echo -e "  3. ${YELLOW}./scripts/idp.sh start${NC}          # Start all services"
        echo ""
        echo -e "${BLUE}Optional:${NC}"
        echo -e "  • ${YELLOW}./scripts/idp.sh config${NC}         # Run configuration wizard"
        echo -e "  • ${YELLOW}./scripts/idp.sh credentials setup${NC} # Setup credentials"
    else
        print_error "Setup completed with errors. Please resolve the issues above."
        exit 1
    fi
}

# Command line interface
case "${1:-setup}" in
    "setup")
        main
        ;;
    "verify")
        verify_installation
        ;;
    "k8s"|"kubernetes")
        setup_kubernetes
        ;;
    "help"|"--help")
        echo "Machine Setup Script for IDP Platform"
        echo ""
        echo "Commands:"
        echo "  setup      - Complete machine setup (default)"
        echo "  verify     - Verify installation"
        echo "  k8s        - Setup Kubernetes cluster only"
        echo "  help       - Show this help"
        ;;
    *)
        print_error "Unknown command: $1"
        exit 1
        ;;
esac