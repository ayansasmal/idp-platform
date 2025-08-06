#!/bin/bash

# IDP Platform Quick Start Script
# Simplified wrapper for the unified IDP script

# Colors
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    IDP Platform Quick Start                 ║"
echo "║                                                              ║"
echo "║  🚀 Starting your Integrated Developer Platform...          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}💡 Quick Start is now unified in the main IDP script${NC}"
echo -e "${YELLOW}   Running: ./scripts/idp.sh start${NC}\n"

# Check if platform is set up
if ! kubectl get namespace argocd &> /dev/null; then
    echo -e "${YELLOW}⚠️  Platform not set up yet. Running setup first...${NC}"
    "$SCRIPT_DIR/idp.sh" setup
fi

# Start the platform
exec "$SCRIPT_DIR/idp.sh" start