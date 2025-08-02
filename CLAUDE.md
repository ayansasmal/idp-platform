# Integrated Developer Platform (IDP) Architecture

## Overview

This document outlines the architecture and implementation plan for a Kubernetes-based Integrated Developer Platform (IDP) designed primarily for web applications with future extensibility for IoT projects.

## Architecture Components

### Core Infrastructure Stack

- **Kubernetes**: Container orchestration platform
- **Crossplane**: Infrastructure as Code and multi-cloud management
- **Istio/Envoy**: Service mesh for traffic management, security, and observability
- **ArgoCD**: GitOps-based continuous deployment
- **LocalStack**: Local AWS service emulation for development

### Container Registry

- **AWS ECR**: Production container registry
- **LocalStack ECR**: Local development container registry
- Unified workflow across environments

### CI/CD Pipeline

- **GitHub Actions**: Continuous Integration (build, test, security scans)
- **ArgoCD**: GitOps-based Continuous Deployment
- **Container Build**: Multi-stage Docker builds pushed to ECR

### Secrets Management

- **External Secrets Operator (ESO)**: Kubernetes secrets synchronization
- **AWS Secrets Manager**: Production secrets backend
- **LocalStack Secrets**: Local development secrets
- **cert-manager**: Certificate lifecycle management
- **Istio mTLS**: Service-to-service encryption

### Developer Experience

- **Backstage**: Developer portal and service catalog
- **Custom CRDs**: Platform abstractions (WebApplication, etc.)
- **Software Templates**: Self-service application scaffolding
- **Multi-environment**: Seamless local to production workflows

## Platform Abstractions

### WebApplication CRD

High-level abstraction that generates:

- Kubernetes Deployment manifests
- Service definitions
- Istio VirtualService/Gateway configurations
- HorizontalPodAutoscaler settings
- Crossplane resource claims (databases, storage)

### Environment Strategy

- **Local Development**: LocalStack + Kind/Minikube
- **Staging**: AWS with reduced resources
- **Production**: Full AWS infrastructure
- **GitOps**: Same configurations, different targets

## Implementation Plan

### Phase 1: Core Infrastructure

1. Set up Kubernetes cluster (local + AWS)
2. Install and configure Crossplane
3. Deploy LocalStack for local development
4. Set up basic ECR integration

### Phase 2: Service Mesh & Security

1. Deploy Istio service mesh
2. Configure mTLS between services
3. Implement External Secrets Operator
4. Set up cert-manager for certificate management

### Phase 3: GitOps & Deployment Engine

1. Deploy ArgoCD operator (one-time manual setup)
2. Configure ArgoCD self-management via GitOps
3. Implement App-of-Apps pattern for platform components
4. Set up multi-environment ArgoCD Applications

### Phase 4: Infrastructure via ArgoCD

1. Deploy Crossplane via ArgoCD (infrastructure provisioning)
2. Deploy Istio service mesh via ArgoCD
3. Deploy External Secrets Operator via ArgoCD
4. Deploy cert-manager via ArgoCD

### Phase 5: Platform Services via ArgoCD

1. Deploy Backstage via ArgoCD
2. Deploy monitoring stack (Grafana, Prometheus, Jaeger, Kiali) via ArgoCD
3. Configure ArgoCD UI with Istio VirtualService
4. Implement self-service capabilities through Backstage templates

### Phase 6: Application Workloads & Observability

1. Deploy WebApplication CRDs and sample applications via ArgoCD
2. Configure complete observability stack
3. Set up logging aggregation and alerting
4. Create operational dashboards

**Key Change**: ArgoCD becomes the central deployment engine that manages the entire platform lifecycle through GitOps, eliminating manual deployment steps after initial ArgoCD installation.

## Directory Structure

```
idp-platform/
├── infrastructure/
│   ├── crossplane/
│   │   ├── providers/
│   │   ├── compositions/
│   │   └── claims/
│   ├── istio/
│   │   ├── gateways/
│   │   ├── virtual-services/
│   │   └── policies/
│   └── localstack/
├── platform/
│   ├── crds/
│   ├── operators/
│   └── compositions/
├── applications/
│   ├── argocd/
│   │   ├── argocd-apps.yaml           # App-of-Apps root
│   │   ├── argocd-self-app.yaml       # ArgoCD self-management
│   │   └── argocd-virtualservice.yaml # ArgoCD UI routing
│   ├── infrastructure/
│   │   └── core-infrastructure-apps.yaml # Crossplane, Istio, ESO
│   ├── platform/
│   │   └── platform-services-apps.yaml   # Backstage, monitoring
│   ├── workloads/
│   │   └── {app-name}-app.yaml       # User applications
│   ├── backstage/
│   ├── monitoring/
│   └── sample-web-app/
├── secrets/
│   ├── external-secrets/
│   └── cert-manager/
├── ci-cd/
│   ├── github-actions/
│   └── templates/
└── docs/
    ├── architecture/
    ├── runbooks/
    └── tutorials/
```

