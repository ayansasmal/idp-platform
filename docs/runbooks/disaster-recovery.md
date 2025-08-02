# IDP Platform Disaster Recovery Runbook

## Overview

This runbook provides comprehensive disaster recovery procedures for the IDP platform. It covers various disaster scenarios and step-by-step recovery procedures to restore platform functionality.

## Recovery Objectives

- **RTO (Recovery Time Objective)**: 1 hour for critical services
- **RPO (Recovery Point Objective)**: 15 minutes data loss maximum
- **Availability Target**: 99.9% uptime

## Disaster Classifications

### Level 1: Service Degradation
- Single service failure
- Partial functionality loss
- **Response Time**: 15 minutes
- **Recovery Time**: 30 minutes

### Level 2: Major Outage
- Multiple service failures
- Significant functionality loss
- **Response Time**: 5 minutes
- **Recovery Time**: 1 hour

### Level 3: Complete Platform Failure
- Total platform unavailability
- All services down
- **Response Time**: Immediate
- **Recovery Time**: 4 hours

## Pre-Disaster Preparation

### 1. Backup Verification

```bash
#!/bin/bash
# Daily backup verification script

echo "=== IDP Platform Backup Verification ==="
echo "Date: $(date)"

# Check Git repository backups
echo "Checking Git repositories..."
git ls-remote https://github.com/company/idp-platform.git
git ls-remote https://github.com/company/idp-applications.git

# Check container registry backups
echo "Checking container registries..."
aws ecr describe-repositories --region us-west-2
aws ecr list-images --repository-name idp-platform --region us-west-2

# Check database backups
echo "Checking database backups..."
aws rds describe-db-snapshots --db-instance-identifier idp-prod

# Check persistent volume snapshots
echo "Checking volume snapshots..."
aws ec2 describe-snapshots --owner-ids self --filters "Name=tag:Environment,Values=production"

# Check secrets backup
echo "Checking secrets backup..."
aws secretsmanager list-secrets --filters Key=tag-key,Values=Environment Key=tag-value,Values=production

echo "=== Backup Verification Complete ==="
```

### 2. Infrastructure as Code Validation

```bash
#!/bin/bash
# Infrastructure validation script

echo "=== Infrastructure Validation ==="

# Validate Crossplane configurations
kubectl get providers
kubectl get compositeresourcedefinitions
kubectl get compositions

# Validate ArgoCD applications
argocd app list
argocd app get platform-infrastructure
argocd app get platform-applications

# Validate Istio configuration
istioctl analyze --all-namespaces

echo "=== Infrastructure Validation Complete ==="
```

## Disaster Detection

### Automated Monitoring

The platform monitors these critical indicators:

1. **Platform Health Checks**
   - Kubernetes API server availability
   - ArgoCD synchronization status
   - Istio control plane health

2. **Application Health Checks**
   - HTTP endpoint availability
   - Database connectivity
   - Service mesh communication

3. **Infrastructure Health Checks**
   - Node availability
   - Persistent volume status
   - Network connectivity

### Alert Thresholds

```yaml
# Platform alerts configuration
platform_down_threshold: "All platform components unavailable for > 2 minutes"
service_degradation_threshold: "Error rate > 5% for > 5 minutes"
infrastructure_failure_threshold: "Node count < 50% for > 1 minute"
```

## Recovery Procedures

### Level 1: Service Degradation Recovery

#### Single Pod/Service Failure

```bash
#!/bin/bash
# Single service recovery procedure

SERVICE_NAME="$1"
NAMESPACE="$2"

echo "=== Recovering Service: $SERVICE_NAME in $NAMESPACE ==="

# 1. Check service status
kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME

# 2. Check logs for errors
kubectl logs -n $NAMESPACE -l app=$SERVICE_NAME --tail=100

# 3. Restart service
kubectl rollout restart deployment/$SERVICE_NAME -n $NAMESPACE

# 4. Verify recovery
kubectl rollout status deployment/$SERVICE_NAME -n $NAMESPACE

# 5. Run health checks
kubectl exec -n $NAMESPACE deploy/$SERVICE_NAME -- curl -f http://localhost:8080/health

echo "=== Service Recovery Complete ==="
```

