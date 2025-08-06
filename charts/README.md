# IDP Platform Helm Charts

This directory contains versioned Helm charts for each IDP platform component, enabling independent updates and rollbacks.

## Chart Structure

```
charts/
├── core-infrastructure/
│   ├── istio-config/           # Istio service mesh configuration
│   ├── argocd-platform/        # ArgoCD GitOps engine
│   ├── crossplane-config/      # Infrastructure as Code
│   └── cert-manager-config/    # Certificate management
├── observability/
│   ├── monitoring-stack/       # Prometheus + Grafana + Alertmanager
│   ├── tracing-stack/         # Jaeger distributed tracing
│   └── service-mesh-obs/      # Kiali service mesh observability
├── platform-services/
│   ├── backstage-deployment/  # Developer portal
│   ├── argo-workflows/        # Internal CI/CD
│   └── external-secrets/      # Secrets management
└── custom-components/
    ├── platform-crds/         # Custom Resource Definitions
    └── platform-operators/    # Custom operators and controllers
```

## Versioning Strategy

- **Semantic Versioning**: Charts follow semver (e.g., `1.2.3`)
- **Chart Version**: Independent of application version
- **App Version**: Tracks the actual application/service version
- **Compatibility Matrix**: Maintained for inter-component dependencies

## Usage

```bash
# List available chart versions
./scripts/idp.sh versions list monitoring-stack

# Update a component to specific version
./scripts/idp.sh update monitoring-stack --version 2.1.0

# Rollback a component
./scripts/idp.sh rollback monitoring-stack --steps 1

# Check component status
./scripts/idp.sh status monitoring-stack
```

## Chart Development

Each chart includes:
- `Chart.yaml` - Chart metadata and versioning
- `values.yaml` - Default configuration values
- `templates/` - Kubernetes manifests with templating
- `README.md` - Chart-specific documentation
- `CHANGELOG.md` - Version history and changes