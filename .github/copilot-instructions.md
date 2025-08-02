# IDP Platform Copilot Instructions

## Platform Architecture Overview

This is a Kubernetes-based Integrated Developer Platform (IDP) designed for web applications with future IoT extensibility. The platform follows a layered approach with GitOps, service mesh, and infrastructure-as-code principles.

### Key Components

- **Crossplane**: Infrastructure abstraction with LocalStack for local development
- **Istio**: Service mesh for traffic management, security (mTLS), and observability
- **ArgoCD**: GitOps-based continuous deployment
- **Backstage**: Developer portal with self-service templates
- **External Secrets Operator**: Kubernetes secrets management
- **Custom CRDs**: Platform abstractions (`WebApplication` CRD in `platform/crds/`)

## Critical Platform Patterns

### WebApplication CRD Workflow

The platform's core abstraction is the `WebApplication` CRD that generates complete application stacks:

```yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
```

This creates Deployments, Services, VirtualServices, and optionally HPA/database resources.

### Environment Strategy

- **Local**: LocalStack + Kind/Minikube (see `infrastructure/localstack/`)
- **Staging/Production**: AWS with Crossplane compositions
- **All environments**: Same manifests, different provider configs

### Label Conventions

All resources use these mandatory labels:

- `app.kubernetes.io/name`: Application identifier
- `platform.idp/environment`: Target environment
- `platform.idp/type`: Resource type (web-application, database, etc.)
- `app.kubernetes.io/managed-by`: Always "idp-platform"

### Crossplane Compositions

Located in `infrastructure/crossplane/compositions/`, these define infrastructure templates:

- `database-composition.yaml`: PostgreSQL RDS with LocalStack support
- `s3-bucket-composition.yaml`: S3 storage abstraction
- Provider configs switch between LocalStack (local) and AWS (production)

## Development Workflows

### CLI Tool Usage

The `idp-cli` script is the primary developer interface:

```bash
./idp-cli create my-app nginx:latest development development 2
```

This creates a complete WebApplication with namespace, Istio injection, and routing.

### Backstage Templates

Templates in `backstage-app/examples/idp-webapp-template/` generate:

- WebApplication CRD manifests
- GitHub repo with CI/CD workflows
- ArgoCD Application definitions
  Use the Backstage pattern of parameterized scaffolding with `template.yaml`.

### CI/CD Pipeline Structure

GitHub Actions in `ci-cd/github-actions/`:

- `build-and-push.yml`: Container builds with security scanning
- `promote-to-*.yml`: Environment promotion workflows
  All use GHCR (`ghcr.io`) as the container registry.

### Local Development Setup

**ArgoCD Bootstrap Process**:

1. Install ArgoCD operator manually (one-time setup)
2. ArgoCD deploys itself + UI via `applications/argocd/argocd-self-app.yaml`
3. ArgoCD deploys platform infrastructure via App-of-Apps pattern
4. Use `infrastructure/localstack/docker-config.sh` for AWS service mocking
5. ECR setup via `infrastructure/localstack/ecr-setup.yaml` (deployed by ArgoCD)
6. Test with `infrastructure/localstack/test-ecr.sh`

**ArgoCD manages deployment order**:

1. Core infrastructure (Crossplane, External Secrets)
2. Service mesh (Istio control plane, gateways)
3. Platform services (Backstage, monitoring)
4. Application workloads

## Istio Service Mesh Patterns

### Gateway Configuration

Main gateway in `infrastructure/istio/gateways/main-gateway.yaml` handles all ingress.

### VirtualService Pattern

Applications get automatic VirtualServices with hostname pattern:
`{app-name}.{environment}.idp.local`

### Security Defaults

- All pods get `sidecar.istio.io/inject: "true"`
- mTLS enforced cluster-wide
- RBAC policies in `infrastructure/istio/policies/`

## Secrets Management

### External Secrets Integration

- ClusterSecretStore: `localstack-secrets` for local, AWS Secrets Manager for production
- ExternalSecret pattern in `secrets/external-secrets/`
- Test credentials: `access-key-id: test`, `secret-access-key: test`

### Certificate Management

cert-manager handles TLS certificates with automatic renewal via `secrets/cert-manager/`.

## Observability Stack

### Monitoring Endpoints

Access via `applications/monitoring/monitoring-summary.yaml`:

- Grafana: `grafana.istio-system.svc.cluster.local`
- Kiali: `kiali.istio-system.svc.cluster.local`
- Jaeger: `jaeger.istio-system.svc.cluster.local`
- Prometheus: `prometheus.istio-system.svc.cluster.local`

### ArgoCD as Central Deployment Engine

ArgoCD deploys ALL platform components using the App-of-Apps pattern:

- **Infrastructure**: Crossplane, Istio, External Secrets (via `applications/argocd/argocd-apps.yaml`)
- **Platform Services**: Backstage, monitoring stack, cert-manager
- **Application Workloads**: WebApplication CRDs and user applications
- **Multi-Environment**: Different ArgoCD Applications target different clusters/namespaces

**Key ArgoCD Applications**:

```yaml
# Core platform infrastructure
applications/infrastructure/
├── crossplane-app.yaml          # Crossplane operator + providers
├── istio-app.yaml              # Istio control plane + gateways
├── external-secrets-app.yaml   # ESO + ClusterSecretStores
└── cert-manager-app.yaml       # Certificate management

# Platform services
applications/platform/
├── backstage-app.yaml          # Developer portal
├── monitoring-app.yaml         # Grafana, Prometheus, Jaeger, Kiali
└── argocd-ui-app.yaml         # ArgoCD dashboard + VirtualService

# User applications (managed by templates)
applications/workloads/
└── {app-name}-app.yaml        # Generated by Backstage templates
```

All use automated sync with pruning and self-healing enabled.

## File Structure Guidelines

### Application Manifests

`applications/{service-name}/`: Contains Kubernetes manifests

- `deployment.yaml`: Core application deployment
- `service.yaml`: Kubernetes service definition
- `virtualservice.yaml`: Istio routing configuration

### Infrastructure Organization

- `infrastructure/crossplane/`: Crossplane providers, compositions, claims
- `infrastructure/istio/`: Service mesh configuration
- `platform/`: Custom CRDs and operators
- `secrets/`: Secret management configuration

## Common Debugging Commands

```bash
# Check WebApplication status
kubectl get webapplications -A

# Inspect Crossplane resources
kubectl get providers,compositions,claims -A

# Istio configuration validation
istioctl analyze

# ArgoCD application sync status
kubectl get applications -n argocd

# External secrets troubleshooting
kubectl get clustersecretstores,externalsecrets -A
```

## Testing Patterns

Use the pattern from `infrastructure/localstack/test-ecr.sh` for integration testing:

1. Verify LocalStack connectivity
2. Test resource creation
3. Validate Crossplane compositions
4. Check Istio sidecar injection