#### Database Connection Issues

```bash
#!/bin/bash
# Database connectivity recovery

echo "=== Database Recovery Procedure ==="

# 1. Check database pods
kubectl get pods -n production -l app=postgresql

# 2. Check database connections
kubectl exec -n production deploy/postgresql -- pg_isready

# 3. Check connection pool status
kubectl logs -n production -l app=pgbouncer

# 4. Restart connection pool if needed
kubectl rollout restart deployment/pgbouncer -n production

# 5. Verify application connectivity
for app in web-app api-service; do
    kubectl exec -n production deploy/$app -- nc -zv postgresql 5432
done

echo "=== Database Recovery Complete ==="
```

### Level 2: Major Outage Recovery

#### Multiple Service Failures

```bash
#!/bin/bash
# Major outage recovery procedure

echo "=== Major Outage Recovery ==="

# 1. Assess scope of failure
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

# 2. Check platform components
kubectl get pods -n istio-system
kubectl get pods -n argocd
kubectl get pods -n crossplane-system

# 3. Restart core services first
kubectl rollout restart deployment/istiod -n istio-system
kubectl rollout restart deployment/argocd-application-controller -n argocd
kubectl rollout restart deployment/crossplane -n crossplane-system

# 4. Wait for core services
kubectl wait --for=condition=available --timeout=300s deployment/istiod -n istio-system
kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n argocd

# 5. Sync all applications
argocd app sync --all

# 6. Verify platform health
./scripts/health-check.sh

echo "=== Major Outage Recovery Complete ==="
```

#### Network Partition Recovery

```bash
#!/bin/bash
# Network partition recovery

echo "=== Network Partition Recovery ==="

# 1. Check node connectivity
kubectl get nodes -o wide
kubectl describe nodes | grep Conditions -A 5

# 2. Check service mesh connectivity
istioctl proxy-status

# 3. Restart network components
kubectl delete pods -n kube-system -l k8s-app=kube-proxy
kubectl delete pods -n istio-system -l app=istio-proxy

# 4. Verify connectivity
kubectl run network-test --image=busybox --rm -it --restart=Never -- /bin/sh -c "
  nslookup kubernetes.default &&
  wget -qO- http://istio-proxy.istio-system:15000/ready
"

echo "=== Network Recovery Complete ==="
```

### Level 3: Complete Platform Failure Recovery

#### Cluster Recreation from Backup

```bash
#!/bin/bash
# Complete cluster recovery procedure

echo "=== Complete Platform Recovery ==="

# 1. Create new cluster
echo "Creating new Kubernetes cluster..."
eksctl create cluster --config-file infrastructure/eks-cluster.yaml

# 2. Install core components
echo "Installing core platform components..."

# Install Crossplane
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --create-namespace

# Install Istio
istioctl install --set values.defaultRevision=default -y

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace

# 3. Restore infrastructure configuration
echo "Restoring infrastructure configuration..."
kubectl apply -f infrastructure/crossplane/
kubectl apply -f infrastructure/istio/
kubectl apply -f secrets/

# 4. Install ArgoCD
echo "Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# 5. Configure ArgoCD applications
echo "Configuring ArgoCD applications..."
kubectl apply -f applications/argocd/applications/

# 6. Sync all applications
echo "Synchronizing applications..."
argocd app sync --all

# 7. Install monitoring stack
echo "Installing monitoring stack..."
kubectl apply -f applications/monitoring/

# 8. Verify platform health
echo "Verifying platform health..."
./scripts/platform-health-check.sh

echo "=== Complete Platform Recovery Finished ==="
```

