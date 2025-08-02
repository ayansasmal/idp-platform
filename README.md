# Kubernetes Integrated Developer Platform (IDP)

A comprehensive Kubernetes-based Integrated Developer Platform designed for web applications with future IoT extensibility. This platform implements GitOps principles with ArgoCD as the central deployment engine.

## 🏗️ Architecture Overview

### Core Components

- **ArgoCD**: GitOps-based continuous deployment (central deployment engine)
- **Crossplane**: Infrastructure as Code with LocalStack for local development
- **Istio**: Service mesh for traffic management, security (mTLS), and observability
- **Backstage**: Developer portal with self-service templates
- **External Secrets Operator**: Kubernetes secrets management
- **Custom CRDs**: Platform abstractions (`WebApplication` CRD)

### Key Features

- **GitOps-First**: Everything deployed via ArgoCD App-of-Apps pattern
- **Multi-Environment**: Local (LocalStack) → Staging → Production
- **Self-Service**: Backstage templates for application scaffolding
- **Observable**: Integrated Grafana, Prometheus, Jaeger, Kiali
- **Secure**: mTLS, RBAC, cert-manager, External Secrets

## 🚀 Quick Start

**One-command platform startup:**

```bash
# Clone the repository
git clone https://github.com/your-org/idp-platform.git
cd idp-platform

# Setup development environment (first time only)
./scripts/dev-setup.sh

# Start the entire platform
./scripts/quick-start.sh
```

**That's it!** Your IDP platform will be running with all services accessible via browser.

## 📊 Access Your Services

Once started, access your platform services:

- **ArgoCD (GitOps)**: http://localhost:8080
- **Backstage (Developer Portal)**: http://localhost:3000
- **Grafana (Monitoring)**: http://localhost:3001
- **Prometheus (Metrics)**: http://localhost:9090
- **Jaeger (Tracing)**: http://localhost:16686
- **Kiali (Service Mesh)**: http://localhost:20001
- **Monitoring Dashboard**: http://localhost:8090

## 🔐 Default Credentials

- **ArgoCD**: admin / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
- **Grafana**: admin / admin

## ⚡ Quick Commands

```bash
# Platform management
idp-start          # Start all services
idp-stop           # Stop all services  
idp-status         # Check service status
idp-health         # Platform health check
idp-restart        # Restart all services

# Service access shortcuts
idp-argocd         # Open ArgoCD
idp-backstage      # Open Backstage
idp-grafana        # Open Grafana
```

## 📋 Prerequisites

- **Kubernetes cluster** (Docker Desktop, Kind, or Minikube)
- **kubectl** configured with cluster access
- **Docker** for container operations
- **Helm** for package management (optional)

## 🔧 Manual Setup (Advanced)

If you prefer manual setup or need to understand the underlying components:

### 1. Install ArgoCD (One-time setup)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 2. Bootstrap Platform via GitOps

```bash
# Apply ArgoCD configuration
kubectl apply -f applications/argocd/argocd-apps.yaml

# Apply infrastructure applications
kubectl apply -f applications/infrastructure/core-infrastructure-apps.yaml

# Apply platform services
kubectl apply -f applications/platform/platform-services-apps.yaml
```

### 3. Manual Port Forwarding

```bash
# ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:80

# Backstage
kubectl port-forward -n backstage svc/backstage 3000:80

# Grafana
kubectl port-forward -n istio-system svc/grafana 3001:3000
```

## 📁 Repository Structure

```
idp-platform/
├── applications/
│   ├── argocd/                    # ArgoCD configuration & App-of-Apps
│   │   ├── argocd-apps.yaml       # Main App-of-Apps root
│   │   ├── argocd-self-app.yaml   # ArgoCD self-management
│   │   └── argocd-virtualservice.yaml
│   ├── infrastructure/            # Infrastructure layer
│   │   └── core-infrastructure-apps.yaml
│   ├── platform/                  # Platform services layer
│   │   └── platform-services-apps.yaml
│   ├── backstage/                 # Developer portal configs
│   ├── monitoring/                # Observability stack
│   └── sample-web-app/           # Reference application
├── infrastructure/
│   ├── crossplane/               # Infrastructure provisioning
│   ├── istio/                   # Service mesh configuration
│   └── localstack/              # Local AWS emulation
├── platform/
│   ├── crds/                    # Custom Resource Definitions
│   └── operators/               # Platform operators
├── secrets/                     # Secret management
├── ci-cd/                      # GitHub Actions workflows
├── backstage-app/              # Backstage source code
└── docs/                       # Documentation
```

## 🔄 GitOps Deployment Flow

### ArgoCD App-of-Apps Hierarchy

