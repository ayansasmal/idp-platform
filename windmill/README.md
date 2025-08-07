# IDP Windmill Orchestration

This directory contains Windmill flows and scripts for orchestrating the Integrated Developer Platform (IDP). It provides the automation backbone for the platform with AI agent integration capabilities.

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