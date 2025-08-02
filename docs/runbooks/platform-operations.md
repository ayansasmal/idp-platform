# IDP Platform Operations Runbook

## Overview

This runbook provides step-by-step procedures for common operational tasks on the IDP platform. These procedures are designed for platform operators and SREs.

## Prerequisites

- `kubectl` configured with cluster access
- `helm` CLI installed
- `argocd` CLI installed (optional)
- Platform monitoring dashboard access

## Quick Health Check

### 1. Platform Components Status

```bash
# Check all platform namespaces
kubectl get pods --all-namespaces | grep -E "(istio-system|argocd|backstage|crossplane-system|external-secrets-system|cert-manager)"

# Quick health check command
kubectl get pods -n istio-system -o wide
kubectl get pods -n argocd -o wide
kubectl get pods -n crossplane-system -o wide
```

### 2. Service Mesh Health

```bash
# Check Istio control plane
istioctl proxy-status

# Verify service mesh configuration
istioctl analyze

# Check gateway status
kubectl get gateway -n istio-system
kubectl get virtualservice --all-namespaces
```

### 3. GitOps Status

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Verify sync status
argocd app list
argocd app get <app-name>
```

## Incident Response Procedures

### Application Down

**Symptoms:**
- Application not responding to requests
- High error rates in monitoring
- Pods in CrashLoopBackOff state

**Diagnosis Steps:**

```bash
# 1. Check application pods
kubectl get pods -n <namespace> -l app=<app-name>

# 2. Check pod logs
kubectl logs -n <namespace> <pod-name> --previous

# 3. Check events
kubectl describe pod -n <namespace> <pod-name>

# 4. Check service endpoints
kubectl get endpoints -n <namespace> <service-name>

# 5. Check Istio configuration
istioctl proxy-config cluster <pod-name>.<namespace>
```

**Resolution Steps:**

```bash
# 1. Restart deployment
kubectl rollout restart deployment/<deployment-name> -n <namespace>

# 2. Check resource limits
kubectl describe deployment <deployment-name> -n <namespace>

# 3. Scale deployment
kubectl scale deployment <deployment-name> --replicas=<count> -n <namespace>

# 4. Check for configuration issues
kubectl get configmap -n <namespace>
kubectl get secret -n <namespace>
```

### High Memory/CPU Usage

**Symptoms:**
- High CPU/Memory alerts firing
- Slow response times
- Pod evictions

**Diagnosis Steps:**

```bash
# 1. Check resource usage
kubectl top pods -n <namespace>
kubectl top nodes

# 2. Check HPA status
kubectl get hpa -n <namespace>
kubectl describe hpa <hpa-name> -n <namespace>

# 3. Check pod resource requests/limits
kubectl describe pod <pod-name> -n <namespace>
```

**Resolution Steps:**

```bash
# 1. Scale up immediately
kubectl scale deployment <deployment-name> --replicas=<higher-count> -n <namespace>

# 2. Update resource limits (if needed)
kubectl patch deployment <deployment-name> -n <namespace> -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container>","resources":{"limits":{"memory":"512Mi","cpu":"500m"}}}]}}}}'

# 3. Check for memory leaks in logs
kubectl logs -n <namespace> <pod-name> | grep -i "memory\|oom"
```

### ArgoCD Sync Issues

**Symptoms:**
- Applications stuck in "OutOfSync" state
- Deployment failures
- Git synchronization errors

**Diagnosis Steps:**

```bash
# 1. Check application status
argocd app get <app-name>

# 2. Check sync history
argocd app history <app-name>

# 3. Check Git repository access
argocd repo list
argocd repo get <repo-url>
```

**Resolution Steps:**

```bash
# 1. Manual sync
argocd app sync <app-name>

# 2. Hard refresh
argocd app sync <app-name> --force

# 3. Reset to specific revision
argocd app rollback <app-name> <revision-id>

