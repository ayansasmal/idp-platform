#!/bin/bash

# Configure Backstage Repository URL
# Helper script to update all references to the external Backstage repository

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Configure Backstage Repository URL                ║"
echo "║                                                              ║"
echo "║  🔗 Update platform to use your GitHub Backstage repo      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to print status
print_status() {
    echo -e "${BLUE}[CONFIG]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get repository URL from user
if [ -n "$1" ]; then
    REPO_URL="$1"
else
    echo -e "${YELLOW}Enter your Backstage repository URL:${NC}"
    echo -e "${BLUE}Examples:${NC}"
    echo -e "  • https://github.com/username/idp-backstage-app.git"
    echo -e "  • git@github.com:username/idp-backstage-app.git"
    echo ""
    read -p "Repository URL: " REPO_URL
fi

# Validate URL
if [ -z "$REPO_URL" ]; then
    print_error "Repository URL cannot be empty"
    exit 1
fi

# Remove .git suffix if present for consistent formatting
REPO_URL_NO_GIT="${REPO_URL%.git}"
REPO_URL_WITH_GIT="${REPO_URL_NO_GIT}.git"

print_status "Configuring platform to use: $REPO_URL_WITH_GIT"

# Update setup-backstage-external.sh
SETUP_SCRIPT="$SCRIPT_DIR/setup-backstage-external.sh"
if [ -f "$SETUP_SCRIPT" ]; then
    print_status "Updating setup-backstage-external.sh..."
    
    # Create backup
    cp "$SETUP_SCRIPT" "$SETUP_SCRIPT.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update the repository URL
    sed -i.tmp "s|BACKSTAGE_REPO_URL=\"\${BACKSTAGE_REPO_URL:-.*}\"$|BACKSTAGE_REPO_URL=\"\${BACKSTAGE_REPO_URL:-$REPO_URL_WITH_GIT}\"|g" "$SETUP_SCRIPT"
    rm "$SETUP_SCRIPT.tmp"
    
    print_success "Updated setup-backstage-external.sh"
else
    print_error "setup-backstage-external.sh not found at $SETUP_SCRIPT"
fi

# Update Argo Workflow
WORKFLOW_FILE="$ROOT_DIR/platform/workflows/stable-backstage-build.yaml"
if [ -f "$WORKFLOW_FILE" ]; then
    print_status "Updating Argo Workflow configuration..."
    
    # Create backup
    cp "$WORKFLOW_FILE" "$WORKFLOW_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update the repository URL (without .git suffix for Argo)
    sed -i.tmp "s|value: \"https://github.com/.*$|value: \"$REPO_URL_NO_GIT\"|g" "$WORKFLOW_FILE"
    rm "$WORKFLOW_FILE.tmp"
    
    print_success "Updated Argo Workflow configuration"
else
    print_error "Argo Workflow file not found at $WORKFLOW_FILE"
fi

# Update IDP setup wizard default
WIZARD_SCRIPT="$SCRIPT_DIR/idp-setup-wizard.sh"
if [ -f "$WIZARD_SCRIPT" ]; then
    print_status "Updating setup wizard default repository..."
    
    # Create backup
    cp "$WIZARD_SCRIPT" "$WIZARD_SCRIPT.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update default repository URL in the wizard
    sed -i.tmp "s|https://github.com/ayansasmal/idp-backstage-app.git|$REPO_URL_WITH_GIT|g" "$WIZARD_SCRIPT"
    rm "$WIZARD_SCRIPT.tmp"
    
    print_success "Updated setup wizard default repository"
else
    print_error "Setup wizard not found at $WIZARD_SCRIPT"
fi

# Update any configuration files
CONFIG_FILE="$ROOT_DIR/.idp-config/idp-config.yaml"
if [ -f "$CONFIG_FILE" ]; then
    print_status "Updating existing configuration..."
    
    # Create backup
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add or update backstage repository configuration
    if grep -q "backstage_repository:" "$CONFIG_FILE"; then
        sed -i.tmp "s|backstage_repository:.*$|backstage_repository: $REPO_URL_WITH_GIT|g" "$CONFIG_FILE"
    else
        echo "" >> "$CONFIG_FILE"
        echo "# External Backstage Repository" >> "$CONFIG_FILE"
        echo "backstage_repository: $REPO_URL_WITH_GIT" >> "$CONFIG_FILE"
    fi
    rm "$CONFIG_FILE.tmp"
    
    print_success "Updated existing configuration"
fi

echo ""
echo -e "${GREEN}🎉 Repository configuration completed successfully!${NC}"
echo ""
echo -e "${BLUE}Updated Files:${NC}"
echo -e "  • ${YELLOW}scripts/setup-backstage-external.sh${NC} - Main integration script"
echo -e "  • ${YELLOW}platform/workflows/stable-backstage-build.yaml${NC} - Argo Workflow"
echo -e "  • ${YELLOW}scripts/idp-setup-wizard.sh${NC} - Setup wizard default"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "  • ${YELLOW}.idp-config/idp-config.yaml${NC} - Platform configuration"
fi
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo -e "  1. Test the configuration: ${YELLOW}./scripts/setup-backstage-external.sh${NC}"
echo -e "  2. Run the platform: ${YELLOW}./scripts/quick-start.sh${NC}"
echo ""
echo -e "${BLUE}Repository Information:${NC}"
echo -e "  • Repository URL: ${GREEN}$REPO_URL_WITH_GIT${NC}"
echo -e "  • Clone URL: ${GREEN}$REPO_URL_NO_GIT${NC}"
echo ""
echo -e "${YELLOW}Note: All original files have been backed up with timestamp suffixes.${NC}"