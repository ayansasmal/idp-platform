# Kubernetes Integrated Developer Platform (IDP)

A comprehensive Kubernetes-based Integrated Developer Platform designed for web applications with future IoT extensibility. This platform implements GitOps principles with ArgoCD as the central deployment engine, featuring AWS Cognito authentication and hybrid architecture with external LocalStack for development.

## 🏗️ Architecture Overview

### Core Components

- **ArgoCD**: GitOps-based continuous deployment with AWS Cognito authentication
- **AWS Cognito**: Centralized OAuth/OIDC authentication for all platform services
- **External LocalStack**: AWS service emulation (Cognito, RDS, S3, Secrets Manager, ECR)
- **Crossplane**: Infrastructure as Code with hybrid LocalStack/AWS providers
- **Istio**: Service mesh with JWT validation, mTLS, and observability
- **Backstage**: Developer portal with Cognito authentication and self-service templates
- **External Secrets Operator**: Kubernetes secrets management with LocalStack/AWS integration
- **Custom CRDs**: Platform abstractions (`WebApplication`, `XDatabase`, `XS3Bucket`)

### Key Features

- **Centralized Authentication**: AWS Cognito OAuth/OIDC for all services
- **Hybrid Architecture**: Kubernetes platform + AWS managed services
- **External LocalStack**: Complete AWS service emulation for development
- **GitOps-First**: Everything deployed via ArgoCD App-of-Apps pattern
- **Multi-Environment**: Local (LocalStack) → Staging (AWS) → Production (AWS)
- **Self-Service**: Backstage templates with Cognito authentication
- **Observable**: Integrated Grafana, Prometheus, Jaeger, Kiali
- **Secure**: JWT validation, mTLS, RBAC, cert-manager, encrypted secrets
- **Production Ready**: Comprehensive automation and uninstall scripts

## 🚀 Quick Start

**One-command platform startup:**

```bash
# Clone the repository
git clone https://github.com/ayansasmal/idp-platform.git
cd idp-platform

# Setup external LocalStack (required)
./scripts/setup-external-localstack.sh

# Start the entire platform (includes Backstage setup)
./scripts/quick-start.sh

# Optional: Setup development aliases
./scripts/dev-setup.sh
```

**That's it!** Your IDP platform will be running with all services accessible via browser.

### What happens during startup:

1. **Configuration Check**: Loads and validates platform configuration
2. **Platform Health Check**: Validates prerequisites and dependencies
3. **External Backstage Setup**: Automatically clones, builds, and integrates the separate Backstage repository
4. **Service Startup**: Launches all platform services via intelligent discovery
5. **Data Protection**: Applies security policies if enabled
6. **Integration**: Connects Backstage with platform services and deploys via ArgoCD

**Note**: The Backstage application is maintained in a separate GitHub repository for independent development while seamlessly integrating with the platform.

### First-time setup:
1. **Backstage Repository**: Already configured to use [idp-backstage-app](https://github.com/ayansasmal/idp-backstage-app)
2. **Optional Setup Wizard**: Run `./scripts/idp-setup-wizard.sh` for advanced configuration
3. **Custom Repository**: Use `./scripts/configure-backstage-repo.sh YOUR_REPO_URL` to change Backstage repository

## 📊 Access Your Services

Once started, access your platform services:

- **ArgoCD (GitOps)**: http://localhost:8080 🔐 *Cognito Authentication*
- **Backstage (Developer Portal)**: http://localhost:3000 🔐 *Cognito Authentication*
- **Grafana (Monitoring)**: http://localhost:3001 (admin/admin)
- **Prometheus (Metrics)**: http://localhost:9090
- **Jaeger (Tracing)**: http://localhost:16686
- **Kiali (Service Mesh)**: http://localhost:20001
- **Monitoring Dashboard**: http://localhost:8090
- **External LocalStack**: http://localhost:4566

### 🔐 Authentication

**Test Cognito Accounts:**
- **Admin**: `admin` / `TempPassword123!`
- **Developer**: `developer` / `TempPassword123!`

**Service Accounts:**
- **Grafana**: admin / admin
- **LocalStack**: No authentication required
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

- **Docker Desktop** with Kubernetes enabled (recommended) or Kind/Minikube
- **kubectl** configured with cluster access
- **Docker** for container operations
- **awslocal** CLI (automatically installed by setup scripts)
- **curl** and **jq** for API operations
- **External LocalStack** for AWS service emulation
- **Git** for repository operations

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

### 🏗️ Architecture & Design
- [Platform Architecture Overview](docs/architecture/platform-architecture.md) - Complete architecture documentation
- [Platform Components Overview](docs/architecture/platform-overview.md) - Component-focused architecture
- [Component Diagrams](docs/architecture/component-diagrams.md) - Visual architecture diagrams

### 🚀 Getting Started & Tutorials
- [Getting Started Guide](docs/tutorials/getting-started.md) - Quick start with Cognito authentication
- [Platform Lifecycle Management](docs/tutorials/platform-lifecycle-management.md) - Installation, updates, backup, uninstall
- [Monitoring & Observability](docs/tutorials/monitoring-observability.md) - Comprehensive monitoring guide
- [Container Builds Guide](docs/tutorials/container-builds-guide.md) - Building and managing containers
- [Deploying Applications](docs/tutorials/deploying-applications.md) - Application deployment workflows
- [Argo Workflows CI/CD](docs/tutorials/argo-workflows-ci-cd.md) - Advanced CI/CD patterns

### 🛠️ Operations & Runbooks
- [Platform Operations](docs/runbooks/platform-operations.md) - Operational procedures with Cognito troubleshooting
- [Disaster Recovery](docs/runbooks/disaster-recovery.md) - Backup and recovery procedures

### 📖 User Guides
- [Access Guide](docs/guides/access-guide.md) - Service access with Cognito authentication

### 📈 Platform Status & Implementation
- [Platform Status](docs/platform-status/PLATFORM_STATUS.md) - Current implementation status
- [Argo Workflows Implementation](docs/implementation/ARGO_WORKFLOWS_IMPLEMENTATION.md)
- [Automation Scripts Update](docs/implementation/AUTOMATION_SCRIPTS_UPDATE.md)
- [Backstage Real Deployment](docs/implementation/BACKSTAGE_REAL_DEPLOYMENT.md)
- [Unified Script Improvements](docs/implementation/UNIFIED_SCRIPT_IMPROVEMENTS.md)

## 🔮 Future Roadmap

- **IoT Integration**: MQTT support, edge deployments
- **Multi-Cluster**: ArgoCD ApplicationSets for cluster fleet management
- **Advanced Security**: OPA/Gatekeeper policies, Falco runtime security
- **AI/ML Workloads**: Kubeflow integration, GPU scheduling

---

**Built with ❤️ for Cloud Native Development**
