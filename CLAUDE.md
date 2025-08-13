# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a production-ready Kubernetes-based Integrated Developer Platform (IDP) designed for web applications with future IoT extensibility. The platform implements GitOps principles with comprehensive automation, service mesh, and developer self-service capabilities.

**Current Status: ✅ PRODUCTION READY** - All core phases completed with advanced multi-instance capabilities and comprehensive automation.

## Repository Structure

**Two Independent GitHub Repositories:**
- **[idp-platform](https://github.com/ayansasmal/idp-platform)** - Core platform infrastructure, GitOps configurations, scripts
- **[idp-backstage-app](https://github.com/ayansasmal/idp-backstage-app)** - Backstage developer portal application

## Quick Platform Setup

```bash
# Clone and start the platform (one command!)
git clone https://github.com/ayansasmal/idp-platform.git
cd idp-platform
./scripts/idp.sh setup
# Platform automatically handles Backstage integration
```

## Development Policies

- Always update claude.md with any changes to the state, structure, features, functionalities of the IDP

## Common Development Commands

### Platform Management
```bash
# Platform setup and configuration
./scripts/idp-setup-wizard.sh       # Interactive setup wizard for platform configuration
./scripts/config-parser.sh show     # Display current platform configuration
./scripts/config-parser.sh validate # Validate platform configuration

# Start entire platform (primary command) - now includes configuration check
./scripts/idp.sh setup

# Platform lifecycle management  
./scripts/idp.sh start               # Start all services with port-forwards
./scripts/idp.sh stop                # Stop all services
./scripts/idp.sh restart             # Restart platform services
./scripts/idp.sh status              # Check platform status
./scripts/idp.sh config              # Run configuration wizard

# Advanced commands
./scripts/idp.sh build-backstage     # Build Backstage app using IDP workflows
./scripts/idp.sh build-unleash       # Build and deploy Unleash OSS feature flags
./scripts/idp.sh deploy-templates    # Deploy/redeploy Argo Workflows templates

# Setup and teardown
./scripts/dev-setup.sh               # One-time development environment setup
./scripts/setup-external-localstack.sh  # Setup LocalStack for AWS emulation
./scripts/setup-backstage-external.sh   # Setup external Backstage integration
./scripts/apply-data-protection.sh   # Apply data loss protection policies
./scripts/uninstall-idp.sh           # Complete platform removal

# Configuration management
export SHOW_CONFIG=false            # Skip configuration summary in idp.sh setup
export SETUP_BACKSTAGE=false        # Skip Backstage setup during platform startup
```

### Version Management Commands
```bash
# Component versioning and rollback capabilities
./scripts/idp.sh versions           # List versions for all components
./scripts/idp.sh versions <comp>    # List versions for specific component
./scripts/idp.sh update <comp> --version <ver> [--dry-run]  # Update component version
./scripts/idp.sh rollback <comp> [--steps <n>]              # Rollback component

# Multi-Instance Management
./scripts/idp.sh instances list     # List all IDP instances
./scripts/idp.sh instances create <env>  # Create new IDP instance
./scripts/idp.sh instances promote <source> <target>  # Promote between instances
```

### Credential Management
```bash
# Interactive credential setup and management
./scripts/idp.sh credentials setup  # Interactive credential configuration
./scripts/idp.sh credentials apply  # Apply credential configurations
./scripts/idp.sh credentials generate  # Generate credentials only
```

## Architecture Components

### Core Infrastructure Stack

- **Kubernetes**: Container orchestration (Docker Desktop/Kind/Minikube)
- **ArgoCD**: GitOps-based continuous deployment at localhost:8080
- **Backstage**: Developer portal and service catalog at localhost:3000
- **Istio**: Service mesh for traffic management, security (mTLS), observability
- **External LocalStack**: AWS service emulation (Cognito, ECR, RDS, Secrets Manager)
- **Crossplane**: Infrastructure as Code with hybrid LocalStack/AWS providers
- **External Secrets Operator**: Kubernetes secrets management
- **Argo Workflows**: Kubernetes-native CI for container builds
- **Unleash OSS**: Feature flag management and progressive deployment

### Platform Abstractions
The platform's primary abstraction is the **WebApplication CRD** (`platform/crds/webapplication-crd.yaml`) which automatically generates:
- Kubernetes Deployments and Services
- Istio VirtualService and Gateway configurations  
- HorizontalPodAutoscaler settings
- Crossplane resource claims (databases, storage)

### Multi-Instance Architecture (NEW)
- **IDPInstance CRD**: Manages multiple environment instances (dev/staging/prod)
- **InstancePromotion CRD**: Handles cross-environment deployments with validation
- **Instance Controller**: Automated lifecycle management and health monitoring
- **Cross-Instance Communication**: Service discovery and secrets synchronization

### Directory Structure
- `applications/`: ArgoCD applications and GitOps configurations
- `infrastructure/`: Core platform infrastructure (Istio, auth, etc.)
- `platform/`: Custom CRDs, operators, workflows, and backend services
- `platform/multi-instance/`: Multi-instance management components (NEW)
- `scripts/`: Automation scripts for platform lifecycle management
- `docs/`: Comprehensive architecture and implementation documentation

### External Repositories
- `../idp-backstage-app/`: Separate Backstage application repository (TypeScript/Node.js)
  - Automatically cloned and integrated by platform scripts
  - Independent development and versioning
  - Built and deployed via platform automation

### Environment Strategy
- **Local Development**: LocalStack + Kubernetes (Docker Desktop/Kind)
- **Staging**: AWS with reduced resources
- **Production**: Full AWS infrastructure
- **Multi-Instance**: Automated promotion workflows between environments
- **Consistency**: Same GitOps configurations across all environments

### Authentication & Security
- **AWS Cognito**: Centralized OAuth/OIDC authentication for all services
- **Test Accounts**: admin/TempPassword123!, developer/TempPassword123!
- **Istio mTLS**: Service-to-service encryption
- **JWT Validation**: Token-based API security
- **cert-manager**: Automatic certificate lifecycle management

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
- **Unleash OSS**: http://localhost:4243 (Feature flag management - admin / unleash4all)
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

## 🔐 **ArgoCD SSL Certificate Management (JUST COMPLETED)**

**Status**: Production-ready SSL certificate infrastructure with cert-manager integration

### **Complete Certificate Management System**
- **cert-manager Integration**: Automated certificate generation, renewal, and lifecycle management  
- **Self-Signed CA**: Dedicated Certificate Authority for ArgoCD and platform services
- **ArgoCD HTTPS**: Secure TLS communication replacing insecure mode
- **Backstage Integration**: Trusted certificate sharing for API communication
- **LocalStack Backup**: Certificate persistence via AWS Secrets Manager emulation

### **Automated Certificate Lifecycle**
1. **Platform Setup**: `./scripts/idp.sh setup` automatically configures certificates
2. **cert-manager Installation**: Deploys via ArgoCD application with Helm chart  
3. **CA Generation**: Creates self-signed root CA for platform services
4. **ArgoCD Certificates**: Server and gRPC certificates with proper DNS names
5. **Backstage Trust**: Automatic CA certificate synchronization for API calls
6. **LocalStack Storage**: Daily backup and startup restore of certificates

### **Certificate Commands**
```bash
# Automatic certificate setup during platform deployment
./scripts/idp.sh setup  

# Manual certificate operations
./scripts/idp.sh setup-certificates      # Setup certificates manually
./scripts/idp.sh verify-certificates     # Verify certificate status

# Direct certificate management
./scripts/setup-argocd-certificates.sh setup
./scripts/setup-argocd-certificates.sh verify
```

### **Integration Benefits**
- **Secure ArgoCD Communication**: HTTPS instead of insecure mode
- **Backstage API Trust**: Eliminates self-signed certificate errors  
- **Production Ready**: Proper TLS configuration with certificate validation
- **Automatic Renewal**: cert-manager handles certificate lifecycle (90-day server certs, 1-year CA)
- **Platform Consistency**: Unified certificate management across all services
- **LocalStack Integration**: Certificate backup/restore for development consistency

### **Certificate Architecture**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   cert-manager  │    │   ArgoCD CA     │    │ ArgoCD Server   │
│   (Automated)   │───▶│   Certificate   │───▶│   Certificate   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │   Backstage     │    │   LocalStack    │  
                       │   CA Trust      │    │   Backup        │
                       └─────────────────┘    └─────────────────┘
```

**The platform now provides enterprise-grade TLS security for all ArgoCD communications!** 🔐

### 🎯 **Unleash OSS Feature Flag Integration (JUST COMPLETED)**

**Status**: Fully integrated feature flag management system

#### **Complete Integration Flow**
- **Setup Phase**: Workflow templates deployed automatically via `./scripts/deploy-workflow-templates.sh`
- **Start Phase**: Unleash automatically built, deployed, and port-forwarded when `./scripts/idp.sh start` runs
- **GitOps Management**: ArgoCD applications for full lifecycle management
- **Service Mesh**: Istio integration with mTLS and traffic policies

#### **Automated Deployment Process**
1. **Platform Start**: `./scripts/idp.sh start` detects missing Unleash deployment
2. **Build Trigger**: Automatically submits Unleash build workflow using official Unleash image
3. **Deployment**: Static manifests ensure Unleash and PostgreSQL are deployed
4. **Service Discovery**: Port-forward automatically configured on http://localhost:4243
5. **Status Integration**: Full visibility in `./scripts/idp.sh status` command

#### **Developer Experience**
```bash
# Unleash automatically included in platform startup
./scripts/idp.sh start

# Manual build/rebuild if needed
./scripts/idp.sh build-unleash

# Access Unleash
curl http://localhost:4243/health  # API health check
open http://localhost:4243         # Web interface (admin / unleash4all)
```

#### **Platform Integration Benefits**
- **Zero Configuration**: Unleash automatically deployed with platform
- **Production Ready**: PostgreSQL backend with persistent storage
- **Service Mesh Security**: Istio mTLS between services
- **GitOps Managed**: ArgoCD handles deployment lifecycle
- **Observability**: Integrated with platform monitoring and tracing
- **Developer Self-Service**: Feature flag management UI and APIs