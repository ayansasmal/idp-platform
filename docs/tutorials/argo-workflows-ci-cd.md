# Argo Workflows CI/CD for Container Builds

## Overview

The IDP platform now includes Argo Workflows for building and pushing container images directly within the cluster. This eliminates the need for external CI systems and provides a complete GitOps experience.

## 🚀 Key Benefits

- **Internal CI/CD**: Build images within the Kubernetes cluster
- **Self-Service**: Engineers trigger builds through Backstage
- **GitOps Native**: Workflows managed as code in Git
- **Unified Platform**: No external CI dependencies
- **Scalable**: Kubernetes-native auto-scaling
- **Secure**: Runs with RBAC and service mesh security

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Backstage     │───▶│  Argo Workflows  │───▶│   LocalStack    │
│  (Self-Service) │    │   (Build Engine)  │    │      ECR        │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                       │
         ▼                        ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Git Repo      │    │   Docker Build   │    │   ArgoCD        │
│  (Source Code)  │    │   (In Cluster)   │    │  (Deployment)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🌐 Accessing Argo Workflows

Once the platform is running, access Argo Workflows at:
- **Workflows UI**: http://localhost:4000/workflows
- **Direct Access**: http://localhost:2746

The UI is automatically port-forwarded by the platform automation scripts.

## 📋 Available Workflow Templates

### 1. General Docker Build (`docker-build-push`)

**Purpose**: Build any Docker application from Git repository

**Parameters**:
- `repo-url`: Git repository URL
- `revision`: Branch/tag to build (default: main)
- `image-name`: Name of the Docker image
- `image-tag`: Tag for the image (default: latest)
- `dockerfile-path`: Path to Dockerfile (default: Dockerfile)
- `build-context`: Docker build context (default: .)

**Usage via CLI**:
```bash
argo submit --from workflowtemplate/docker-build-push \
  -p repo-url=https://github.com/your-org/your-app.git \
  -p image-name=my-app \
  -p image-tag=v1.0.0
```

### 2. Backstage Application Build (`backstage-app-build`)

**Purpose**: Build Backstage applications with Node.js compilation

**Parameters**:
- `repo-url`: Git repository URL
- `revision`: Branch/tag to build (default: main)
- `app-name`: Backstage application name
- `image-tag`: Tag for the image (default: latest)
- `dockerfile`: Dockerfile to use (default: Dockerfile.prebuilt)

**Usage via CLI**:
```bash
argo submit --from workflowtemplate/backstage-app-build \
  -p repo-url=https://github.com/your-org/backstage-app.git \
  -p app-name=my-backstage-app \
  -p dockerfile=Dockerfile.prebuilt
```

## 🎯 Self-Service via Backstage

### Using the Docker Image Build Template

1. **Access Backstage**: http://localhost:3000
2. **Navigate to Create**: Click "Create" in sidebar
3. **Select Template**: Choose "Build Docker Image"
4. **Fill Parameters**:
   - Application Name: `my-web-app`
   - Repository URL: Your Git repository
   - Branch: `main` or specific branch
   - Dockerfile Path: `Dockerfile`
   - Build Context: `.`
   - Image Tag: `v1.0.0`
5. **Submit**: Click "Create" to trigger the workflow

### Using the Backstage Application Build Template

1. **Access Backstage**: http://localhost:3000
2. **Navigate to Create**: Click "Create" in sidebar
3. **Select Template**: Choose "Build Backstage Application"
4. **Fill Parameters**:
   - Application Name: `my-backstage-portal`
   - Repository URL: Your Backstage app repository
   - Branch: `main`
   - Dockerfile: `Dockerfile.prebuilt`
   - Auto Sync: `true` (automatically deploy after build)
5. **Submit**: Click "Create" to trigger the workflow

## 🛠️ Manual Workflow Execution

### Using Argo CLI

1. **Install Argo CLI**:
```bash
# On macOS
brew install argo

# On Linux
curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.5.5/argo-linux-amd64.gz
gunzip argo-linux-amd64.gz
chmod +x argo-linux-amd64
sudo mv ./argo-linux-amd64 /usr/local/bin/argo
```

2. **Configure Access**:
```bash
# Port forward to Argo Workflows (if not already done by platform)
kubectl port-forward -n argo-workflows svc/argo-server 2746:2746

# Set ARGO_SERVER
export ARGO_SERVER=localhost:2746
export ARGO_NAMESPACE=argo-workflows
```

3. **Submit Workflow**:
```bash
# Build a general Docker application
argo submit --from workflowtemplate/docker-build-push \
  -p repo-url=https://github.com/nginx/nginx.git \
  -p image-name=my-nginx \
  -p image-tag=custom

# Build a Backstage application
argo submit --from workflowtemplate/backstage-app-build \
  -p repo-url=https://github.com/your-org/backstage-app.git \
  -p app-name=custom-backstage
```

