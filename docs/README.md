# IDP Platform Documentation

Welcome to the Integrated Developer Platform (IDP) documentation! This comprehensive guide covers all aspects of the platform, from quick start to advanced operations.

## 🚀 Quick Start

**New to the platform?** Start here:
1. [Getting Started Guide](tutorials/getting-started.md) - Your first steps with the IDP platform
2. [Access Guide](guides/access-guide.md) - How to access all platform services
3. [Platform Architecture](architecture/platform-architecture.md) - Understanding the platform

## 📚 Documentation Categories

### 🏗️ Architecture & Design

Understand the platform's design and components:

- **[Platform Architecture Overview](architecture/platform-architecture.md)**
  - Complete architecture documentation with AWS Cognito and LocalStack
  - Infrastructure stack, authentication, and hybrid design
  - Platform abstractions and developer experience

- **[Platform Components Overview](architecture/platform-overview.md)**
  - Component-focused architecture documentation
  - Service mesh, observability, and security layers
  - Technology decisions and extensibility

- **[Component Diagrams](architecture/component-diagrams.md)**
  - Visual architecture diagrams
  - Component relationships and data flows

### 🚀 Getting Started & Tutorials

Step-by-step guides for using the platform:

- **[Getting Started Guide](tutorials/getting-started.md)**
  - Platform setup with external LocalStack
  - AWS Cognito authentication
  - Creating your first application
  - Updated platform architecture diagrams

- **[Platform Lifecycle Management](tutorials/platform-lifecycle-management.md)**
  - Installation procedures
  - Platform updates and maintenance
  - Backup and restore procedures
  - Complete uninstall processes
  - Migration procedures

- **[Monitoring & Observability](tutorials/monitoring-observability.md)**
  - Platform health monitoring
  - Authentication service monitoring
  - External LocalStack monitoring
  - Custom dashboards and alerting

- **[Container Builds Guide](tutorials/container-builds-guide.md)**
  - Building and managing containers
  - CI/CD integration with LocalStack ECR

- **[Deploying Applications](tutorials/deploying-applications.md)**
  - Application deployment workflows
  - GitOps deployment patterns

- **[Argo Workflows CI/CD](tutorials/argo-workflows-ci-cd.md)**
  - Advanced CI/CD patterns
  - Workflow automation

### 🛠️ Operations & Runbooks

Operational procedures and troubleshooting:

- **[Platform Operations](runbooks/platform-operations.md)**
  - Day-to-day operational procedures
  - AWS Cognito authentication troubleshooting
  - External LocalStack connectivity debugging
  - Platform health monitoring
  - Incident response procedures

- **[Disaster Recovery](runbooks/disaster-recovery.md)**
  - Backup and recovery procedures
  - Business continuity planning

### 📖 User Guides

End-user documentation:

- **[Services and Capabilities](guides/services-and-capabilities.md)**
  - Complete overview of OOB services and features
  - Platform value proposition and business benefits
  - Service-level commitments and capabilities
  - Use cases and ROI analysis

- **[Access Guide](guides/access-guide.md)**
  - Service access with Cognito authentication
  - Test user accounts and credentials
  - Authentication troubleshooting
  - Platform lifecycle management

### 📈 Platform Status & Implementation

Current status and implementation details:

- **[Platform Status](platform-status/PLATFORM_STATUS.md)**
  - Current implementation status
  - Feature completeness matrix

- **[Implementation Documents](implementation/)**
  - [Argo Workflows Implementation](implementation/ARGO_WORKFLOWS_IMPLEMENTATION.md)
  - [Automation Scripts Update](implementation/AUTOMATION_SCRIPTS_UPDATE.md)
  - [Backstage Real Deployment](implementation/BACKSTAGE_REAL_DEPLOYMENT.md)
  - [Unified Script Improvements](implementation/UNIFIED_SCRIPT_IMPROVEMENTS.md)

## 🔍 Quick References

### Authentication
- **Cognito Test Accounts**: 
  - Admin: `admin` / `TempPassword123!`
  - Developer: `developer` / `TempPassword123!`
- **Service Accounts**: Grafana: admin/admin

### Service Access
- **ArgoCD**: http://localhost:8080 (🔐 Cognito)
- **Backstage**: http://localhost:3000 (🔐 Cognito)
- **Grafana**: http://localhost:3001 (admin/admin)
- **Prometheus**: http://localhost:9090
- **Jaeger**: http://localhost:16686
- **Kiali**: http://localhost:20001
- **LocalStack**: http://localhost:4566

### Platform Commands
```bash
# Quick start
./scripts/setup-external-localstack.sh
./scripts/quick-start.sh

# Platform management
./scripts/start-platform.sh {start|stop|status|health}

# Access shortcuts (after dev-setup.sh)
idp-start          # Start platform
idp-argocd         # Open ArgoCD
idp-backstage      # Open Backstage
idp-grafana        # Open Grafana
```

## 🆘 Getting Help

### Common Issues
1. **Authentication Issues**: See [Platform Operations - Authentication Troubleshooting](runbooks/platform-operations.md#authentication-troubleshooting)
2. **LocalStack Connectivity**: See [Platform Operations - External LocalStack Issues](runbooks/platform-operations.md#external-localstack-issues)
3. **Platform Health**: Run `./scripts/start-platform.sh health`

### Support Channels
- **Documentation**: This comprehensive guide
- **Runbooks**: Operational procedures for common issues
- **Platform Health**: Automated health checking and diagnostics

### Contributing to Documentation
1. All documentation is in Markdown format
2. Follow the existing structure and formatting
3. Update the relevant index files when adding new documentation
4. Test all procedures before documenting them

---

**Platform Version**: Production Ready ✅  
**Documentation Last Updated**: AWS Cognito & External LocalStack Integration  
**Architecture**: Hybrid Kubernetes + AWS Managed Services