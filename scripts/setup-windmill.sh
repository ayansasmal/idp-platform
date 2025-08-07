#!/bin/bash

# Windmill Setup Script for IDP Platform
# Installs and configures Windmill for workflow orchestration and AI agent integration

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
WINDMILL_DIR="$ROOT_DIR/windmill"

# Configuration
WINDMILL_VERSION="1.150.0"
WINDMILL_PORT="8000"
WINDMILL_DB_PORT="5432"
WINDMILL_WORKSPACE="idp"

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

# Check prerequisites
check_prerequisites() {
    local errors=0
    
    print_status "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required but not installed"
        ((errors++))
    else
        print_success "Docker found: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is required but not installed"
        ((errors++))
    else
        print_success "Docker Compose found"
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        ((errors++))
    fi
    
    # Check if ports are available
    local ports_to_check=($WINDMILL_PORT $WINDMILL_DB_PORT)
    for port in "${ports_to_check[@]}"; do
        if lsof -ti:$port &> /dev/null; then
            print_warning "Port $port is already in use"
        else
            print_status "Port $port is available"
        fi
    done
    
    return $errors
}

# Create Windmill configuration
create_windmill_config() {
    print_status "Creating Windmill configuration..."
    
    # Create .env file for Windmill
    cat > "$ROOT_DIR/.env.windmill" << EOF
# Windmill Configuration for IDP Platform
WM_VERSION=$WINDMILL_VERSION
WINDMILL_PORT=$WINDMILL_PORT
WINDMILL_DB_PORT=$WINDMILL_DB_PORT

# Database Configuration  
DATABASE_URL=postgresql://windmill:windmill@windmill-db:5432/windmill
RUST_LOG=info

# Security
WM_BASE_URL=http://localhost:$WINDMILL_PORT
WM_COOKIE_DOMAIN=localhost

# Workers
NUM_WORKERS=3
WORKER_GROUP=default
DISABLE_NUSER=false
KEEP_JOB_DIR=false

# Optional: AI Integration
OPENAI_API_KEY=\${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY:-}
EOF

    print_success "Windmill configuration created"
}

# Create Docker Compose for Windmill
create_docker_compose() {
    print_status "Creating Docker Compose configuration..."
    
    cat > "$ROOT_DIR/docker-compose.windmill.yml" << 'EOF'
version: '3.8'

services:
  windmill-db:
    image: postgres:14
    container_name: windmill-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: windmill
      POSTGRES_USER: windmill
      POSTGRES_PASSWORD: windmill
    ports:
      - "${WINDMILL_DB_PORT:-5432}:5432"
    volumes:
      - windmill_db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U windmill -d windmill"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - windmill

  windmill-server:
    image: ghcr.io/windmill-labs/windmill:${WM_VERSION:-1.150.0}
    container_name: windmill-server
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://windmill:windmill@windmill-db:5432/windmill
      RUST_LOG: info
      MODE: server
    ports:
      - "${WINDMILL_PORT:-8000}:8000"
    depends_on:
      windmill-db:
        condition: service_healthy
    volumes:
      - windmill_worker_logs:/tmp/windmill
    networks:
      - windmill

  windmill-worker:
    image: ghcr.io/windmill-labs/windmill:${WM_VERSION:-1.150.0}
    container_name: windmill-worker
    restart: unless-stopped
    environment:
      DATABASE_URL: postgresql://windmill:windmill@windmill-db:5432/windmill
      RUST_LOG: info
      MODE: worker
      WORKER_GROUP: default
      NUM_WORKERS: 3
      DISABLE_NUSER: "false"
      KEEP_JOB_DIR: "false"
    depends_on:
      windmill-db:
        condition: service_healthy
    volumes:
      - windmill_worker_logs:/tmp/windmill
      - /var/run/docker.sock:/var/run/docker.sock
      - windmill_worker_dependency_cache:/tmp/windmill/cache
    networks:
      - windmill

  windmill-lsp:
    image: ghcr.io/windmill-labs/windmill-lsp:${WM_VERSION:-1.150.0}
    container_name: windmill-lsp
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - windmill_lsp_cache:/tmp/windmill/cache
    networks:
      - windmill

volumes:
  windmill_db_data:
  windmill_worker_logs:
  windmill_worker_dependency_cache:
  windmill_lsp_cache:

networks:
  windmill:
    driver: bridge
EOF

    print_success "Docker Compose configuration created"
}

