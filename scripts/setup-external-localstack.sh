#!/bin/bash

# External LocalStack Setup Script for IDP Platform
# This script configures external LocalStack for proper IDP integration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOCALSTACK_PORT=${LOCALSTACK_PORT:-4566}
LOCALSTACK_HOST=${LOCALSTACK_HOST:-localhost}

echo -e "${BLUE}🏗️ Setting up External LocalStack for IDP Platform${NC}"
echo

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install dependencies
install_dependencies() {
    echo -e "${YELLOW}📦 Checking and installing required dependencies...${NC}"
    
    # Check for Python and pip
    if ! command_exists python3; then
        echo -e "${RED}❌ Python 3 is required but not installed${NC}"
        echo -e "${YELLOW}💡 Install Python 3: ${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  brew install python3"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "  sudo apt-get install python3 python3-pip  # Ubuntu/Debian"
            echo "  sudo yum install python3 python3-pip     # RHEL/CentOS"
        fi
        return 1
    fi
    
    if ! command_exists pip3; then
        echo -e "${RED}❌ pip3 is required but not installed${NC}"
        echo -e "${YELLOW}💡 Install pip3: ${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  brew install python3"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "  sudo apt-get install python3-pip  # Ubuntu/Debian"
            echo "  sudo yum install python3-pip      # RHEL/CentOS"
        fi
        return 1
    fi
    
    # Check for jq
    if ! command_exists jq; then
        echo -e "${YELLOW}📦 Installing jq...${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command_exists brew; then
                brew install jq
            else
                echo -e "${RED}❌ Homebrew not found. Please install jq manually: https://stedolan.github.io/jq/download/${NC}"
                return 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command_exists apt-get; then
                sudo apt-get update && sudo apt-get install -y jq
            elif command_exists yum; then
                sudo yum install -y jq
            else
                echo -e "${RED}❌ Package manager not found. Please install jq manually${NC}"
                return 1
            fi
        fi
    fi
    
    # Check for curl
    if ! command_exists curl; then
        echo -e "${YELLOW}📦 Installing curl...${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo -e "${GREEN}✅ curl should be pre-installed on macOS${NC}"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command_exists apt-get; then
                sudo apt-get update && sudo apt-get install -y curl
            elif command_exists yum; then
                sudo yum install -y curl
            fi
        fi
    fi
    
    # Check for docker
    if ! command_exists docker; then
        echo -e "${RED}❌ Docker is required but not installed${NC}"
        echo -e "${YELLOW}💡 Install Docker: https://docs.docker.com/get-docker/${NC}"
        return 1
    fi
    
    # Check for docker-compose
    if ! command_exists docker-compose; then
        echo -e "${YELLOW}📦 Installing docker-compose...${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo -e "${GREEN}✅ docker-compose should be included with Docker Desktop${NC}"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo -e "${YELLOW}💡 Install docker-compose: ${NC}"
            echo "  sudo curl -L \"https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose"
            echo "  sudo chmod +x /usr/local/bin/docker-compose"
        fi
    fi
    
    echo -e "${GREEN}✅ Basic dependencies checked${NC}"
    return 0
}

# Function to install awslocal
install_awslocal() {
    echo -e "${YELLOW}🔧 Checking awslocal installation...${NC}"
    
    if command_exists awslocal; then
        echo -e "${GREEN}✅ awslocal is already installed${NC}"
        awslocal --version
        return 0
    fi
    
    echo -e "${YELLOW}📦 Installing awslocal...${NC}"
    
    # Try to install awslocal
    if pip3 install awslocal; then
        echo -e "${GREEN}✅ awslocal installed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to install awslocal with pip3${NC}"
        echo -e "${YELLOW}💡 Trying alternative installation methods...${NC}"
        
        # Try with --user flag
        if pip3 install --user awslocal; then
            echo -e "${GREEN}✅ awslocal installed successfully (user scope)${NC}"
            echo -e "${YELLOW}💡 You may need to add ~/.local/bin to your PATH${NC}"
            export PATH="$HOME/.local/bin:$PATH"
        else
            echo -e "${RED}❌ Failed to install awslocal${NC}"
            echo -e "${YELLOW}💡 Manual installation: pip3 install awslocal${NC}"
            return 1
        fi
    fi
    
    # Verify installation
    if command_exists awslocal; then
        echo -e "${GREEN}✅ awslocal verification successful${NC}"
        awslocal --version
    else
        echo -e "${RED}❌ awslocal installation verification failed${NC}"
        echo -e "${YELLOW}💡 You may need to restart your shell or update PATH${NC}"
        return 1
    fi
    
    return 0
}

