# IDP Platform Operations Runbook

## Overview

This runbook provides step-by-step procedures for common operational tasks on the IDP platform. These procedures are designed for platform operators and SREs.

## Prerequisites

- `kubectl` configured with cluster access
- `helm` CLI installed
- `argocd` CLI installed (optional)
- `awslocal` CLI installed for LocalStack operations
- AWS Cognito authentication configured
- External LocalStack running (for development)
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

# Check external LocalStack connectivity
curl -s http://localhost:4566/_localstack/health | jq '.services'

# Check AWS Cognito authentication status
kubectl get requestauthentication -n istio-system
kubectl get authorizationpolicy -n istio-system
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
- Cognito client secret synchronization issues

**Diagnosis Steps:**

```bash
# 1. Check ExternalSecret status
kubectl get externalsecrets --all-namespaces

# 2. Check SecretStore connectivity
kubectl get secretstore --all-namespaces
kubectl describe secretstore <store-name> -n <namespace>

# 3. Check ESO logs
kubectl logs -n external-secrets-system deployment/external-secrets

# 4. Test LocalStack Secrets Manager connectivity
awslocal secretsmanager list-secrets
awslocal secretsmanager get-secret-value --secret-id <secret-name>

# 5. Check Cognito client secrets
kubectl get secret cognito-clients -n argocd -o yaml
kubectl get secret cognito-clients -n backstage -o yaml
```

**Resolution Steps:**

```bash
# 1. Force secret refresh
kubectl delete externalsecret <secret-name> -n <namespace>

# 2. Check AWS/LocalStack credentials
kubectl get secret aws-credentials -n external-secrets-system -o yaml

# 3. Test LocalStack connectivity
curl -s http://localhost:4566/_localstack/health

# 4. Restart External Secrets Operator
kubectl rollout restart deployment/external-secrets -n external-secrets-system

# 5. Recreate Cognito clients (if needed)
kubectl apply -f infrastructure/aws/cognito-stack.yaml
```

### Authentication Issues

**Symptoms:**
- Users cannot log into ArgoCD or Backstage
- JWT token validation failures
- OIDC redirect errors
- "Invalid redirect URL" errors

**Diagnosis Steps:**

```bash
# 1. Check Cognito User Pool status
awslocal cognito-idp describe-user-pool --user-pool-id <pool-id>

# 2. Check OIDC client configuration
awslocal cognito-idp describe-user-pool-client --user-pool-id <pool-id> --client-id <client-id>

# 3. Check Istio JWT validation
kubectl logs -n istio-system deployment/istiod | grep -i jwt

# 4. Check ArgoCD OIDC configuration
kubectl get configmap argocd-cm -n argocd -o yaml | grep -A 20 oidc

# 5. Test JWKS endpoint accessibility
curl -s http://localhost.localstack.cloud:4566/<user-pool-id>/.well-known/jwks.json | jq
```

**Resolution Steps:**

```bash
# 1. Update OIDC client callback URLs
awslocal cognito-idp update-user-pool-client \
  --user-pool-id <pool-id> \
  --client-id <client-id> \
  --callback-urls "http://localhost:8080/api/dex/callback,https://argocd.idp.local/api/dex/callback"

# 2. Restart ArgoCD server
kubectl rollout restart deployment/argocd-server -n argocd

# 3. Update Istio JWT policies
kubectl apply -f infrastructure/istio/jwt-policy.yaml

# 4. Check and update issuer configuration
kubectl patch configmap argocd-cm -n argocd --patch-file argocd-oidc-patch.yaml

# 5. Verify JWKS endpoint in service mesh
kubectl apply -f infrastructure/external-services/localstack-external-service.yaml
```

### External LocalStack Issues

**Symptoms:**
- Platform cannot connect to LocalStack services
- AWS service emulation failures
- ECR push/pull failures

**Diagnosis Steps:**

```bash
# 1. Check LocalStack container status
docker ps | grep localstack

# 2. Check LocalStack health
curl -s http://localhost:4566/_localstack/health | jq

# 3. Test service connectivity from cluster
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- curl -s http://host.docker.internal:4566/_localstack/health

# 4. Check external service configuration
kubectl get service localhost-localstack-cloud -n default
kubectl get endpoints localstack-external -n default

# 5. Test awslocal connectivity
awslocal sts get-caller-identity
```