# Start Windmill services
start_windmill() {
    print_status "Starting Windmill services..."
    
    cd "$ROOT_DIR"
    
    # Load environment variables
    export $(grep -v '^#' .env.windmill | xargs)
    
    # Start services
    docker-compose -f docker-compose.windmill.yml up -d
    
    print_status "Waiting for Windmill to be ready..."
    
    # Wait for services to be healthy
    local retries=30
    while [ $retries -gt 0 ]; do
        if curl -f -s "http://localhost:$WINDMILL_PORT/api/version" > /dev/null 2>&1; then
            print_success "Windmill is ready!"
            break
        fi
        
        print_status "Waiting for Windmill... ($retries retries left)"
        sleep 10
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        print_error "Windmill failed to start within expected time"
        return 1
    fi
    
    # Display status
    docker-compose -f docker-compose.windmill.yml ps
}

# Setup Windmill workspace and flows
setup_windmill_workspace() {
    print_status "Setting up Windmill workspace and flows..."
    
    # Wait a bit more for full initialization
    sleep 5
    
    # Check if CLI is available, if not install it
    if ! command -v wmill &> /dev/null; then
        print_status "Installing Windmill CLI..."
        
        # Try npm install first
        if command -v npm &> /dev/null; then
            npm install -g windmill-cli@$WINDMILL_VERSION || {
                print_warning "npm install failed, trying alternative method..."
                
                # Alternative: download binary
                local os=$(uname -s | tr '[:upper:]' '[:lower:]')
                local arch=$(uname -m)
                case $arch in
                    x86_64) arch="x64" ;;
                    aarch64|arm64) arch="arm64" ;;
                esac
                
                curl -L "https://github.com/windmill-labs/windmill/releases/download/v$WINDMILL_VERSION/wmill-v$WINDMILL_VERSION-$os-$arch" \
                    -o /usr/local/bin/wmill
                chmod +x /usr/local/bin/wmill
            }
        else
            print_error "Neither npm nor curl available for CLI installation"
            return 1
        fi
    fi
    
    # Configure CLI
    wmill workspace add $WINDMILL_WORKSPACE $WINDMILL_WORKSPACE http://localhost:$WINDMILL_PORT --create
    
    # Set as default workspace
    wmill workspace use $WINDMILL_WORKSPACE
    
    print_success "Windmill workspace '$WINDMILL_WORKSPACE' configured"
    
    # Deploy flows if they exist
    if [ -d "$WINDMILL_DIR" ]; then
        print_status "Deploying IDP flows to Windmill..."
        
        cd "$WINDMILL_DIR"
        
        # Install dependencies if package.json exists
        if [ -f "package.json" ]; then
            if command -v npm &> /dev/null; then
                npm install
            elif command -v yarn &> /dev/null; then
                yarn install
            fi
        fi
        
        # Deploy flows (this would typically use wmill sync or similar)
        print_status "Flows deployment requires manual setup - see windmill/README.md for details"
        print_warning "To deploy flows manually:"
        echo "  1. Access Windmill UI at http://localhost:$WINDMILL_PORT"
        echo "  2. Import flows from windmill/flows/ directory"
        echo "  3. Import scripts from windmill/scripts/ directory"
        
        cd "$ROOT_DIR"
    fi
}