# 4. Restart ArgoCD components
kubectl rollout restart deployment/argocd-application-controller -n argocd
kubectl rollout restart deployment/argocd-server -n argocd
```

### Certificate Issues

**Symptoms:**
- TLS certificate expired alerts
- SSL/TLS handshake failures
- Browser security warnings

**Diagnosis Steps:**

```bash
# 1. Check certificate status
kubectl get certificates --all-namespaces

# 2. Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# 3. Check certificate details
kubectl describe certificate <cert-name> -n <namespace>

# 4. Check Istio Gateway TLS
kubectl get gateway -n istio-system -o yaml
```

**Resolution Steps:**

```bash
# 1. Force certificate renewal
kubectl delete certificate <cert-name> -n <namespace>

# 2. Check certificate issuer
kubectl get clusterissuer
kubectl describe clusterissuer <issuer-name>

# 3. Restart cert-manager
kubectl rollout restart deployment/cert-manager -n cert-manager
```

### Secret Synchronization Issues

**Symptoms:**
- External Secrets Operator alerts
- Pods failing to start due to missing secrets
- Authentication failures

**Diagnosis Steps:**

```bash
# 1. Check ExternalSecret status
kubectl get externalsecrets --all-namespaces

# 2. Check SecretStore connectivity
kubectl get secretstore --all-namespaces
kubectl describe secretstore <store-name> -n <namespace>

# 3. Check ESO logs
kubectl logs -n external-secrets-system deployment/external-secrets
```

**Resolution Steps:**

```bash
# 1. Force secret refresh
kubectl delete externalsecret <secret-name> -n <namespace>

# 2. Check AWS credentials (for AWS Secrets Manager)
kubectl get secret aws-credentials -n external-secrets-system -o yaml

# 3. Restart External Secrets Operator
kubectl rollout restart deployment/external-secrets -n external-secrets-system
```

## Maintenance Procedures

### Platform Updates

#### 1. Istio Upgrade

```bash
# 1. Check current version
istioctl version

# 2. Download new Istio version
curl -L https://istio.io/downloadIstio | sh -

# 3. Upgrade control plane
istioctl upgrade

# 4. Restart data plane (gradual)
kubectl rollout restart deployment --all -n <namespace>

# 5. Verify upgrade
istioctl proxy-status
```

#### 2. ArgoCD Upgrade

```bash
# 1. Check current version
kubectl get deployment argocd-server -n argocd -o yaml | grep image:

# 2. Update ArgoCD manifests
kubectl apply -f applications/argocd/

# 3. Verify upgrade
kubectl get pods -n argocd
argocd version
```

#### 3. Crossplane Upgrade

```bash
# 1. Check current version
kubectl get deployment crossplane -n crossplane-system -o yaml | grep image:

# 2. Upgrade via Helm
helm upgrade crossplane crossplane-stable/crossplane -n crossplane-system

# 3. Verify providers
kubectl get providers
```

### Backup Procedures

#### 1. GitOps Repository Backup

```bash
# Backup Git repositories (automated via Git hosting)
# Ensure all configuration is in Git
git clone <idp-config-repo>
git clone <app-configs-repo>
```

#### 2. Secret Backup

```bash
# Export secrets (for disaster recovery)
kubectl get secrets --all-namespaces -o yaml > secrets-backup.yaml

# Encrypt backup file
gpg --symmetric --cipher-algo AES256 secrets-backup.yaml
```

#### 3. Persistent Volume Backup

```bash
# List PVs
kubectl get pv

# Create volume snapshots (cloud-specific)
# For AWS EBS
aws ec2 create-snapshot --volume-id <volume-id> --description "IDP backup $(date)"
```

### Scaling Procedures

#### 1. Cluster Scaling

```bash
# Check current nodes
kubectl get nodes

# For AWS EKS
aws eks update-nodegroup-config --cluster-name <cluster> --nodegroup-name <nodegroup> --scaling-config minSize=<min>,maxSize=<max>,desiredSize=<desired>

# Verify scaling
kubectl get nodes
kubectl top nodes
```

#### 2. Application Scaling

```bash
# Manual scaling
kubectl scale deployment <deployment> --replicas=<count> -n <namespace>

