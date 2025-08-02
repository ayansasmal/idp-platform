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

### Prerequisites
- Kubernetes cluster (local: Kind/Minikube, cloud: EKS/GKE/AKS)
- kubectl configured
- Docker (for LocalStack)
- Git

### 1. Clone Repository
```bash
git clone https://github.com/your-username/idp-platform.git
cd idp-platform
```

### 2. Install ArgoCD (One-time setup)
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Bootstrap Platform via GitOps
```bash
# Apply ArgoCD configuration
kubectl apply -f applications/argocd/argocd-apps.yaml

# Apply infrastructure applications
kubectl apply -f applications/infrastructure/core-infrastructure-apps.yaml

# Apply platform services
kubectl apply -f applications/platform/platform-services-apps.yaml

# Apply ArgoCD self-management
kubectl apply -f applications/argocd/argocd-self-app.yaml
```

### 4. Access ArgoCD UI
```bash
# Port forward ArgoCD
kubectl port-forward service/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access at: https://localhost:8080 (username: `admin`)

### 5. Deploy Sample Application
```bash
# Use the IDP CLI
./idp-cli create my-app nginx:latest development development 2

# Or use Backstage templates (after Backstage is deployed)
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
# Option 1: CLI
./idp-cli create app-name image:tag namespace environment replicas

# Option 2: Backstage Template (Web UI)
# Navigate to Backstage → Create → IDP Web Application

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

Access monitoring tools via Istio gateway:
- **Grafana**: `grafana.istio-system.svc.cluster.local`
- **Kiali**: `kiali.istio-system.svc.cluster.local`  
- **Jaeger**: `jaeger.istio-system.svc.cluster.local`
- **Prometheus**: `prometheus.istio-system.svc.cluster.local`

## 🏷️ Platform Conventions

### Mandatory Labels
All resources must include:
```yaml
labels:
  app.kubernetes.io/name: "app-identifier"
  platform.idp/environment: "development|staging|production"
  platform.idp/type: "web-application|database|etc"
  app.kubernetes.io/managed-by: "idp-platform"
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