#### Data Recovery from Snapshots

```bash
#!/bin/bash
# Data recovery from snapshots

echo "=== Data Recovery from Snapshots ==="

# 1. List available snapshots
aws ec2 describe-snapshots --owner-ids self --filters "Name=tag:Environment,Values=production"

# 2. Create volumes from snapshots
SNAPSHOT_ID="$1"
AVAILABILITY_ZONE="us-west-2a"

VOLUME_ID=$(aws ec2 create-volume \
  --snapshot-id $SNAPSHOT_ID \
  --availability-zone $AVAILABILITY_ZONE \
  --volume-type gp3 \
  --query 'VolumeId' --output text)

echo "Created volume: $VOLUME_ID"

# 3. Create PersistentVolume
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: recovered-data-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: $VOLUME_ID
EOF

# 4. Create PersistentVolumeClaim
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: recovered-data-pvc
  namespace: production
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  volumeName: recovered-data-pv
EOF

echo "=== Data Recovery Complete ==="
```

### Database Recovery

#### PostgreSQL Recovery

```bash
#!/bin/bash
# PostgreSQL database recovery

echo "=== PostgreSQL Recovery ==="

# 1. Get latest database snapshot
SNAPSHOT_IDENTIFIER=$(aws rds describe-db-snapshots \
  --db-instance-identifier idp-prod-postgres \
  --snapshot-type automated \
  --query 'DBSnapshots[0].DBSnapshotIdentifier' \
  --output text)

echo "Latest snapshot: $SNAPSHOT_IDENTIFIER"

# 2. Restore database from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier idp-prod-postgres-recovered \
  --db-snapshot-identifier $SNAPSHOT_IDENTIFIER \
  --db-instance-class db.t3.medium

# 3. Wait for database to be available
aws rds wait db-instance-available --db-instance-identifier idp-prod-postgres-recovered

# 4. Get new database endpoint
DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier idp-prod-postgres-recovered \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# 5. Update database connection secrets
kubectl patch secret postgres-credentials -n production --patch="{\"data\":{\"host\":\"$(echo -n $DB_ENDPOINT | base64)\"}}"

# 6. Restart applications to pick up new endpoint
kubectl rollout restart deployment --all -n production

echo "=== PostgreSQL Recovery Complete ==="
```

## Communication Plan

### Incident Communication Template

```
SUBJECT: IDP Platform Incident - [SEVERITY] - [STATUS]

INCIDENT DETAILS:
- Incident ID: IDP-YYYY-MM-DD-XXX
- Severity: [Critical/Major/Minor]
- Start Time: [YYYY-MM-DD HH:MM UTC]
- Status: [Investigating/Identified/Monitoring/Resolved]

IMPACT:
- Affected Services: [List of services]
- Affected Users: [Number/Percentage]
- Functionality Impact: [Description]

CURRENT STATUS:
[Description of current situation and actions being taken]

NEXT UPDATE:
[Expected time for next update]

INCIDENT COMMANDER: [Name and contact]
```

### Stakeholder Notification

```bash
#!/bin/bash
# Stakeholder notification script

SEVERITY="$1"
MESSAGE="$2"

case $SEVERITY in
  "critical")
    # Page on-call engineers
    curl -X POST "https://events.pagerduty.com/v2/enqueue" \
      -H "Content-Type: application/json" \
      -d "{\"routing_key\":\"$PAGERDUTY_KEY\",\"event_action\":\"trigger\",\"payload\":{\"summary\":\"$MESSAGE\",\"severity\":\"critical\"}}"
    
    # Send Slack alert
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"🚨 CRITICAL: $MESSAGE\"}" \
      $SLACK_CRITICAL_WEBHOOK
    ;;
  "major")
    # Send Slack alert
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"⚠️ MAJOR: $MESSAGE\"}" \
      $SLACK_ALERTS_WEBHOOK
    ;;
  "minor")
    # Log to monitoring system
    echo "$(date): MINOR: $MESSAGE" >> /var/log/incidents.log
    ;;
esac
```