**Resolution Steps:**

```bash
# 1. Restart LocalStack container
docker restart localstack-idp

# 2. Update external service configuration
kubectl apply -f infrastructure/external-services/localstack-external-service.yaml

# 3. Check hostname resolution
echo "127.0.0.1 localhost.localstack.cloud" | sudo tee -a /etc/hosts

# 4. Run LocalStack setup script
./scripts/setup-external-localstack.sh

# 5. Verify ECR connectivity
awslocal ecr get-login-password | docker login --username AWS --password-stdin 000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566
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

# Check Cognito user pools and groups
awslocal cognito-idp list-users --user-pool-id <pool-id>
awslocal cognito-idp list-groups --user-pool-id <pool-id>

# Check ArgoCD RBAC policies
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Audit JWT authentication policies
kubectl get requestauthentication --all-namespaces
kubectl get authorizationpolicy --all-namespaces
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

## Platform Lifecycle Management

### Complete Platform Uninstall

**When to Use:**
- Environment decommissioning
- Clean platform reinstallation
- Development environment cleanup

**Procedure:**

```bash
# 1. Run comprehensive uninstall script
./scripts/uninstall-idp.sh --dry-run  # Preview what will be removed
./scripts/uninstall-idp.sh --yes      # Execute uninstall

# 2. Verify cleanup
kubectl get namespaces | grep -E "(argocd|backstage|crossplane|istio)"
kubectl get crd | grep -E "(platform.idp|crossplane|argoproj)"

# 3. Check preserved resources
curl -s http://localhost:4566/_localstack/health  # LocalStack should remain
awslocal --version  # Tools should remain
```

### Platform Reinstallation

```bash
# 1. Ensure external LocalStack is running
./scripts/setup-external-localstack.sh

# 2. Start platform
./scripts/quick-start.sh

# 3. Verify deployment
./scripts/start-platform.sh health
```

## Authentication Troubleshooting Guide

### Common Cognito Issues

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| Invalid redirect URL | OIDC login fails | Update callback URLs in Cognito client |
| JWT validation fails | 401 errors in service mesh | Check JWKS endpoint accessibility |
| User not found | Login rejected | Create user in Cognito user pool |
| Client secret mismatch | OIDC client_secret error | Regenerate and update client secret |
| Issuer mismatch | Token validation fails | Update issuer URL in ArgoCD/Istio config |

### Quick Authentication Test

```bash
# Test Cognito user pool
awslocal cognito-idp admin-get-user --user-pool-id <pool-id> --username admin

# Test JWKS endpoint
curl -s http://localhost.localstack.cloud:4566/<pool-id>/.well-known/jwks.json

# Test ArgoCD OIDC
curl -s http://localhost:8080/api/dex/.well-known/openid_configuration

# Test service mesh JWT validation
kubectl get requestauthentication cognito-jwt -n istio-system -o yaml
```

## External Dependencies

### LocalStack Requirements
- **Version**: 3.0+
- **Services**: cognito-idp, rds, s3, secretsmanager, iam, ecr
- **Endpoint**: http://localhost:4566
- **Hostname**: localhost.localstack.cloud

### AWS Services (Production)
- **Cognito**: User pools with OIDC clients
- **RDS**: PostgreSQL for persistent storage
- **S3**: Artifact and backup storage
- **Secrets Manager**: Secret management
- **ECR**: Container registry

## Contact Information

**Platform Team:**
- Slack: #platform-team
- Email: platform-team@company.com
- On-call: +1-XXX-XXX-XXXX

**Escalation:**
- Level 1: Platform Engineers
- Level 2: Senior Platform Engineers
- Level 3: Platform Architect

**External Dependencies:**
- LocalStack Support: https://docs.localstack.cloud/
- AWS Cognito Documentation: https://docs.aws.amazon.com/cognito/
- Istio Security Documentation: https://istio.io/latest/docs/concepts/security/