# Function to setup AWS CLI configuration for LocalStack
setup_aws_config() {
    echo -e "${YELLOW}⚙️ Setting up AWS CLI configuration for LocalStack...${NC}"
    
    # Create AWS config directory if it doesn't exist
    mkdir -p ~/.aws
    
    # Create or update AWS credentials for LocalStack
    cat > ~/.aws/credentials << 'EOF'
[default]
aws_access_key_id = test
aws_secret_access_key = test
region = us-east-1

[localstack]
aws_access_key_id = test
aws_secret_access_key = test
region = us-east-1
EOF

    # Create or update AWS config
    cat > ~/.aws/config << 'EOF'
[default]
region = us-east-1
output = json

[profile localstack]
region = us-east-1
output = json
EOF

    echo -e "${GREEN}✅ AWS CLI configuration created${NC}"
}

# Function to check if LocalStack is running
check_localstack() {
    echo -e "${YELLOW}⏳ Checking LocalStack availability...${NC}"
    
    if curl -s "http://${LOCALSTACK_HOST}:${LOCALSTACK_PORT}/_localstack/health" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ LocalStack is running at http://${LOCALSTACK_HOST}:${LOCALSTACK_PORT}${NC}"
        return 0
    else
        echo -e "${RED}❌ LocalStack is not accessible at http://${LOCALSTACK_HOST}:${LOCALSTACK_PORT}${NC}"
        return 1
    fi
}

# Function to start LocalStack with IDP configuration
start_localstack() {
    echo -e "${YELLOW}🚀 Starting LocalStack with IDP services...${NC}"
    
    cat > docker-compose.localstack.yml << 'EOF'
version: '3.8'
services:
  localstack:
    container_name: localstack-idp
    image: localstack/localstack:3.0
    ports:
      - "4566:4566"
    environment:
      - SERVICES=cognito-idp,rds,s3,secretsmanager,iam,ecr
      - DEBUG=1
      - DATA_DIR=/tmp/localstack/data
      - HOSTNAME_EXTERNAL=localhost.localstack.cloud
      - COGNITO_PROVIDER_DEVELOPER_USER_POOL_DOMAIN=localhost.localstack.cloud
    volumes:
      - "${TMPDIR:-/tmp}/localstack:/tmp/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
    networks:
      - idp-network

networks:
  idp-network:
    driver: bridge
EOF

    echo -e "${BLUE}📄 Created docker-compose.localstack.yml${NC}"
    echo -e "${YELLOW}🏃 Run: docker-compose -f docker-compose.localstack.yml up -d${NC}"
    echo
}

# Function to configure LocalStack hostname resolution
setup_hostname_resolution() {
    echo -e "${YELLOW}🌐 Setting up hostname resolution...${NC}"
    
    # Check if localhost.localstack.cloud is already in /etc/hosts
    if grep -q "localhost.localstack.cloud" /etc/hosts 2>/dev/null; then
        echo -e "${GREEN}✅ localhost.localstack.cloud already in /etc/hosts${NC}"
    else
        echo -e "${YELLOW}📝 Adding localhost.localstack.cloud to /etc/hosts...${NC}"
        echo "Run this command with sudo:"
        echo -e "${BLUE}echo '127.0.0.1 localhost.localstack.cloud' | sudo tee -a /etc/hosts${NC}"
    fi
    echo
}

# Function to validate required services
validate_services() {
    echo -e "${YELLOW}🔍 Validating required LocalStack services...${NC}"
    
    if ! command_exists awslocal; then
        echo -e "${RED}❌ awslocal not available for service validation${NC}"
        return 1
    fi
    
    local health_response
    health_response=$(curl -s "http://${LOCALSTACK_HOST}:${LOCALSTACK_PORT}/_localstack/health" | jq -r '.services')
    
    local required_services=("cognito-idp" "rds" "s3" "secretsmanager" "iam" "ecr")
    local all_available=true
    
    for service in "${required_services[@]}"; do
        local status
        status=$(echo "$health_response" | jq -r ".[\"$service\"]")
        
        if [[ "$status" == "available" || "$status" == "running" ]]; then
            echo -e "${GREEN}✅ $service: $status${NC}"
        else
            echo -e "${RED}❌ $service: $status${NC}"
            all_available=false
        fi
    done
    
    if $all_available; then
        echo -e "${GREEN}✅ All required services are available${NC}"
        
        # Test awslocal connectivity
        echo -e "${YELLOW}🔗 Testing awslocal connectivity...${NC}"
        if awslocal sts get-caller-identity >/dev/null 2>&1; then
            echo -e "${GREEN}✅ awslocal connectivity test passed${NC}"
        else
            echo -e "${YELLOW}⚠️ awslocal connectivity test failed (LocalStack may still be starting)${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}❌ Some services are not available${NC}"
        return 1
    fi
}