# Create startup script
create_startup_script() {
    print_status "Creating Windmill startup script..."
    
    cat > "$SCRIPT_DIR/start-windmill.sh" << 'EOF'
#!/bin/bash

# Start Windmill Services
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

if [ -f ".env.windmill" ]; then
    export $(grep -v '^#' .env.windmill | xargs)
fi

echo "🚀 Starting Windmill services..."
docker-compose -f docker-compose.windmill.yml up -d

echo "⏳ Waiting for Windmill to be ready..."
timeout=60
while [ $timeout -gt 0 ]; do
    if curl -f -s "http://localhost:${WINDMILL_PORT:-8000}/api/version" > /dev/null 2>&1; then
        echo "✅ Windmill is ready!"
        echo ""
        echo "🔗 Access Windmill at: http://localhost:${WINDMILL_PORT:-8000}"
        echo "📚 Workspace: idp"
        echo "🔧 Admin setup required on first access"
        break
    fi
    sleep 2
    ((timeout -= 2))
done

if [ $timeout -le 0 ]; then
    echo "❌ Windmill failed to start within expected time"
    exit 1
fi
EOF

    chmod +x "$SCRIPT_DIR/start-windmill.sh"
    
    # Create stop script
    cat > "$SCRIPT_DIR/stop-windmill.sh" << 'EOF'
#!/bin/bash

# Stop Windmill Services
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

echo "🛑 Stopping Windmill services..."
docker-compose -f docker-compose.windmill.yml down

echo "✅ Windmill services stopped"
EOF

    chmod +x "$SCRIPT_DIR/stop-windmill.sh"
    
    print_success "Windmill management scripts created"
}

# Main setup function
setup_windmill_main() {
    print_header "Windmill Setup for IDP Platform"
    
    # Check prerequisites
    if ! check_prerequisites; then
        print_error "Prerequisites not met. Please install required tools."
        exit 1
    fi
    
    # Create configuration
    create_windmill_config
    create_docker_compose
    
    # Start Windmill
    start_windmill
    
    # Setup workspace
    setup_windmill_workspace
    
    # Create management scripts
    create_startup_script
    
    print_header "Windmill Setup Complete"
    
    echo -e "${GREEN}🎉 Windmill is now running!${NC}\n"
    echo -e "${BLUE}🔗 Access Windmill UI:${NC} http://localhost:$WINDMILL_PORT"
    echo -e "${BLUE}📚 Workspace:${NC} $WINDMILL_WORKSPACE"
    echo -e "${BLUE}🔧 Next Steps:${NC}"
    echo -e "  1. Open http://localhost:$WINDMILL_PORT in your browser"
    echo -e "  2. Complete the initial admin setup"
    echo -e "  3. Import IDP flows from windmill/ directory"
    echo -e "  4. Configure AI agent integration (see windmill/README.md)"
    echo ""
    echo -e "${CYAN}Management Commands:${NC}"
    echo -e "  ${YELLOW}./scripts/start-windmill.sh${NC}  - Start Windmill services"
    echo -e "  ${YELLOW}./scripts/stop-windmill.sh${NC}   - Stop Windmill services"
    echo -e "  ${YELLOW}docker-compose -f docker-compose.windmill.yml logs -f${NC} - View logs"
    echo ""
}

# Command line interface
case "${1:-setup}" in
    "setup")
        setup_windmill_main
        ;;
    "start")
        cd "$ROOT_DIR"
        if [ -f ".env.windmill" ]; then
            export $(grep -v '^#' .env.windmill | xargs)
        fi
        docker-compose -f docker-compose.windmill.yml up -d
        print_success "Windmill services started"
        ;;
    "stop")
        cd "$ROOT_DIR"
        docker-compose -f docker-compose.windmill.yml down
        print_success "Windmill services stopped"
        ;;
    "status")
        cd "$ROOT_DIR"
        docker-compose -f docker-compose.windmill.yml ps
        ;;
    "logs")
        cd "$ROOT_DIR"
        docker-compose -f docker-compose.windmill.yml logs -f
        ;;
    "clean")
        cd "$ROOT_DIR"
        docker-compose -f docker-compose.windmill.yml down -v
        docker volume rm $(docker volume ls -q | grep windmill) 2>/dev/null || true
        print_success "Windmill completely removed"
        ;;
    "help"|"--help")
        echo "Windmill Setup Script for IDP Platform"
        echo ""
        echo "Commands:"
        echo "  setup   - Complete Windmill setup (default)"
        echo "  start   - Start Windmill services"
        echo "  stop    - Stop Windmill services" 
        echo "  status  - Show service status"
        echo "  logs    - Show service logs"
        echo "  clean   - Remove all Windmill data"
        echo "  help    - Show this help"
        ;;
    *)
        print_error "Unknown command: $1"
        print_status "Use 'help' for available commands"
        exit 1
        ;;
esac