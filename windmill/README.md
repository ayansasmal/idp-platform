# IDP Windmill Orchestration

This directory contains Windmill flows and scripts for orchestrating the Integrated Developer Platform (IDP). It provides the automation backbone for the platform with AI agent integration capabilities.

## 🚀 Quick Setup (Zero to Windmill)

**⚠️ Important:** Windmill is not included in the basic IDP setup. Follow these steps to add Windmill orchestration to your platform.

### Prerequisites

Before setting up Windmill, ensure you have a working machine with basic development tools:

```bash
# Option 1: Automated prerequisite installation (recommended)
./scripts/setup-machine.sh setup

# Option 2: Manual verification of existing tools
./scripts/setup-machine.sh verify
```

**Required Tools:**
- Docker Desktop with Kubernetes enabled (or Kind/Minikube)
- Docker Compose v2.0+
- curl, jq, git
- Node.js 16+ with npm/yarn

### Windmill Installation

```bash
# 1. Complete Windmill setup (one command!)
./scripts/setup-windmill.sh setup

# This automatically:
# ✅ Checks prerequisites
# ✅ Creates Docker Compose configuration
# ✅ Starts Windmill services (PostgreSQL + Windmill)
# ✅ Installs Windmill CLI
# ✅ Creates 'idp' workspace
# ✅ Generates management scripts
# ✅ Waits for services to be ready
```

### Verification

```bash
# Check Windmill is running
./scripts/setup-windmill.sh status

# Access Windmill UI
open http://localhost:8000

# Check CLI is working
wmill workspace list
```

### Next Steps

1. **Complete Admin Setup**: Open http://localhost:8000 and create your admin user
2. **Import IDP Flows**: Upload flows from this directory using the Windmill UI
3. **Test Integration**: Run the platform bootstrap flow
4. **Configure AI Agent** (optional): Set up LangChain integration

### Management Commands

```bash
# Service management
./scripts/start-windmill.sh     # Start Windmill services  
./scripts/stop-windmill.sh      # Stop Windmill services
./scripts/setup-windmill.sh status   # Check service status
./scripts/setup-windmill.sh logs     # View service logs
./scripts/setup-windmill.sh clean    # Complete removal

# Workspace management (auto-configured)
wmill workspace use idp         # Switch to IDP workspace
wmill sync pull                 # Download flows from server
wmill sync push                 # Upload local changes
```

**That's it!** Windmill is now running and ready for AI-powered platform management. 🎉

## Overview

The Windmill orchestration layer serves as:
- **Workflow Engine**: Manages complex multi-step platform operations
- **AI Agent Backend**: Provides structured APIs for LangChain-powered agents
- **Async Task Manager**: Handles long-running operations without blocking
- **Integration Bridge**: Connects to existing IDP bash scripts

## Directory Structure

```
windmill/
├── flows/                          # Windmill workflow definitions
│   ├── idp-bootstrap.flow.ts      # Complete platform bootstrap
│   └── platform-operations.flow.ts # Start/stop/monitor operations
├── scripts/                       # Individual Windmill scripts
│   ├── check-prerequisites.ts     # Environment validation
│   ├── setup-infrastructure.ts    # LocalStack & OPA setup
│   ├── setup-authentication.ts    # AWS Cognito configuration
│   ├── setup-platform-core.ts     # Kubernetes core components
│   ├── setup-monitoring.ts        # Observability stack
│   ├── build-backstage.ts         # Backstage build & deploy
│   └── health-check-platform.ts   # Comprehensive health checks
├── integration/                   # Bridge components
│   └── windmill-idp-bridge.ts    # Integration layer with IDP scripts
├── package.json                   # Dependencies and configuration
└── README.md                      # This file
```

## Key Features

### 🚀 Platform Bootstrap Flow
Complete end-to-end platform setup with validation and error handling:
```typescript
// Example bootstrap configuration
{
  platform_name: "IDP Platform",
  environment: "development",
  enable_monitoring: true,
  enable_auth: true,
  skip_backstage: false,
  dry_run: false
}
```

### ⚙️ Platform Operations Flow  
Operational control over platform services:
```typescript
// Example operations
{
  operation: "start",        // start | stop | restart | status | health
  services: ["backstage"],   // Optional: specific services
  comprehensive_health: true,
  dry_run: false
}
```

### 🔗 IDP Script Integration
Seamless integration with existing bash scripts through the bridge layer:
```typescript
// Direct script execution
await idpBridge.setupInfrastructure({
  action: "setup-infrastructure",
  localstack_enabled: true,
  dry_run: false
});

// Async task management
await idpBridge.runAsyncTask(
  "platform-setup",
  "idp.sh", 
  "setup",
  { sync: true }
);
```

## Usage Examples

### 1. Bootstrap Complete Platform
```bash
# Via Windmill API
curl -X POST http://localhost:8000/api/w/idp/jobs/run/f/idp/bootstrap-platform \
  -H "Content-Type: application/json" \
  -d '{
    "environment": "development",
    "enable_monitoring": true,
    "dry_run": false
  }'
```

### 2. Platform Health Check
```bash
# Via Windmill API
curl -X POST http://localhost:8000/api/w/idp/jobs/run/f/idp/platform-operations \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "health",
    "comprehensive_health": true
  }'
```

### 3. Start Platform Services
```bash
# Via Windmill API
curl -X POST http://localhost:8000/api/w/idp/jobs/run/f/idp/platform-operations \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "start",
    "services": ["backstage", "argocd"]
  }'
```

