# ArgoCD SSL Certificate Management

This directory contains the configuration for ArgoCD SSL certificate management using cert-manager and LocalStack integration.

## Overview

The certificate management system provides:
- **cert-manager** for automated certificate generation and renewal
- **Self-signed CA** for ArgoCD SSL certificates  
- **ArgoCD server** TLS configuration
- **Backstage integration** for trusted certificate communication
- **LocalStack backup** for certificate persistence

## Components

### Core Certificate Infrastructure

- `cert-manager-install.yaml` - ArgoCD application for installing cert-manager via Helm
- `argocd-cluster-issuer.yaml` - Self-signed ClusterIssuer and CA certificate for ArgoCD
- `argocd-server-certificate.yaml` - SSL certificates for ArgoCD server and gRPC

### ArgoCD Configuration  

- `argocd-server-config.yaml` - ArgoCD server TLS configuration and CA certificate copying
- `argocd-server-tls-patch.yaml` - Deployment patches to enable TLS in ArgoCD server

### Backstage Integration

- `backstage-argocd-certs.yaml` - Certificate sharing between ArgoCD and Backstage namespaces

### LocalStack Integration

- `localstack-cert-backup.yaml` - Certificate backup/restore to LocalStack Secrets Manager

### Management

- `certificate-management-app.yaml` - ArgoCD application to manage all certificate components

## Usage

### Automatic Setup (Recommended)

Certificates are automatically configured during platform setup:

```bash
# Certificates are set up automatically during platform setup
./scripts/idp.sh setup
```

### Manual Certificate Operations

```bash
# Setup certificates manually
./scripts/idp.sh setup-certificates

# Verify certificate configuration  
./scripts/idp.sh verify-certificates

# Direct script usage
./scripts/setup-argocd-certificates.sh setup
./scripts/setup-argocd-certificates.sh verify
```

## Certificate Details

### ArgoCD CA Certificate
- **Common Name**: ArgoCD IDP Platform Root CA
- **Duration**: 1 year (8760h)
- **Algorithm**: RSA 4096-bit
- **Storage**: `argocd-ca-key-pair` secret in `cert-manager` namespace

### ArgoCD Server Certificate  
- **Common Name**: argocd-server.argocd.svc.cluster.local
- **Duration**: 90 days (2160h) 
- **Algorithm**: RSA 2048-bit
- **Storage**: `argocd-server-tls` secret in `argocd` namespace
- **DNS Names**:
  - argocd-server
  - argocd-server.argocd
  - argocd-server.argocd.svc
  - argocd-server.argocd.svc.cluster.local
  - localhost
  - argocd.local

## Integration Points

### ArgoCD Server
- Configured for HTTPS on port 443
- Custom TLS configuration with certificate files
- Automatic certificate renewal via cert-manager

### Backstage
- CA certificate mounted at `/etc/ssl/argocd/ca.crt`
- `NODE_EXTRA_CA_CERTS` environment variable configured
- Automatic certificate synchronization via Jobs

### LocalStack
- Daily certificate backup to Secrets Manager
- Certificate restore on platform startup
- Secrets stored as JSON with certificate and key data

## Troubleshooting

### Certificate Not Ready
```bash
# Check certificate status
kubectl get certificates -A

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate events
kubectl describe certificate argocd-server-tls -n argocd
```

### ArgoCD TLS Issues
```bash
# Check ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# Verify TLS configuration
kubectl get configmap argocd-server-config -n argocd -o yaml

# Test HTTPS connectivity
kubectl port-forward -n argocd svc/argocd-server 8443:443
curl -k https://localhost:8443/api/version
```

### Backstage Certificate Issues
```bash
# Check CA certificate sync
kubectl get configmap argocd-ca-certificate -n backstage -o yaml

# Check sync job logs
kubectl logs -n backstage job/sync-argocd-ca-to-backstage

# Verify certificate mount
kubectl exec -n backstage deployment/backstage -- ls -la /etc/ssl/argocd/
```

### LocalStack Backup Issues
```bash
# Check backup job logs
kubectl logs -n cert-manager job/argocd-cert-backup

# Verify LocalStack connectivity
kubectl port-forward -n localstack svc/localstack 4566:4566
curl http://localhost:4566/health

# Check stored secrets
awslocal secretsmanager list-secrets --region us-east-1
```

## Security Considerations

- **Self-signed certificates** are used for local development
- **Production deployments** should use certificates from a trusted CA
- **Certificate rotation** is handled automatically by cert-manager
- **LocalStack secrets** are stored unencrypted (development only)
- **RBAC** is configured for certificate management service accounts

## Architecture Benefits

1. **Automated Management**: cert-manager handles certificate lifecycle
2. **Secure Communication**: End-to-end TLS between ArgoCD and Backstage
3. **Platform Integration**: Seamless certificate sharing across namespaces  
4. **Backup & Recovery**: LocalStack integration for certificate persistence
5. **Observability**: Certificate status monitoring and alerting
6. **Compliance**: Proper certificate validation and trust chain