**ArgoCD Application Structure**:

- **Root App**: `applications/argocd/argocd-apps.yaml` manages all platform applications
- **Infrastructure Layer**: Core platform components (Crossplane, Istio, secrets)
- **Platform Layer**: Developer-facing services (Backstage, monitoring)
- **Workload Layer**: User applications generated by Backstage templates

## ArgoCD as Central Deployment Engine

### Bootstrap Process

1. **Manual Setup**: Install ArgoCD operator only (one-time)
2. **Self-Management**: ArgoCD deploys its own UI and configuration via `argocd-self-app.yaml`
3. **App-of-Apps**: Root application in `argocd-apps.yaml` deploys all platform components
4. **Dependency Management**: Sync waves ensure proper deployment order

### Deployment Layers (Managed by ArgoCD)

**Layer 1 - Core Infrastructure** (`applications/infrastructure/`):

- Crossplane operators and providers
- External Secrets Operator
- cert-manager for certificate management

**Layer 2 - Service Mesh** (`infrastructure/istio/`):

- Istio control plane and data plane
- Gateways and ingress configuration
- Security policies and mTLS setup

**Layer 3 - Platform Services** (`applications/platform/`):

- Backstage developer portal
- Monitoring stack (Grafana, Prometheus, Jaeger, Kiali)
- ArgoCD UI with Istio VirtualService

**Layer 4 - Application Workloads** (`applications/workloads/`):

- WebApplication CRDs and sample applications
- User applications generated by Backstage templates

### GitOps Benefits

- **Single Source of Truth**: Git repository defines entire platform state
- **Automated Sync**: All components self-heal and stay in sync with Git
- **Environment Parity**: Same manifests across local/staging/production
- **Audit Trail**: Complete deployment history and rollback capability
- **Multi-Cluster**: ArgoCD can manage multiple Kubernetes clusters

## Technology Decisions

### Why Crossplane?

- Infrastructure as Code with Kubernetes-native APIs
- Multi-cloud abstractions
- GitOps integration
- LocalStack compatibility for local development

### Why Istio?

- Comprehensive service mesh capabilities
- Advanced traffic management
- Built-in security (mTLS, RBAC)
- Excellent observability

### Why ArgoCD?

- **GitOps-Native**: Declarative, Git-driven deployments
- **Central Deployment Engine**: Single tool manages entire platform lifecycle
- **App-of-Apps Pattern**: Hierarchical application management
- **Multi-Environment**: Same ArgoCD setup for local/staging/production
- **Self-Healing**: Automatic drift detection and correction
- **Dependency Management**: Sync waves for proper deployment order
- **Audit Trail**: Complete deployment history and rollback capability
- **Multi-Cluster Support**: Can manage edge/regional deployments

### Why Backstage?

- Comprehensive developer portal
- Service catalog and templates
- Extensible plugin architecture
- Strong community adoption

## Future Extensibility

### IoT Integration Points

- **Device Management**: Kubernetes ConfigMaps/Secrets for device configurations
- **Protocol Support**: Istio supports HTTP, gRPC, and TCP (MQTT over TCP)
- **Edge Deployment**: ArgoCD can manage edge cluster deployments
- **Data Pipeline**: Same service mesh for IoT data processing services

### Scaling Considerations

- **Multi-cluster**: ArgoCD supports multi-cluster deployments
- **Federation**: Crossplane can manage resources across multiple cloud providers
- **Regional**: Istio supports multi-region service mesh deployments

## Getting Started

### ArgoCD-First Bootstrap Process

1. **Prepare Git Repository**: Fork/clone the IDP platform repository
2. **Local Kubernetes**: Set up Kind/Minikube cluster
3. **LocalStack**: Start LocalStack for AWS service emulation
4. **Install ArgoCD**: Deploy ArgoCD operator manually (one-time setup)
5. **Bootstrap Platform**: Apply `argocd-apps.yaml` to trigger full platform deployment
6. **Verify Deployment**: Check ArgoCD UI for application sync status
7. **Access Services**: Use Istio gateway to access Backstage, monitoring, etc.

### Development Workflow

1. **Create Application**: Use Backstage templates or `idp-cli`
2. **Git Commit**: Push WebApplication manifests to repository
3. **Automatic Deployment**: ArgoCD detects changes and deploys application
4. **Monitor**: Use Grafana, Kiali, and Jaeger for observability
5. **Iterate**: Modify application configs in Git for GitOps updates

## Next Steps

- Set up local ArgoCD environment with LocalStack
- Deploy sample WebApplication via Backstage template
- Test GitOps workflow: Git commit → ArgoCD sync → application deployment
- Explore multi-environment promotion using ArgoCD ApplicationSets
