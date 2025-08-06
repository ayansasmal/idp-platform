# Integrated Developer Platform (IDP) Architecture

## Overview

This document outlines the complete architecture and implementation of a production-ready Kubernetes-based Integrated Developer Platform (IDP) designed primarily for web applications with future extensibility for IoT projects.

**Current Status: ✅ PRODUCTION READY** - All 6 phases completed with automation scripts and comprehensive observability.

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

## Getting Started

### Quick Start (Recommended)

```bash
# 1. Clone repository
git clone https://github.com/your-org/idp-platform.git
cd idp-platform

# 2. One-time setup and start
./scripts/idp.sh setup

# 3. Start platform services
./scripts/idp.sh start

# That's it! Complete platform is running with all services accessible
```

### Access Your Platform

All services are automatically accessible:
- **ArgoCD**: https://localhost:8080 (admin / [get password from output])
- **Backstage**: http://localhost:3000 (Developer portal)
- **Grafana**: http://localhost:3001 (admin / admin)
- **Prometheus**: http://localhost:9090 (Metrics collection)
- **Jaeger**: http://localhost:16686 (Distributed tracing)
- **Kiali**: http://localhost:20001 (Service mesh observability)
- **Argo Workflows**: http://localhost:4000 (CI/CD workflows)
- **Monitoring Dashboard**: http://localhost:3002 (Observability overview)

The platform is now production-ready with comprehensive automation! 🎉

## ⚡ Latest Optimizations (Script Simplification & Efficiency)

### Unified Platform Management
```bash
# New streamlined workflow (all-in-one script)
./scripts/idp.sh setup           # One-time platform setup (replaces multiple scripts)
./scripts/idp.sh build-backstage # Build Backstage via internal Argo Workflows
./scripts/idp.sh start           # Start all services with intelligent discovery
./scripts/idp.sh stop            # Stop all services
./scripts/idp.sh restart         # Restart platform services
./scripts/idp.sh status          # Check platform status
./scripts/idp.sh config          # Run configuration wizard
```

### Key Optimizations Implemented
- **14 scripts → 1 unified script** with specialized functions
- **External builds → Internal workflows** using Argo Workflows  
- **Manual coordination → Automated orchestration**
- **Reduced complexity → Streamlined developer experience**

### Script Changes Summary
- **Created**: `scripts/idp.sh` - Unified platform management script
- **Created**: `platform/workflows/backstage-ci-pipeline.yaml` - Internal CI/CD for Backstage
- **Simplified**: `scripts/quick-start.sh` - Now wrapper to unified script
- **Documented**: `scripts/DEPRECATED_SCRIPTS.md` - Migration guide for deprecated scripts
- **Enhanced**: README.md and documentation to reflect new simplified workflow

### Backstage Build Process (Now Internal)
1. **Setup Platform**: `./scripts/idp.sh setup` deploys ArgoCD + Argo Workflows
2. **Trigger Build**: `./scripts/idp.sh build-backstage` submits workflow to internal CI/CD  
3. **Automated Pipeline**: Argo Workflows clones, builds, containerizes, and deploys Backstage
4. **GitOps Integration**: ArgoCD automatically syncs and deploys to platform
5. **Access**: Backstage available at http://localhost:3000 via intelligent port-forwarding

**Result**: Complete end-to-end automation with simplified developer interface!