## Post-Incident Activities

### 1. Incident Review Checklist

- [ ] Timeline of events documented
- [ ] Root cause identified
- [ ] Impact assessment completed
- [ ] Communication effectiveness reviewed
- [ ] Recovery time analyzed
- [ ] Action items identified
- [ ] Preventive measures defined

### 2. Post-Incident Report Template

```markdown
# Incident Post-Mortem Report

## Incident Summary
**Incident ID**: IDP-YYYY-MM-DD-XXX
**Date**: YYYY-MM-DD
**Duration**: X hours Y minutes
**Severity**: [Critical/Major/Minor]

## Timeline
| Time (UTC) | Event |
|------------|-------|
| HH:MM | Incident detected |
| HH:MM | Response team assembled |
| HH:MM | Mitigation started |
| HH:MM | Service restored |

## Root Cause
[Detailed root cause analysis]

## Impact
- **Users Affected**: X users
- **Revenue Impact**: $X
- **SLA Breach**: Yes/No

## What Went Well
- [List positive aspects]

## What Went Wrong
- [List areas for improvement]

## Action Items
| Action | Owner | Due Date | Priority |
|--------|-------|----------|----------|
| [Action] | [Name] | YYYY-MM-DD | High/Medium/Low |

## Lessons Learned
[Key takeaways and improvements]
```

### 3. Platform Hardening

```bash
#!/bin/bash
# Post-incident platform hardening

echo "=== Platform Hardening ==="

# 1. Review and update monitoring
kubectl apply -f monitoring/enhanced-alerts.yaml

# 2. Implement additional health checks
kubectl apply -f health-checks/comprehensive-checks.yaml

# 3. Update backup procedures
./scripts/enhanced-backup.sh

# 4. Review security policies
kubectl apply -f security/updated-policies.yaml

# 5. Test disaster recovery procedures
./scripts/dr-test.sh

echo "=== Platform Hardening Complete ==="
```

## Testing and Validation

### Disaster Recovery Testing Schedule

- **Monthly**: Service failure simulation
- **Quarterly**: Major outage simulation
- **Annually**: Complete platform failure drill

### DR Test Procedures

```bash
#!/bin/bash
# Disaster recovery test

echo "=== DR Test: $(date) ==="

# 1. Create test namespace
kubectl create namespace dr-test

# 2. Deploy test application
kubectl apply -f tests/dr-test-app.yaml -n dr-test

# 3. Simulate failure
kubectl delete pods -n dr-test --all

# 4. Verify recovery
kubectl wait --for=condition=available --timeout=300s deployment/dr-test-app -n dr-test

# 5. Cleanup
kubectl delete namespace dr-test

echo "=== DR Test Complete ==="
```

## Emergency Contacts

### Platform Team
- **Primary On-Call**: +1-XXX-XXX-XXXX
- **Secondary On-Call**: +1-XXX-XXX-XXXX
- **Platform Lead**: +1-XXX-XXX-XXXX

### Vendor Support
- **AWS Enterprise Support**: 1-800-XXX-XXXX
- **Istio Support**: support@istio.io
- **ArgoCD Support**: support@argoproj.io

### Management Escalation
- **Engineering Director**: +1-XXX-XXX-XXXX
- **CTO**: +1-XXX-XXX-XXXX

## Recovery Resources

### Infrastructure Requirements
- **Compute**: 10-50 EC2 instances
- **Storage**: 1TB+ EBS volumes
- **Network**: 100Mbps+ bandwidth
- **Database**: RDS instances with Multi-AZ

### Recovery Tools
- `kubectl` - Kubernetes CLI
- `argocd` - ArgoCD CLI
- `istioctl` - Istio CLI
- `aws` - AWS CLI
- `helm` - Helm package manager