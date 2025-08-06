# IDP Platform Version Management

This guide covers the comprehensive versioning and rollback capabilities for IDP platform components.

## 🎯 Overview

The IDP Platform now supports independent versioning and rollback for each component, preventing system-wide outages during updates and providing granular control over service lifecycles.

### Key Benefits

- ✅ **Independent Updates** - Update Grafana without affecting Istio
- ✅ **Instant Rollbacks** - Rollback failed updates in seconds
- ✅ **Health Validation** - Automatic validation after updates
- ✅ **Backup & Recovery** - Automatic backup before updates
- ✅ **GitOps Integration** - Leverages ArgoCD for deployment management

## 📊 Component Categories

### Core Infrastructure
- **argocd-platform** - GitOps engine
- **istio-config** - Service mesh
- **crossplane-config** - Infrastructure as Code
- **cert-manager-config** - Certificate management

### Observability Stack  
- **monitoring-stack** - Prometheus + Grafana + Alertmanager
- **tracing-stack** - Jaeger distributed tracing
- **service-mesh-obs** - Kiali service mesh observability

### Platform Services
- **backstage-deployment** - Developer portal
- **argo-workflows** - Internal CI/CD
- **external-secrets** - Secrets management

### Custom Components
- **platform-crds** - Custom Resource Definitions
- **platform-operators** - Custom operators

## 🚀 Quick Start

### List Component Versions
```bash
# List all component versions
./scripts/idp.sh versions

# List specific component versions
./scripts/idp.sh versions monitoring-stack
```

### Update a Component
```bash
# Dry run update (recommended first)
./scripts/idp.sh update monitoring-stack --version 1.1.0 --dry-run

# Actual update
./scripts/idp.sh update monitoring-stack --version 1.1.0

# Update with automatic validation
./scripts/idp.sh update istio-config --version 1.20.1
```

### Rollback a Component
```bash
# Rollback one step
./scripts/idp.sh rollback monitoring-stack

# Rollback multiple steps
./scripts/idp.sh rollback monitoring-stack --steps 2
```

### Check Component Status
```bash
# Check all components
./scripts/idp.sh status

# Check specific component
./scripts/idp.sh status monitoring-stack
```

## 📋 Version Management Workflow

### 1. Pre-Update Planning
```bash
# Check current versions
./scripts/idp.sh versions

# Check component health
./scripts/idp.sh status monitoring-stack

# Plan update with dry-run
./scripts/idp.sh update monitoring-stack --version 1.1.0 --dry-run
```

### 2. Safe Update Process
```bash
# Execute update
./scripts/idp.sh update monitoring-stack --version 1.1.0

# Automatic process:
# ✓ Creates backup of current state
# ✓ Updates ArgoCD application
# ✓ Triggers sync
# ✓ Waits for health validation
# ✓ Updates version manifest
```

### 3. Post-Update Validation
```bash
# Verify component health
./scripts/health-check.sh monitoring-stack

# Check service availability
curl -s http://localhost:3001/api/health  # Grafana health check
```

### 4. Rollback if Needed
```bash
# Quick rollback if update fails
./scripts/idp.sh rollback monitoring-stack

# Monitor rollback progress
kubectl get application monitoring-stack -n argocd -w
```

## 🔧 Advanced Usage

### Version Manifest Structure
The `platform-versions.yaml` file tracks all component versions:

```yaml
spec:
  components:
    observability:
      monitoring-stack:
        current: "1.0.0"
        available: ["1.1.0", "1.0.0", "0.9.5"]
        chart: "charts/observability/monitoring-stack"
        namespace: "monitoring"
        dependencies: []
```

### Custom Health Checks
The system includes component-specific health checks:

- **ArgoCD**: Server API health + sync status
- **Istio**: Control plane pods + proxy injection
- **Monitoring**: Prometheus + Grafana + Alertmanager
- **Backstage**: Application pods + service availability

### Backup and Recovery
- Automatic backup before updates to `.idp-config/backups/`
- ArgoCD application manifests preserved
- Easy restoration from backup files

## 🛠️ Troubleshooting

### Update Fails
```bash
# Check ArgoCD application status
kubectl get application <component> -n argocd

# View ArgoCD application details
kubectl describe application <component> -n argocd

# Check component logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=<component>
```

### Rollback Issues
```bash
# Check revision history
kubectl get application <component> -n argocd -o yaml | grep -A 10 history

# Manual ArgoCD sync
kubectl patch application <component> -n argocd \\
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type merge
```

### Health Check Failures
```bash
# Run detailed health check
./scripts/health-check.sh <component>

# Check pod status
kubectl get pods -n <namespace>

# View pod logs
kubectl logs -n <namespace> <pod-name>
```

## 🔄 Integration with GitOps

### ArgoCD Integration
- Updates modify ArgoCD application `targetRevision`
- Automatic sync policies ensure deployment
- Rollbacks use ArgoCD revision history
- Health status from ArgoCD application health

### Helm Chart Integration
```bash
# Chart structure
charts/observability/monitoring-stack/
├── Chart.yaml          # Chart version and metadata
├── values.yaml         # Default configuration
├── templates/          # Kubernetes manifests
└── CHANGELOG.md        # Version history
```

### Git Workflow
```bash
# Version updates tracked in Git
git log --oneline platform-versions.yaml

# Component updates create Git history
git show <commit>  # View version change details
```

## 📚 Best Practices

### 1. Update Strategy
- Always run dry-run first
- Update non-critical components first
- Monitor component health after updates
- Have rollback plan ready

### 2. Version Planning
- Review changelog before updating
- Check component dependencies
- Test in staging environment
- Schedule updates during maintenance windows

### 3. Health Monitoring
- Use health checks after updates
- Monitor component logs
- Verify service availability
- Check downstream dependencies

### 4. Rollback Strategy
- Rollback immediately if health checks fail
- Monitor rollback completion
- Investigate root cause after rollback
- Plan remediation for next update cycle

## 🚨 Emergency Procedures

### Quick Component Rollback
```bash
# Emergency rollback (fastest)
./scripts/idp.sh rollback <component>

# Check rollback status
./scripts/idp.sh status <component>
```

### Manual Recovery
```bash
# If automated rollback fails
kubectl patch application <component> -n argocd \\
  --patch-file /path/to/backup.yaml

# Force ArgoCD sync
kubectl patch application <component> -n argocd \\
  -p '{"operation":{"sync":{}}}' --type merge
```

### Platform-wide Recovery
```bash
# Check all component health
./scripts/health-check.sh

# Rollback multiple components if needed
./scripts/idp.sh rollback istio-config
./scripts/idp.sh rollback monitoring-stack
./scripts/idp.sh rollback backstage-deployment
```

This versioning system provides enterprise-grade component lifecycle management while maintaining the simplicity of the unified IDP platform! 🚀