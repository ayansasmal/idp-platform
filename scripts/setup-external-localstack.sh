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
    
    if check_localstack; then
        validate_services && echo -e "${GREEN}✅ LocalStack is properly configured${NC}" || echo -e "${RED}❌ LocalStack needs reconfiguration${NC}"
    else
        echo -e "${YELLOW}📝 LocalStack is not running. Creating setup files...${NC}"
        start_localstack
    fi
    
    setup_hostname_resolution
    create_idp_config
    test_connectivity
    show_idp_integration
    
    echo -e "${GREEN}🎉 External LocalStack setup complete!${NC}"
    echo -e "${BLUE}💡 Run this script anytime to validate LocalStack configuration${NC}"
}

# Run main function
main "$@"