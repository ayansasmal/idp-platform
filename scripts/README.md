# IDP Platform Scripts

Streamlined script collection optimized for automation and windmill/idp-agent integration.

## 🎯 Core Scripts (Essential)

### **idp.sh** - Main Platform Orchestrator
Primary script for all platform operations.
```bash
./idp.sh setup                    # Platform setup
./idp.sh start                    # Start services  
./idp.sh stop                     # Stop services
./idp.sh status                   # Platform status
./idp.sh build-backstage          # Build Backstage app
./idp.sh restart                  # Restart platform
```

**Automation-friendly features:**
- JSON output with `--json` flag
- Exit codes: 0=success, 1=error, 2=warning
- Non-interactive mode with environment variables

---

## 🔧 Specialized Scripts

### **auth-management.sh** - Authentication & RBAC
Consolidated authentication management for AWS Cognito and RBAC personas.

```bash
./auth-management.sh setup-full          # Complete auth setup
./auth-management.sh create-personas     # Create test users/groups  
./auth-management.sh status              # Auth system status
./auth-management.sh test-auth           # Test authentication
```

**Key Features:**
- Creates 9 predefined personas with RBAC mapping
- 8 test users with appropriate group memberships
- LocalStack compatible for development

### **infrastructure-setup.sh** - Core Infrastructure  
Manages LocalStack and OPA (Open Policy Agent) setup.

```bash
./infrastructure-setup.sh setup-infrastructure  # Complete setup
./infrastructure-setup.sh status                # Infrastructure status
./infrastructure-setup.sh test-connectivity     # Test services
```

### **configuration-manager.sh** - Configuration Management
Unified configuration management with validation.

```bash
./configuration-manager.sh wizard       # Interactive config wizard
./configuration-manager.sh show         # Display configuration
./configuration-manager.sh export       # Export as env vars
./configuration-manager.sh validate     # Validate config file
```

---

## 🛠️ Utility Scripts

### **health-check.sh** - Health Monitoring
Platform component health validation.
```bash
./health-check.sh                       # Full health check
./health-check.sh --component argocd     # Specific component
./health-check.sh --json                # JSON output
```

### **deploy-workflow-templates.sh** - Argo Workflows
Deploy and manage Argo Workflow templates.
```bash
./deploy-workflow-templates.sh deploy   # Deploy templates
./deploy-workflow-templates.sh status   # Template status
```

### **configure-backstage-repo.sh** - Repository Configuration
Configure Backstage repository integration.
```bash
./configure-backstage-repo.sh setup     # Configure repo
./configure-backstage-repo.sh validate  # Validate setup
```

### **apply-data-protection.sh** - Security Policies
Apply data protection and security policies.
```bash
./apply-data-protection.sh apply        # Apply policies
./apply-data-protection.sh status       # Policy status
```

### **setup-argo-artifacts.sh** - Argo Workflows Storage
Setup S3 storage for Argo Workflows artifacts.
```bash
./setup-argo-artifacts.sh setup        # Setup storage
./setup-argo-artifacts.sh test         # Test connectivity
```

### **uninstall-idp.sh** - Platform Removal
Complete platform uninstallation.
```bash
./uninstall-idp.sh --confirm           # Remove platform
```

---

## 🤖 Windmill/IDP-Agent Compatibility

### **Exit Codes**
All scripts follow standard exit code conventions:
- `0` - Success
- `1` - Error/Failure  
- `2` - Warning (operation succeeded with warnings)
- `3` - Configuration error
- `4` - Dependency missing

### **JSON Output**
Most scripts support `--json` flag for structured output:
```bash
./idp.sh status --json
./health-check.sh --json
./auth-management.sh status --json
```

### **Environment Variables**
Scripts can be configured via environment variables for automation:
```bash
export IDP_PLATFORM_NAME="My Platform"
export IDP_PLATFORM_MODE="production"
export LOCALSTACK_ENDPOINT="http://localhost:4566"
export COGNITO_USER_POOL_NAME="my-user-pool"
```

### **Non-Interactive Modes**
All scripts support non-interactive execution:
```bash
# Skip prompts, use defaults
export IDP_AUTO_CONFIRM=true

# Provide answers via environment
export IDP_PLATFORM_NAME="AutoPlatform"
export IDP_AUTH_PROVIDER="cognito"
```

---

## 📁 File Structure

```
idp-platform/scripts/
├── idp.sh                      # Main orchestrator
├── auth-management.sh          # Authentication & RBAC
├── infrastructure-setup.sh     # LocalStack + OPA
├── configuration-manager.sh    # Configuration management
├── health-check.sh            # Health monitoring
├── deploy-workflow-templates.sh # Argo Workflows
├── configure-backstage-repo.sh # Repository setup
├── apply-data-protection.sh    # Security policies
├── setup-argo-artifacts.sh    # Workflow storage
├── credential-manager.sh       # Credential management
├── uninstall-idp.sh           # Platform removal
└── localstack-idp-config.json # LocalStack config
```

---

## 🗑️ Removed Scripts (Previously Deprecated)

Scripts that were consolidated or removed:
- ~~`bootstrap-platform.sh`~~ → `idp.sh setup`
- ~~`start-platform.sh`~~ → `idp.sh start/stop/status`
- ~~`setup-backstage-external.sh`~~ → `idp.sh build-backstage`
- ~~`setup-cognito-auth.sh`~~ → `auth-management.sh setup-cognito`
- ~~`setup-cognito-personas.sh`~~ → `auth-management.sh create-personas`
- ~~`setup-external-localstack.sh`~~ → `infrastructure-setup.sh setup-localstack`
- ~~`setup-opa.sh`~~ → `infrastructure-setup.sh setup-opa`
- ~~`config-parser.sh`~~ → `configuration-manager.sh parse`
- ~~`idp-setup-wizard.sh`~~ → `configuration-manager.sh wizard`
- ~~`quick-start.sh`~~ → Simple wrapper removed
- ~~`developer-onboarding.sh`~~ → Functionality moved to main scripts
- ~~`idp-cli-mcp.sh`~~ → MCP integration simplified

**Result:** Reduced from **22 scripts** to **11 focused scripts** (50% reduction)

---

## 🚀 Quick Start for Automation

### Complete Platform Setup
```bash
# 1. Setup platform infrastructure
./idp.sh setup

# 2. Setup authentication with personas
./auth-management.sh setup-full

# 3. Verify everything is healthy
./health-check.sh --json

# 4. Start platform services  
./idp.sh start
```

### Status Monitoring
```bash
# Platform overview
./idp.sh status --json

# Infrastructure status
./infrastructure-setup.sh status

# Authentication status  
./auth-management.sh status

# Health check
./health-check.sh --json
```

This streamlined script collection provides all necessary functionality while being optimized for automation, monitoring, and integration with windmill workflows and idp-agent systems.