1. **Root**: `argocd-apps.yaml` manages all platform applications
2. **Infrastructure Layer**: Crossplane, Istio, External Secrets, cert-manager
3. **Platform Layer**: Backstage, monitoring stack, ArgoCD UI
4. **Workload Layer**: User applications via Backstage templates

### Deployment Order (Automatic via ArgoCD)

1. Core infrastructure (Crossplane, External Secrets)
2. Service mesh (Istio control plane, gateways)
3. Platform services (Backstage, monitoring)
4. Application workloads

## 🛠️ Development Workflows

### Create New Application

```bash
# Option 1: Backstage Template (Recommended - Web UI)
# Navigate to http://localhost:3000 → Create → IDP Web Application

# Option 2: CLI (Quick deployment)
./idp-cli create app-name image:tag namespace environment replicas

# Option 3: Direct WebApplication CRD
kubectl apply -f - <<EOF
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: my-app
  namespace: development
spec:
  appName: my-app
  image:
    repository: nginx
    tag: latest
  replicas: 2
  environment: development
EOF
```

### Development Commands

```bash
# Platform management
./scripts/quick-start.sh      # Start entire platform
./scripts/start-platform.sh status  # Check all services
./scripts/start-platform.sh logs argocd  # View service logs
./scripts/start-platform.sh health   # Health check

# Individual service management
./scripts/start-platform.sh start argocd backstage  # Start specific services
./scripts/start-platform.sh stop     # Stop all services
```

### Local Development with LocalStack

```bash
# Start LocalStack
./infrastructure/localstack/docker-config.sh

# Test ECR integration
./infrastructure/localstack/test-ecr.sh
```

### Multi-Environment Promotion

Git-based promotion through ArgoCD:

1. **Development**: Direct commits to `main` branch
2. **Staging**: Tags or `staging` branch
3. **Production**: Release tags or `production` branch

## 🔍 Observability & Monitoring

The platform includes a complete observability stack with automatic port forwarding:

### Monitoring Services (Auto-forwarded)

- **Grafana**: http://localhost:3001 (Dashboards and visualization)
- **Prometheus**: http://localhost:9090 (Metrics collection)  
- **Jaeger**: http://localhost:16686 (Distributed tracing)
- **Kiali**: http://localhost:20001 (Service mesh visualization)
- **Alertmanager**: http://localhost:9093 (Alert management)
- **Monitoring Hub**: http://localhost:8090 (Central dashboard)

### Pre-configured Dashboards

- **Platform Overview**: Overall health and performance
- **WebApplication Metrics**: Per-application monitoring
- **ArgoCD Dashboard**: GitOps deployment status
- **Istio Service Mesh**: Traffic flow and security

### Built-in Alerts

- High error rates (>5%)
- High latency (P95 >1s)
- Application down alerts
- Resource utilization warnings

## 🏷️ Platform Conventions

### Mandatory Labels

All resources must include:

```yaml
labels:
  app.kubernetes.io/name: 'app-identifier'
  platform.idp/environment: 'development|staging|production'
  platform.idp/type: 'web-application|database|etc'
  app.kubernetes.io/managed-by: 'idp-platform'
```

### Istio Integration

- All pods get `sidecar.istio.io/inject: "true"`
- VirtualServices follow pattern: `{app-name}.{environment}.idp.local`
- mTLS enforced cluster-wide

## 🔧 Troubleshooting

### Check Platform Status

```bash
# ArgoCD applications
kubectl get applications -n argocd

# WebApplications
kubectl get webapplications -A

# Crossplane resources
kubectl get providers,compositions,claims -A

# Istio configuration
istioctl analyze

# External Secrets
kubectl get clustersecretstores,externalsecrets -A
```

### Common Issues

1. **Applications stuck in "Unknown" sync**: Check repository access and credentials
2. **Istio sidecar not injecting**: Verify namespace has `istio-injection=enabled`
3. **External Secrets failing**: Check LocalStack connectivity or AWS credentials

## 🤝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open Pull Request

Changes will be automatically deployed via ArgoCD GitOps.

## 📚 Documentation

- [Architecture Overview](docs/architecture/platform-overview.md)
- [Platform Operations](docs/runbooks/platform-operations.md)
- [Disaster Recovery](docs/runbooks/disaster-recovery.md)

## 🔮 Future Roadmap

- **IoT Integration**: MQTT support, edge deployments
- **Multi-Cluster**: ArgoCD ApplicationSets for cluster fleet management
- **Advanced Security**: OPA/Gatekeeper policies, Falco runtime security
- **AI/ML Workloads**: Kubeflow integration, GPU scheduling

---

**Built with ❤️ for Cloud Native Development**