# Function to create IDP-specific LocalStack configuration
create_idp_config() {
    echo -e "${YELLOW}⚙️ Creating IDP-specific LocalStack configuration...${NC}"
    
    cat > localstack-idp-config.json << 'EOF'
{
  "services": {
    "cognito-idp": {
      "endpoint_url": "http://localhost:4566",
      "region": "us-east-1"
    },
    "rds": {
      "endpoint_url": "http://localhost:4566",
      "region": "us-east-1"
    },
    "s3": {
      "endpoint_url": "http://localhost:4566",
      "region": "us-east-1",
      "path_style": true
    },
    "secretsmanager": {
      "endpoint_url": "http://localhost:4566",
      "region": "us-east-1"
    },
    "iam": {
      "endpoint_url": "http://localhost:4566",
      "region": "us-east-1"
    },
    "ecr": {
      "endpoint_url": "http://localhost:4566",
      "region": "us-east-1"
    }
  },
  "hostname_external": "localhost.localstack.cloud",
  "cognito_idp_issuer": "http://localhost.localstack.cloud:4566"
}
EOF

    echo -e "${GREEN}✅ Created localstack-idp-config.json${NC}"
    echo
}

# Function to test LocalStack connectivity from different contexts
test_connectivity() {
    echo -e "${YELLOW}🔗 Testing LocalStack connectivity...${NC}"
    
    # Test localhost
    if curl -s "http://localhost:${LOCALSTACK_PORT}/_localstack/health" >/dev/null; then
        echo -e "${GREEN}✅ localhost:${LOCALSTACK_PORT} - accessible${NC}"
    else
        echo -e "${RED}❌ localhost:${LOCALSTACK_PORT} - not accessible${NC}"
    fi
    
    # Test localhost.localstack.cloud
    if curl -s "http://localhost.localstack.cloud:${LOCALSTACK_PORT}/_localstack/health" >/dev/null; then
        echo -e "${GREEN}✅ localhost.localstack.cloud:${LOCALSTACK_PORT} - accessible${NC}"
    else
        echo -e "${RED}❌ localhost.localstack.cloud:${LOCALSTACK_PORT} - not accessible${NC}"
    fi
    
    echo
}

# Function to display IDP integration status
show_idp_integration() {
    echo -e "${BLUE}🔧 IDP Integration Status:${NC}"
    echo
    echo -e "${YELLOW}📋 LocalStack URLs for IDP:${NC}"
    echo "  • Health: http://localhost:4566/_localstack/health"
    echo "  • Cognito: http://localhost.localstack.cloud:4566"
    echo "  • S3: http://localhost:4566"
    echo "  • RDS: http://localhost:4566"
    echo
    echo -e "${YELLOW}🔑 Next Steps:${NC}"
    echo "  1. Ensure LocalStack is running with required services"
    echo "  2. Run: ./scripts/setup-cognito.sh (already configured)"
    echo "  3. Apply IDP external services: kubectl apply -f infrastructure/external-services/"
    echo "  4. Access ArgoCD: https://localhost:8080"
    echo "  5. Access Backstage: http://localhost:3000"
    echo
}

# Main execution
main() {
    echo -e "${BLUE}🎯 External LocalStack Setup for IDP Platform${NC}"
    echo
    
    # Install dependencies first
    echo -e "${BLUE}🔧 Phase 1: Installing Dependencies${NC}"
    if ! install_dependencies; then
        echo -e "${RED}❌ Dependency installation failed. Please install missing dependencies and retry.${NC}"
        exit 1
    fi
    echo
    
    # Install and configure awslocal
    echo -e "${BLUE}🔧 Phase 2: Installing awslocal${NC}"
    if ! install_awslocal; then
        echo -e "${RED}❌ awslocal installation failed. Some features may not work.${NC}"
        echo -e "${YELLOW}💡 You can install manually: pip3 install awslocal${NC}"
    fi
    echo
    
    # Setup AWS configuration
    echo -e "${BLUE}🔧 Phase 3: AWS Configuration${NC}"
    setup_aws_config
    echo
    
    # Check LocalStack and validate services
    echo -e "${BLUE}🔧 Phase 4: LocalStack Validation${NC}"
    if check_localstack; then
        if validate_services; then
            echo -e "${GREEN}✅ LocalStack is properly configured${NC}"
        else
            echo -e "${RED}❌ LocalStack needs reconfiguration${NC}"
            echo -e "${YELLOW}💡 Some services may still be starting up${NC}"
        fi
    else
        echo -e "${YELLOW}📝 LocalStack is not running. Creating setup files...${NC}"
        start_localstack
    fi
    echo
    
    # Additional setup steps
    echo -e "${BLUE}🔧 Phase 5: Additional Configuration${NC}"
    setup_hostname_resolution
    create_idp_config
    test_connectivity
    show_idp_integration
    
    echo -e "${GREEN}🎉 External LocalStack setup complete!${NC}"
    echo -e "${BLUE}💡 Run this script anytime to validate LocalStack configuration${NC}"
    echo
    
    # Final recommendations
    echo -e "${YELLOW}📝 Next Steps:${NC}"
    echo "  1. If LocalStack is not running: docker-compose -f docker-compose.localstack.yml up -d"
    echo "  2. Test awslocal: awslocal sts get-caller-identity"
    echo "  3. Apply IDP external services: kubectl apply -f infrastructure/external-services/"
    echo "  4. Test ArgoCD Cognito: https://localhost:8080"
}

# Run main function
main "$@"