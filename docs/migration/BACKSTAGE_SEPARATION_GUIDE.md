# Backstage Application Separation Guide

This guide documents the separation of the Backstage application from the main IDP platform repository to enable independent development and deployment.

## Overview

**Before**: Backstage application was embedded within the IDP platform at `idp-platform/backstage-app-real/backstage/`

**After**: Backstage application is now in a separate repository `idp-backstage-app/` with automated integration into the platform.

## Benefits of Separation

1. **Independent Development**: Backstage team can develop independently from platform infrastructure
2. **Parallel Evolution**: Both repositories can evolve at their own pace
3. **Clear Responsibilities**: Cleaner separation of concerns between platform and application
4. **Easier Maintenance**: Focused development and testing for each component
5. **Version Independence**: Backstage can have its own release cycle

## Migration Process

### 1. Repository Structure Changes

#### Old Structure
```
idp-platform/
├── backstage-app-real/
│   └── backstage/          # Backstage application code
│       ├── package.json
│       ├── packages/
│       ├── plugins/
│       └── Dockerfile.*
├── applications/
├── platform/
└── scripts/
```

#### New Structure
```
idp-platform/                      # Platform repository
├── applications/                  # Platform applications
├── platform/                     # Platform services
├── scripts/
│   └── setup-backstage-external.sh  # NEW: External Backstage integration
└── docs/

idp-backstage-app/                 # NEW: Separate Backstage repository
├── package.json
├── packages/
├── plugins/
├── Dockerfile                     # Optimized for external builds
└── README.md                      # Backstage-specific documentation
```

### 2. Integration Workflow Changes

#### Before (Embedded)
1. Platform startup directly built embedded Backstage
2. Argo Workflows referenced local `backstage-app-real/` path
3. Deployment manifests pointed to local build artifacts

#### After (External)
1. Platform startup clones external Backstage repository
2. Builds Backstage application independently
3. Pushes container image to platform registry
4. Updates platform deployment manifests
5. ArgoCD syncs and deploys the updated application

### 3. Updated Scripts and Workflows

#### New Script: `setup-backstage-external.sh`
- **Purpose**: Clone, build, and integrate external Backstage repository
- **Features**:
  - Clones or updates Backstage repository
  - Builds application with `yarn build:all`
  - Creates and pushes container image
  - Updates platform deployment manifests
  - Triggers ArgoCD sync

#### Updated: `quick-start.sh`
- **Added**: Automatic external Backstage setup during platform startup
- **Environment Variable**: `SETUP_BACKSTAGE=false` to skip Backstage setup
- **Integration**: Seamless integration with existing platform workflow

#### Updated: Argo Workflows
- **Repository URL**: Changed from platform repo to external Backstage repo
- **Build Context**: Updated paths to reflect new repository structure
- **Image Names**: Standardized to `idp/backstage-app:*`

### 4. Configuration Changes

#### Environment Variables
The external Backstage repository uses the same environment variables as before:
```bash
# Database
POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB

# Authentication
COGNITO_CLIENT_ID, COGNITO_CLIENT_SECRET, COGNITO_USER_POOL_ID, 
COGNITO_AUTH_URL, COGNITO_TOKEN_URL

# Integrations
GITHUB_TOKEN, ARGOCD_TOKEN
```

#### Container Registry
- **Image Name**: Changed from `backstage-app-real` to `idp/backstage-app`
- **Registry**: Same LocalStack ECR registry
- **Tags**: Supports both `latest` and versioned tags

### 5. Development Workflow Changes

#### For Platform Developers
```bash
# Start platform (automatically handles Backstage)
./scripts/quick-start.sh

# Manual Backstage integration (if needed)
./scripts/setup-backstage-external.sh

# Skip Backstage during development
SETUP_BACKSTAGE=false ./scripts/quick-start.sh
```

#### For Backstage Developers
```bash
# Clone the separate repository
git clone https://github.com/your-org/idp-backstage-app.git
cd idp-backstage-app

# Local development
yarn install
yarn start

# Test changes
yarn test:all
yarn lint:all

# Build and test container
docker build -t idp/backstage-app:dev .

# Integrate with platform
cd ../idp-platform
./scripts/setup-backstage-external.sh
```

## Migration Checklist

### ✅ Completed
- [x] Created separate `idp-backstage-app` repository structure
- [x] Moved Backstage code to external repository
- [x] Created `setup-backstage-external.sh` integration script
- [x] Updated `quick-start.sh` to handle external Backstage
- [x] Updated Argo Workflows to reference external repository
- [x] Updated platform documentation and CLAUDE.md
- [x] Created optimized Dockerfile for external builds

### 🔄 In Progress
- [ ] Update ArgoCD applications for external deployment
- [ ] Test complete integration workflow
- [ ] Validate container builds and deployments

### 📋 To Do
- [ ] Create GitHub repository for `idp-backstage-app`
- [ ] Setup CI/CD pipeline for Backstage repository
- [ ] Update platform monitoring for external integration
- [ ] Create version compatibility matrix
- [ ] Update team documentation and training

## Configuration Reference

### Repository URLs
```bash
# Platform Repository
PLATFORM_REPO="https://github.com/your-org/idp-platform"

# Backstage Repository (NEW)
BACKSTAGE_REPO="https://github.com/your-org/idp-backstage-app"
```

### Environment Variables for Integration
```bash
# External Backstage Repository Configuration
BACKSTAGE_REPO_URL="https://github.com/your-org/idp-backstage-app"
BACKSTAGE_BRANCH="main"
BACKSTAGE_IMAGE_TAG="latest"

# Skip Backstage setup during platform startup
SETUP_BACKSTAGE="false"
```

### Container Image Configuration
```bash
# Registry
REGISTRY="000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566"

# Image Name
IMAGE_NAME="idp/backstage-app"

# Full Image Reference
IMAGE_REF="${REGISTRY}/${IMAGE_NAME}:${TAG}"
```

## Troubleshooting

### Common Issues

**Issue**: `setup-backstage-external.sh` fails to clone repository
- **Solution**: Verify repository URL and access permissions
- **Check**: `git clone https://github.com/your-org/idp-backstage-app.git`

**Issue**: Container build fails with missing dependencies
- **Solution**: Ensure all dependencies are in `package.json`
- **Check**: Run `yarn install` and `yarn build:all` locally

**Issue**: ArgoCD deployment fails after integration
- **Solution**: Check image reference in deployment manifest
- **Verify**: `kubectl get deployment backstage -n backstage -o yaml`

**Issue**: Platform startup hangs during Backstage setup
- **Solution**: Skip Backstage setup temporarily: `SETUP_BACKSTAGE=false ./scripts/quick-start.sh`
- **Debug**: Run `./scripts/setup-backstage-external.sh` manually

### Debugging Commands

```bash
# Check Backstage repository status
ls -la ../idp-backstage-app/

# Verify container image
docker images | grep idp/backstage-app

# Check deployment status
kubectl get pods -n backstage
kubectl describe deployment backstage -n backstage

# View integration logs
kubectl logs -n backstage deployment/backstage -f
```

## Future Enhancements

1. **CI/CD Pipeline**: Add GitHub Actions for Backstage repository
2. **Version Management**: Implement semantic versioning for Backstage releases
3. **Automated Testing**: Add integration tests between platform and Backstage
4. **Multi-Environment**: Support for staging and production Backstage variants
5. **Plugin Development**: Dedicated workflow for custom Backstage plugins

## Support

For questions or issues related to the separation:
1. Check this guide and troubleshooting section
2. Review the updated platform documentation
3. Test integration workflow manually
4. Create issues in the appropriate repository (platform vs. Backstage)