### Using Argo Workflows UI

1. **Access UI**: http://localhost:4000/workflows
2. **Click "Submit New Workflow"**
3. **Select "From Template"**
4. **Choose Template**: `docker-build-push` or `backstage-app-build`
5. **Fill Parameters** in the form
6. **Submit** to start the workflow

## 📊 Monitoring Builds

### Via Argo Workflows UI

1. **Access**: http://localhost:4000/workflows
2. **View Workflows**: See all running/completed workflows
3. **Click Workflow**: View detailed logs and status
4. **Live Logs**: Watch real-time build progress

### Via CLI

```bash
# List workflows
argo list

# Get workflow details
argo get <workflow-name>

# Watch workflow logs
argo logs <workflow-name> -f

# Get workflow status
argo get <workflow-name> -o json | jq .status.phase
```

### Via Grafana Dashboard

Monitor workflow metrics at: http://localhost:3001
- Search for "Argo Workflows" dashboard
- View build success rates, duration, resource usage

## 🔧 Customizing Workflows

### Creating Custom Templates

1. **Create Template File**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: my-custom-build
  namespace: argo-workflows
spec:
  entrypoint: build-custom-app
  # ... template definition
```

2. **Apply Template**:
```bash
kubectl apply -f my-custom-template.yaml
```

3. **Use in Backstage**: Reference in Backstage templates

### Template Best Practices

1. **Resource Limits**: Always set CPU/memory limits
2. **Caching**: Use volume mounts for dependency caches
3. **Secrets**: Use Kubernetes secrets for sensitive data
4. **Error Handling**: Include proper error handling and cleanup
5. **Logging**: Add detailed logging for debugging

## 🔐 Security Configuration

### Service Accounts

Workflows run with specific service accounts:
- `argo-workflow`: Main workflow execution
- `docker-builder`: Docker build operations with ECR access

### RBAC

Workflows have minimal required permissions:
- Pod creation/management in argo-workflows namespace
- Secret access for ECR authentication
- ConfigMap access for build configuration

### Network Security

- All traffic secured with Istio mTLS
- ECR access through LocalStack (no external internet required)
- Workflows isolated in dedicated namespace

## 🐛 Troubleshooting

### Common Issues

1. **Workflow Stuck in Pending**:
   ```bash
   # Check pod status
   kubectl get pods -n argo-workflows
   
   # Check resource constraints
   kubectl describe pod <workflow-pod> -n argo-workflows
   ```

2. **Docker Build Failures**:
   ```bash
   # Check workflow logs
   argo logs <workflow-name> -c docker-build-step
   
   # Verify ECR access
   kubectl exec -it <build-pod> -n argo-workflows -- aws --endpoint-url=http://localstack:4566 ecr describe-repositories
   ```

3. **Template Not Found**:
   ```bash
   # List available templates
   argo template list
   
   # Check template status
   kubectl get workflowtemplate -n argo-workflows
   ```

### Getting Help

- **Workflow Logs**: `argo logs <workflow-name>`
- **Pod Logs**: `kubectl logs <pod-name> -n argo-workflows`
- **Events**: `kubectl get events -n argo-workflows --sort-by='.lastTimestamp'`

## 📈 Performance Optimization

### Build Optimization

1. **Use Multi-stage Builds**: Reduce final image size
2. **Layer Caching**: Order Dockerfile commands efficiently
3. **Resource Allocation**: Tune CPU/memory for build steps
4. **Parallel Builds**: Use workflow parallelism for multi-component apps

### Cluster Resources

```yaml
# Example resource configuration
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "4Gi"
    cpu: "2"
```

## 🔄 Integration with ArgoCD

### Automatic Deployment

Workflows can trigger ArgoCD deployments:

1. **Build Image**: Workflow builds and pushes image
2. **Update Manifest**: Update deployment with new image tag
3. **ArgoCD Sync**: ArgoCD detects changes and deploys
4. **Verification**: Health checks confirm successful deployment

### GitOps Workflow

```
Code Change → Workflow Build → Image Push → Manifest Update → ArgoCD Deploy
```

This completes the full GitOps cycle within the IDP platform!

## 🎓 Next Steps

1. **Explore Templates**: Try different workflow templates
2. **Create Custom Workflows**: Build templates for your specific needs
3. **Monitor Performance**: Use Grafana dashboards to optimize builds
4. **Scale Workflows**: Configure auto-scaling for high-volume builds
5. **Extend Platform**: Add more specialized workflow templates

Happy building! 🚀