# Update HPA
kubectl patch hpa <hpa-name> -n <namespace> -p '{"spec":{"maxReplicas":<new-max>}}'

# Check HPA status
kubectl get hpa -n <namespace>
```

## Monitoring and Alerts

### Key Metrics to Monitor

1. **Platform Health**
   - Pod restart rate
   - Node resource utilization
   - Persistent volume usage

2. **Application Performance**
   - Request latency (P50, P95, P99)
   - Error rate
   - Throughput (requests/second)

3. **Security**
   - Certificate expiration
   - Failed authentication attempts
   - Network policy violations

### Alert Escalation

1. **Critical Alerts** (Page immediately)
   - Platform components down
   - High error rates (>5%)
   - Security incidents

2. **Warning Alerts** (Ticket creation)
   - High resource utilization (>80%)
   - Certificate expiring (<30 days)
   - Slow response times

3. **Info Alerts** (Log only)
   - Deployment events
   - Scaling events
   - Configuration changes

## Disaster Recovery

### Recovery Time Objectives (RTO)

- **Platform Infrastructure**: 1 hour
- **Critical Applications**: 30 minutes
- **Non-critical Applications**: 4 hours

### Recovery Procedures

#### 1. Complete Cluster Failure

```bash
# 1. Create new cluster
eksctl create cluster --config-file cluster-config.yaml

# 2. Install platform components
kubectl apply -f infrastructure/

# 3. Restore GitOps
kubectl apply -f applications/argocd/
argocd app sync --all

# 4. Verify all applications
kubectl get pods --all-namespaces
```

#### 2. Data Recovery

```bash
# 1. Restore from snapshots
aws ec2 create-volume --snapshot-id <snapshot-id>

# 2. Attach volumes to new instances
aws ec2 attach-volume --volume-id <volume-id> --instance-id <instance-id>

# 3. Update PV configurations
kubectl apply -f restored-pv-configs.yaml
```

## Performance Optimization

### 1. Resource Right-sizing

```bash
# Check resource recommendations
kubectl describe vpa <vpa-name> -n <namespace>

# Apply recommendations
kubectl patch deployment <deployment> -n <namespace> --patch-file resource-patch.yaml
```

### 2. Network Optimization

```bash
# Check service mesh performance
istioctl proxy-config cluster <pod-name>.<namespace>

# Optimize Envoy configuration
kubectl apply -f envoy-filter-optimization.yaml
```

### 3. Storage Optimization

```bash
# Check PV usage
kubectl get pv
df -h /mnt/data

# Cleanup unused volumes
kubectl delete pv <unused-pv>
```

## Security Procedures

### 1. Security Incident Response

**Steps:**
1. Isolate affected components
2. Preserve logs and evidence
3. Patch vulnerabilities
4. Restore from clean backups
5. Conduct post-incident review

### 2. Access Review

```bash
# Check RBAC permissions
kubectl get rolebindings --all-namespaces
kubectl get clusterrolebindings

# Audit service accounts
kubectl get serviceaccounts --all-namespaces
```

### 3. Vulnerability Management

```bash
# Scan container images
trivy image <image-name>

# Check for outdated packages
kubectl get pods -o yaml | grep image: | sort | uniq
```

## Troubleshooting Common Issues

### Pod Stuck in Pending State

```bash
# Check node resources
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -n <namespace>

# Check node taints and tolerations
kubectl describe nodes
```

### DNS Resolution Issues

```bash
# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

### Persistent Volume Issues

```bash
# Check PV status
kubectl get pv
kubectl describe pv <pv-name>

# Check storage class
kubectl get storageclass
```

## Contact Information

**Platform Team:**
- Slack: #platform-team
- Email: platform-team@company.com
- On-call: +1-XXX-XXX-XXXX

**Escalation:**
- Level 1: Platform Engineers
- Level 2: Senior Platform Engineers
- Level 3: Platform Architect