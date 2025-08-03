# IDP Platform Lifecycle Management

## Overview

This guide covers the complete lifecycle management of the IDP platform, including installation, updates, backup, restore, and uninstallation procedures. The platform is designed with lifecycle management in mind, providing automated scripts and clear procedures for all operational phases.

## Table of Contents

1. [Platform Installation](#platform-installation)
2. [Platform Updates and Maintenance](#platform-updates-and-maintenance)
3. [Backup and Restore](#backup-and-restore)
4. [Platform Uninstallation](#platform-uninstallation)
5. [Migration Procedures](#migration-procedures)
6. [Disaster Recovery](#disaster-recovery)

## Platform Installation

### Prerequisites

Before installing the IDP platform, ensure you have:

- **Docker Desktop** with Kubernetes enabled
- **kubectl** CLI tool configured
- **awslocal** CLI tool (installed automatically by setup scripts)
- **Git** for repository operations
- **curl** and **jq** for API operations

### Fresh Installation

#### Step 1: External Dependencies Setup

```bash
# Clone the IDP platform repository
git clone <idp-platform-repo>
cd idp-platform

# Setup external LocalStack for development
./scripts/setup-external-localstack.sh
```

This script will:
- Install required dependencies (awslocal, jq, curl)
- Configure AWS CLI for LocalStack
- Start external LocalStack container
- Validate service connectivity
- Create IDP-specific LocalStack configuration

#### Step 2: Platform Deployment

```bash
# Quick start - deploys entire platform
./scripts/quick-start.sh
```

This comprehensive script will:
- Validate external dependencies (LocalStack, Docker, kubectl)
- Deploy all platform components via ArgoCD
- Setup external service discovery
- Configure authentication (AWS Cognito)
- Setup monitoring and observability
- Establish automatic port forwarding
- Validate platform health

#### Step 3: Verification

```bash
# Check platform health
./scripts/start-platform.sh health

# Verify all services are accessible
curl -s http://localhost:8080  # ArgoCD
curl -s http://localhost:3000  # Backstage
curl -s http://localhost:3001  # Grafana
curl -s http://localhost:4566/_localstack/health  # LocalStack
```

### Development Environment Setup

```bash
# One-time development environment setup
./scripts/dev-setup.sh
```

This creates convenient aliases:
- `idp-start` - Start platform
- `idp-stop` - Stop platform
- `idp-status` - Check platform status
- `idp-health` - Run health checks
- `idp-argocd` - Open ArgoCD
- `idp-backstage` - Open Backstage
- `idp-grafana` - Open Grafana

## Platform Updates and Maintenance

### Component Updates

#### ArgoCD Updates

```bash
# Check current ArgoCD version
kubectl get deployment argocd-server -n argocd -o yaml | grep image:

# Update ArgoCD via GitOps
git pull origin main
kubectl apply -f applications/argocd/

# Verify update
kubectl rollout status deployment/argocd-server -n argocd
```

#### Istio Updates

```bash
# Check current Istio version
istioctl version

# Download new Istio version
curl -L https://istio.io/downloadIstio | sh -
cd istio-<version>
export PATH=$PWD/bin:$PATH

# Upgrade Istio control plane
istioctl upgrade

# Restart data plane components
kubectl rollout restart deployment --all -n development
kubectl rollout restart deployment --all -n staging
kubectl rollout restart deployment --all -n production

# Verify upgrade
istioctl proxy-status
```

#### Crossplane Updates

```bash
# Check current Crossplane version
kubectl get deployment crossplane -n crossplane-system -o yaml | grep image:

# Update via GitOps
git pull origin main
kubectl apply -f applications/platform/

# Verify providers are healthy
kubectl get providers
kubectl get compositeresourcedefinitions
```

#### External LocalStack Updates

```bash
# Update LocalStack container
docker pull localstack/localstack:latest

# Restart with new image
docker stop localstack-idp
docker rm localstack-idp
./scripts/setup-external-localstack.sh

# Verify services
curl -s http://localhost:4566/_localstack/health | jq '.services'
```

### Platform Configuration Updates

#### Authentication Configuration

```bash
# Update Cognito configuration
kubectl apply -f infrastructure/aws/cognito-stack.yaml

# Update JWT policies
kubectl apply -f infrastructure/istio/jwt-policy.yaml

# Restart affected services
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/backstage -n backstage
```

#### Monitoring Configuration

```bash
# Update monitoring configuration
kubectl apply -f applications/monitoring/

# Restart monitoring components
kubectl rollout restart deployment/prometheus-server -n istio-system
kubectl rollout restart deployment/grafana -n istio-system
```

## Backup and Restore

### What to Backup

#### Git Repositories (Primary Backup)
The platform follows GitOps principles, so Git repositories are the primary source of truth:

```bash
# Backup configuration repositories
git clone --mirror <idp-config-repo> idp-config-backup.git
git clone --mirror <application-repos> app-repos-backup.git

# Create tarball backup
tar -czf idp-git-backup-$(date +%Y%m%d).tar.gz *.git
```

#### Kubernetes Secrets

```bash
# Export all secrets (encrypted storage recommended)
kubectl get secrets --all-namespaces -o yaml > secrets-backup-$(date +%Y%m%d).yaml

# Encrypt backup
gpg --symmetric --cipher-algo AES256 secrets-backup-$(date +%Y%m%d).yaml
rm secrets-backup-$(date +%Y%m%d).yaml

# Store encrypted backup securely
mv secrets-backup-$(date +%Y%m%d).yaml.gpg /secure/backup/location/
```

#### Persistent Data

```bash
# LocalStack data (development)
tar -czf localstack-data-$(date +%Y%m%d).tar.gz ${TMPDIR:-/tmp}/localstack

# Application data (if any persistent volumes)
kubectl get pv
# Create volume snapshots based on storage provider
```

#### Platform Configuration

```bash
# Export platform configurations
mkdir -p backup/platform-config-$(date +%Y%m%d)

# Export key configurations
kubectl get configmaps --all-namespaces -o yaml > backup/platform-config-$(date +%Y%m%d)/configmaps.yaml
kubectl get crds -o yaml > backup/platform-config-$(date +%Y%m%d)/crds.yaml
kubectl get applications -n argocd -o yaml > backup/platform-config-$(date +%Y%m%d)/applications.yaml

# Create tarball
tar -czf platform-config-backup-$(date +%Y%m%d).tar.gz backup/platform-config-$(date +%Y%m%d)
```

### Automated Backup Script

```bash
#!/bin/bash
# backup-platform.sh

set -euo pipefail

BACKUP_DIR="/secure/backup/idp-platform"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${DATE}"

mkdir -p "${BACKUP_PATH}"

echo "Creating IDP Platform backup: ${DATE}"

# 1. Git repositories
echo "Backing up Git repositories..."
git clone --mirror <idp-config-repo> "${BACKUP_PATH}/idp-config.git"

# 2. Kubernetes secrets
echo "Backing up Kubernetes secrets..."
kubectl get secrets --all-namespaces -o yaml > "${BACKUP_PATH}/secrets.yaml"
gpg --symmetric --cipher-algo AES256 "${BACKUP_PATH}/secrets.yaml"
rm "${BACKUP_PATH}/secrets.yaml"

# 3. Platform configuration
echo "Backing up platform configuration..."
kubectl get configmaps --all-namespaces -o yaml > "${BACKUP_PATH}/configmaps.yaml"
kubectl get applications -n argocd -o yaml > "${BACKUP_PATH}/applications.yaml"
kubectl get crds -o yaml > "${BACKUP_PATH}/crds.yaml"

# 4. LocalStack data
echo "Backing up LocalStack data..."
tar -czf "${BACKUP_PATH}/localstack-data.tar.gz" ${TMPDIR:-/tmp}/localstack

# 5. Create manifest
echo "Creating backup manifest..."
cat > "${BACKUP_PATH}/manifest.yaml" << EOF
backup:
  date: ${DATE}
  platform_version: $(kubectl get deployment argocd-server -n argocd -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}')
  kubernetes_version: $(kubectl version --short --client | grep Client)
  git_commit: $(git rev-parse HEAD)
  components:
    - git_repositories
    - kubernetes_secrets
    - platform_configuration
    - localstack_data
EOF

echo "Backup completed: ${BACKUP_PATH}"
```

### Restore Procedures

#### Complete Platform Restore

```bash
#!/bin/bash
# restore-platform.sh

BACKUP_DATE=$1
BACKUP_PATH="/secure/backup/idp-platform/${BACKUP_DATE}"

if [[ ! -d "${BACKUP_PATH}" ]]; then
    echo "Backup not found: ${BACKUP_PATH}"
    exit 1
fi

echo "Restoring IDP Platform from backup: ${BACKUP_DATE}"

# 1. Ensure clean environment
./scripts/uninstall-idp.sh --yes

# 2. Restore Git repositories
echo "Restoring Git repositories..."
git clone "${BACKUP_PATH}/idp-config.git" idp-platform
cd idp-platform

# 3. Setup external dependencies
./scripts/setup-external-localstack.sh

# 4. Restore LocalStack data
echo "Restoring LocalStack data..."
docker stop localstack-idp
tar -xzf "${BACKUP_PATH}/localstack-data.tar.gz" -C /
docker start localstack-idp

# 5. Deploy platform
./scripts/quick-start.sh

# 6. Restore secrets
echo "Restoring secrets..."
gpg --decrypt "${BACKUP_PATH}/secrets.yaml.gpg" | kubectl apply -f -

# 7. Verify restore
./scripts/start-platform.sh health

echo "Platform restore completed"
```

## Platform Uninstallation

### Complete Uninstall

The platform provides a comprehensive uninstall script that safely removes all IDP resources while preserving external dependencies:

```bash
# Preview what will be removed
./scripts/uninstall-idp.sh --dry-run

# Complete uninstall
./scripts/uninstall-idp.sh --yes
```

#### What Gets Removed

**Kubernetes Resources:**
- All IDP platform namespaces (argocd, backstage, istio-system, etc.)
- Custom Resource Definitions (CRDs)
- Platform-specific configurations
- Application deployments and services

**Docker Resources:**
- IDP-related container images
- LocalStack ECR repositories (IDP workloads only)
- Stopped containers from IDP deployments

**Generated Files:**
- Port forward PID files
- Temporary configuration files

#### What Gets Preserved

**External Dependencies:**
- Docker Desktop Kubernetes cluster
- External LocalStack installation and data
- System tools (awslocal, kubectl, docker)
- AWS CLI configuration
- Non-IDP docker images

**Manual Cleanup Required:**
- Kind clusters: `kind delete cluster --name <cluster-name>`
- Minikube: `minikube delete`
- External clusters: Manual cleanup required

### Selective Uninstall

#### Remove Specific Components

```bash
# Remove only monitoring stack
kubectl delete -f applications/monitoring/

# Remove authentication components
kubectl delete -f infrastructure/aws/cognito-stack.yaml
kubectl delete -f infrastructure/istio/jwt-policy.yaml

# Remove specific applications
kubectl delete application <app-name> -n argocd
```

#### Namespace-Specific Cleanup

```bash
# Remove development environment only
kubectl delete namespace development

# Clean up staging environment
kubectl delete namespace staging
```

## Migration Procedures

### Environment Migration

#### Local to Cloud Migration

```bash
# 1. Backup local environment
./backup-platform.sh

# 2. Prepare cloud environment
# - Setup AWS EKS cluster
# - Configure AWS Cognito (production)
# - Setup AWS RDS, S3, Secrets Manager

# 3. Update configurations for cloud
# Update infrastructure/crossplane/providers/ to use AWS instead of LocalStack
# Update authentication configuration for production Cognito

# 4. Deploy to cloud
kubectl apply -f applications/argocd/
```

#### Version Migration

```bash
# 1. Create backup
./backup-platform.sh

# 2. Update Git repository
git pull origin main

# 3. Apply updates via GitOps
kubectl apply -f applications/

# 4. Monitor rollout
kubectl rollout status deployment --all -n argocd
kubectl rollout status deployment --all -n backstage
kubectl rollout status deployment --all -n istio-system
```

### Data Migration

#### Database Migration (LocalStack to AWS RDS)

```bash
# 1. Export data from LocalStack
awslocal rds describe-db-instances
# Use database-specific export tools

# 2. Create AWS RDS instance
kubectl apply -f infrastructure/crossplane/claims/database-claims.yaml

# 3. Import data to AWS RDS
# Use database-specific import tools

# 4. Update application configurations
kubectl patch configmap backstage-config -n backstage --patch-file db-migration-patch.yaml
```

## Disaster Recovery

### Recovery Time Objectives (RTO)

- **Platform Infrastructure**: 1 hour
- **Critical Applications**: 30 minutes
- **Non-critical Applications**: 4 hours
- **Full Data Recovery**: 2 hours

### Recovery Point Objectives (RPO)

- **Configuration Data**: 0 (Git-based)
- **Application Data**: 15 minutes (with automated backups)
- **Secrets**: 1 hour (encrypted backups)

### Disaster Scenarios

#### Complete Cluster Failure

```bash
# 1. Create new cluster (Docker Desktop/EKS)
# For Docker Desktop: Reset Kubernetes cluster
# For EKS: eksctl create cluster --config-file cluster-config.yaml

# 2. Setup external dependencies
./scripts/setup-external-localstack.sh

# 3. Restore from backup
./restore-platform.sh <backup-date>

# 4. Verify all services
./scripts/start-platform.sh health
```

#### Partial Service Failure

```bash
# 1. Identify failed components
kubectl get pods --all-namespaces | grep -v Running

# 2. Restart failed services
kubectl rollout restart deployment/<failed-deployment> -n <namespace>

# 3. Check for configuration issues
kubectl describe pod <failed-pod> -n <namespace>
kubectl logs <failed-pod> -n <namespace>
```

#### Data Corruption

```bash
# 1. Stop affected services
kubectl scale deployment <affected-deployment> --replicas=0 -n <namespace>

# 2. Restore data from backup
# Use backup-specific restore procedures

# 3. Restart services
kubectl scale deployment <affected-deployment> --replicas=<original-count> -n <namespace>

# 4. Verify data integrity
# Run application-specific health checks
```

### Recovery Testing

#### Regular DR Drills

```bash
#!/bin/bash
# dr-drill.sh - Disaster Recovery Drill

echo "Starting DR Drill: $(date)"

# 1. Create test backup
./backup-platform.sh

# 2. Simulate disaster (in test environment only)
if [[ "${ENVIRONMENT}" == "test" ]]; then
    ./scripts/uninstall-idp.sh --yes
fi

# 3. Restore from backup
./restore-platform.sh $(date +%Y%m%d-%H%M%S)

# 4. Verify recovery
./scripts/start-platform.sh health

# 5. Run smoke tests
curl -f http://localhost:8080/healthz  # ArgoCD
curl -f http://localhost:3000/api/health  # Backstage

echo "DR Drill completed: $(date)"
```

## Best Practices

### Lifecycle Management

1. **Regular Backups**: Schedule daily automated backups
2. **Version Control**: All configuration changes through Git
3. **Testing**: Test all procedures in non-production environments
4. **Documentation**: Keep runbooks updated with any procedural changes
5. **Monitoring**: Set up alerts for backup failures and system health

### Security Considerations

1. **Encrypted Backups**: All backups should be encrypted
2. **Access Control**: Limit access to backup and restore procedures
3. **Audit Trail**: Log all lifecycle operations
4. **Secret Rotation**: Regular rotation of authentication secrets

### Operational Excellence

1. **Automation**: Automate repetitive lifecycle tasks
2. **Validation**: Always validate operations with health checks
3. **Rollback Plans**: Have rollback procedures for all changes
4. **Communication**: Clear communication during maintenance windows

This comprehensive lifecycle management guide ensures reliable operation of the IDP platform throughout its entire lifecycle, from initial installation through maintenance, updates, and eventual decommissioning.