## Integration with IDP-Agent

The Windmill flows are designed for seamless integration with the IDP-Agent (LangChain + AI):

### Agent Tool Integration
```python
# Example LangChain tool integration
from langchain.tools import Tool

def create_windmill_tools():
    return [
        Tool(
            name="bootstrap_platform",
            description="Bootstrap complete IDP platform",
            func=lambda config: call_windmill_flow(
                "f/idp/bootstrap-platform", 
                json.loads(config)
            )
        ),
        Tool(
            name="platform_operations",
            description="Start, stop, restart, or check platform status",
            func=lambda config: call_windmill_flow(
                "f/idp/platform-operations",
                json.loads(config)
            )
        )
    ]
```

### Natural Language Interface
The agent can process requests like:
- "Set up the complete platform for development"
- "Check the health of all platform services"
- "Restart Backstage and check if it's running"
- "Deploy a new version of the monitoring stack"

## Configuration

### Environment Variables
```bash
# Windmill Configuration
export WINDMILL_TOKEN="your-windmill-token"
export WINDMILL_BASE_URL="http://localhost:8000"

# IDP Platform Configuration  
export IDP_ENVIRONMENT="development"
export IDP_SCRIPTS_DIR="/path/to/idp-platform/scripts"
```

### Dependencies
Install required packages:
```bash
cd windmill/
npm install
```

## Development

### Adding New Flows
1. Create new flow in `flows/` directory
2. Follow the existing pattern for error handling and structured results
3. Add integration methods to the bridge if needed
4. Test with both direct execution and via agent

### Script Development
1. Create new script in `scripts/` directory
2. Use proper TypeScript types for parameters and results
3. Handle dry-run mode for testing
4. Provide comprehensive error handling and logging

### Bridge Extensions
1. Add new methods to `WindmillIDPBridge` class
2. Export convenience functions for direct use
3. Ensure proper timeout and error handling
4. Document the integration for agent tools

## Monitoring and Observability

### Flow Execution Tracking
All flows provide structured results with:
- Step-by-step execution tracking
- Timing and performance metrics
- Error details and stack traces
- Service URLs and status information

### Integration with Platform Monitoring
- Flows automatically report status to platform monitoring
- Health checks validate all components
- Recommendations are provided for degraded services
- Full audit trail of all operations

## Best Practices

### Error Handling
- All flows implement comprehensive error handling
- Dry-run mode is supported for testing
- Structured error responses for programmatic handling
- Graceful degradation when possible

### Performance
- Async execution for long-running tasks
- Intelligent timeouts and retries
- Resource usage monitoring
- Caching where appropriate

### Security
- Proper credential management
- Audit logging of all operations
- Role-based access control integration
- Secure communication with all services

## Troubleshooting

### Common Issues

1. **Connection Timeouts**
   - Increase timeout values in flow configuration
   - Check network connectivity to services
   - Verify Kubernetes cluster accessibility

2. **Permission Errors**
   - Ensure proper RBAC configuration
   - Check service account permissions
   - Verify Windmill token permissions

3. **Script Execution Failures**
   - Check script permissions and paths
   - Verify environment variables
   - Review logs in async task manager

### Debug Mode
Enable debug logging:
```bash
export DEBUG=1
export WINDMILL_DEBUG=true
```

### Setup Troubleshooting

**1. "Port 8000 already in use"**
```bash
# Check what's using the port
lsof -ti:8000

# Stop existing Windmill
./scripts/stop-windmill.sh

# Or change the port in .env.windmill
echo "WINDMILL_PORT=8001" >> .env.windmill
```

**2. "Docker Compose command not found"**
```bash
# Check Docker Compose version
docker compose version  # v2 syntax
docker-compose --version  # v1 syntax

# Setup script will detect and use the correct version
./scripts/setup-windmill.sh setup
```

**3. "Windmill CLI not found after setup"**
```bash
# Check if npm is working
npm --version

# Manual CLI installation
npm install -g windmill-cli@1.150.0

# Alternative: Download binary directly (Linux/macOS)
curl -L "https://github.com/windmill-labs/windmill/releases/download/v1.150.0/wmill-v1.150.0-linux-x64" -o /usr/local/bin/wmill
chmod +x /usr/local/bin/wmill
```

**4. "Services won't start"**
```bash
# Check Docker is running
docker info

# Check logs for specific errors
./scripts/setup-windmill.sh logs

# Complete reset
./scripts/setup-windmill.sh clean
./scripts/setup-windmill.sh setup
```

**5. "Can't access Windmill UI"**
```bash
# Wait for services to fully initialize
# Check if Windmill server is ready
curl http://localhost:8000/api/version

# If timeout, check firewall/network settings
# Or try different port in .env.windmill
```

## Future Enhancements

- **Multi-Environment Support**: Cross-environment promotion workflows
- **Advanced Scheduling**: Cron-based maintenance tasks
- **Policy Enforcement**: Automated compliance checks
- **Auto-Remediation**: Self-healing platform capabilities
- **Advanced Analytics**: Platform usage and performance insights

## Contributing

1. Follow the existing code patterns and structure
2. Add comprehensive TypeScript types
3. Include error handling and dry-run support
4. Document new flows and scripts
5. Test with both Windmill direct execution and agent integration

For more information, see the main [IDP Platform Documentation](../README.md).