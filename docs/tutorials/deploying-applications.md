# Deploying Applications on IDP Platform

## Overview

This tutorial covers various methods and strategies for deploying applications on the IDP platform, from simple deployments to advanced patterns like blue-green and canary deployments.

## Table of Contents

1. [Basic Application Deployment](#basic-application-deployment)
2. [Multi-Environment Deployment](#multi-environment-deployment)
3. [Advanced Deployment Strategies](#advanced-deployment-strategies)
4. [Database Integration](#database-integration)
5. [Monitoring and Observability](#monitoring-and-observability)
6. [Troubleshooting Deployments](#troubleshooting-deployments)

## Basic Application Deployment

### Using Backstage Portal (Recommended for Beginners)

#### Step 1: Create Application from Template

1. Navigate to Backstage: `http://localhost:3000`
2. Click **"Create Component"**
3. Select **"IDP Web Application"** template
4. Fill in application details:

```yaml
# Application Configuration
name: hello-world-app
description: A simple Hello World application
owner: platform-team
technology: nodejs
repository: https://github.com/yourorg/hello-world-app
```

#### Step 2: Configure Application Specifications

```yaml
# WebApplication CRD specification
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: hello-world-app
  namespace: development
spec:
  appName: hello-world-app
  image: your-registry/hello-world-app:latest
  port: 3000
  
  # Resource specifications
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  
  # Scaling configuration
  replicas: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilization: 70
  
  # Health checks
  healthCheck:
    path: /health
    port: 3000
    initialDelaySeconds: 30
    periodSeconds: 10
  
  # Environment variables
  environment:
    - name: NODE_ENV
      value: "production"
    - name: PORT
      value: "3000"
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: url
```

#### Step 3: Commit and Deploy

```bash
# The platform automatically handles:
# 1. Git repository creation
# 2. CI/CD pipeline setup
# 3. Container image building
# 4. Kubernetes deployment
# 5. Service mesh configuration
# 6. Monitoring setup

# Check deployment status in ArgoCD
argocd app list
argocd app get hello-world-app
```

### Using kubectl (Advanced Users)

#### Step 1: Create Application Manifest

```yaml
# hello-world-app.yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: hello-world-app
  namespace: development
  labels:
    app.kubernetes.io/name: hello-world-app
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: web
spec:
  appName: hello-world-app
  image: your-registry/hello-world-app:v1.0.0
  port: 3000
  
  ingress:
    enabled: true
    host: hello-world.idp.local
    tls:
      enabled: true
      secretName: hello-world-tls
  
  monitoring:
    enabled: true
    path: /metrics
    port: 9090
```

#### Step 2: Apply Manifest

```bash
# Apply the WebApplication CRD
kubectl apply -f hello-world-app.yaml

# Verify creation
kubectl get webapplications -n development
kubectl describe webapplication hello-world-app -n development

# Check generated resources
kubectl get pods,svc,ing -n development -l app=hello-world-app
```

## Multi-Environment Deployment

### Environment Strategy

The platform supports three environments with automatic promotion:

```
Development → Staging → Production
```

### Environment Configuration

#### Development Environment

```yaml
# overlays/development/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patchesStrategicMerge:
  - webapplication-patch.yaml

namePrefix: dev-
namespace: development

images:
  - name: hello-world-app
    newTag: latest
```

```yaml
# overlays/development/webapplication-patch.yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: hello-world-app
spec:
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
  environment:
    - name: NODE_ENV
      value: "development"
    - name: LOG_LEVEL
      value: "debug"
```

#### Staging Environment

```yaml
# overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patchesStrategicMerge:
  - webapplication-patch.yaml

namePrefix: staging-
namespace: staging

images:
  - name: hello-world-app
    newTag: v1.0.0-rc.1
```

```yaml
# overlays/staging/webapplication-patch.yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: hello-world-app
spec:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
  environment:
    - name: NODE_ENV
      value: "staging"
    - name: LOG_LEVEL
      value: "info"
  ingress:
    host: hello-world-staging.idp.local
```

#### Production Environment

```yaml
# overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patchesStrategicMerge:
  - webapplication-patch.yaml

namePrefix: prod-
namespace: production

images:
  - name: hello-world-app
    newTag: v1.0.0
```

```yaml
# overlays/production/webapplication-patch.yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: hello-world-app
spec:
  replicas: 3
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
    targetCPUUtilization: 60
  environment:
    - name: NODE_ENV
      value: "production"
    - name: LOG_LEVEL
      value: "warn"
  ingress:
    host: hello-world.company.com
```

### Automated Promotion Pipeline

```yaml
# .github/workflows/deploy.yml
name: Deploy Application

on:
  push:
    branches: [main]
  release:
    types: [published]

jobs:
  deploy-development:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to Development
        run: |
          # Update image tag
          kustomize edit set image hello-world-app=registry/hello-world-app:${{ github.sha }}
          # Commit changes
          git add . && git commit -m "Deploy ${{ github.sha }} to development"
          git push

  deploy-staging:
    runs-on: ubuntu-latest
    if: github.event_name == 'release' && github.event.action == 'published'
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to Staging
        run: |
          cd overlays/staging
          kustomize edit set image hello-world-app=registry/hello-world-app:${{ github.event.release.tag_name }}
          git add . && git commit -m "Deploy ${{ github.event.release.tag_name }} to staging"
          git push

  deploy-production:
    runs-on: ubuntu-latest
    needs: [integration-tests]
    if: github.event_name == 'release' && github.event.action == 'published'
    environment: production
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to Production
        run: |
          cd overlays/production
          kustomize edit set image hello-world-app=registry/hello-world-app:${{ github.event.release.tag_name }}
          git add . && git commit -m "Deploy ${{ github.event.release.tag_name }} to production"
          git push
```

## Advanced Deployment Strategies

### Blue-Green Deployment

Blue-green deployment ensures zero-downtime deployments by maintaining two identical production environments.

#### Step 1: Configure Blue-Green Setup

```yaml
# blue-green-webapplication.yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: hello-world-app
  namespace: production
spec:
  deploymentStrategy:
    type: BlueGreen
    blueGreen:
      # Active version
      activeService: hello-world-blue
      # Preview version
      previewService: hello-world-green
      # Traffic switching
      autoPromotionEnabled: false
      # Rollback window
      scaleDownDelaySeconds: 300
  
  # Blue version (currently active)
  blue:
    image: registry/hello-world-app:v1.0.0
    replicas: 3
  
  # Green version (new deployment)
  green:
    image: registry/hello-world-app:v1.1.0
    replicas: 3
```

#### Step 2: Deploy New Version

```bash
# Deploy to green environment
kubectl patch webapplication hello-world-app -n production --type='merge' -p='{
  "spec": {
    "green": {
      "image": "registry/hello-world-app:v1.1.0"
    }
  }
}'

# Verify green deployment
kubectl get pods -n production -l version=green

# Test green environment
curl -H "Host: hello-world.company.com" http://green-hello-world.company.com/health
```

#### Step 3: Traffic Switching

```bash
# Switch traffic to green (manual)
kubectl patch webapplication hello-world-app -n production --type='merge' -p='{
  "spec": {
    "deploymentStrategy": {
      "blueGreen": {
        "activeService": "hello-world-green"
      }
    }
  }
}'

# Verify traffic switch
curl -H "Host: hello-world.company.com" http://hello-world.company.com/version

# Scale down blue after validation
kubectl patch webapplication hello-world-app -n production --type='merge' -p='{
  "spec": {
    "blue": {
      "replicas": 0
    }
  }
}'
```

### Canary Deployment

Canary deployment gradually shifts traffic from old to new version.

#### Step 1: Configure Canary Deployment

```yaml
# canary-webapplication.yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: hello-world-app
  namespace: production
spec:
  deploymentStrategy:
    type: Canary
    canary:
      # Canary traffic percentage
      weight: 10
      # Step configuration
      steps:
        - setWeight: 10
        - pause: {duration: 600}  # 10 minutes
        - setWeight: 25
        - pause: {duration: 600}  # 10 minutes
        - setWeight: 50
        - pause: {duration: 600}  # 10 minutes
        - setWeight: 100
      
      # Automatic rollback triggers
      analysis:
        successRate:
          threshold: 95
        latency:
          threshold: 500ms
        errorRate:
          threshold: 5
```

#### Step 2: Start Canary Deployment

```bash
# Deploy canary version
kubectl patch webapplication hello-world-app -n production --type='merge' -p='{
  "spec": {
    "canary": {
      "image": "registry/hello-world-app:v1.1.0"
    }
  }
}'

# Monitor canary metrics
kubectl get analysis -n production
kubectl describe analysis hello-world-app-canary -n production
```

#### Step 3: Monitor and Control

```bash
# Check canary progress
kubectl get rollout hello-world-app -n production

# Manual promotion (skip waiting)
kubectl argo rollouts promote hello-world-app -n production

# Manual rollback
kubectl argo rollouts abort hello-world-app -n production
```

## Database Integration

### PostgreSQL Database

#### Step 1: Define Database Requirements

```yaml
# webapplication-with-db.yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: user-service
  namespace: production
spec:
  appName: user-service
  image: registry/user-service:v1.0.0
  
  # Database configuration
  database:
    type: postgresql
    version: "13"
    storage: "20Gi"
    storageClass: "gp3-ssd"
    
    # High availability
    replicas: 2
    
    # Backup configuration
    backup:
      enabled: true
      schedule: "0 2 * * *"  # Daily at 2 AM
      retention: "7d"
    
    # Resource limits
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2000m
        memory: 4Gi
  
  # Application database connection
  environment:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: user-service-db-credentials
          key: url
    - name: DB_HOST
      valueFrom:
        secretKeyRef:
          name: user-service-db-credentials
          key: host
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: user-service-db-credentials
          key: password
```

#### Step 2: Database Migration

```yaml
# database-migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: user-service-migration
  namespace: production
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: migration
        image: registry/user-service:v1.0.0
        command: ["npm", "run", "migrate"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: user-service-db-credentials
              key: url
```

```bash
# Run migration
kubectl apply -f database-migration-job.yaml

# Monitor migration
kubectl logs job/user-service-migration -n production -f

# Verify migration success
kubectl get jobs -n production
```

### Redis Cache Integration

```yaml
# webapplication-with-redis.yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: user-service
spec:
  cache:
    type: redis
    version: "6.2"
    replicas: 3  # Redis Cluster
    storage: "5Gi"
    
    # Performance tuning
    maxMemoryPolicy: "allkeys-lru"
    
    # High availability
    sentinel:
      enabled: true
      replicas: 3
  
  environment:
    - name: REDIS_URL
      valueFrom:
        secretKeyRef:
          name: user-service-redis-credentials
          key: url
```

## Monitoring and Observability

### Application Metrics

#### Custom Metrics Configuration

```yaml
# monitoring-config.yaml
apiVersion: platform.idp/v1alpha1
kind: WebApplication
metadata:
  name: user-service
spec:
  monitoring:
    enabled: true
    
    # Prometheus scraping
    prometheus:
      path: /metrics
      port: 9090
      interval: 30s
    
    # Custom dashboards
    dashboards:
      - name: user-service-overview
        queries:
          - name: request_rate
            query: 'sum(rate(http_requests_total{app="user-service"}[5m]))'
          - name: error_rate
            query: 'sum(rate(http_requests_total{app="user-service",status=~"5.."}[5m]))'
          - name: response_time
            query: 'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{app="user-service"}[5m])) by (le))'
    
    # Custom alerts
    alerts:
      - name: HighErrorRate
        expr: 'sum(rate(http_requests_total{app="user-service",status=~"5.."}[5m])) > 0.1'
        for: 2m
        severity: critical
        message: "User service has high error rate"
      
      - name: HighLatency
        expr: 'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{app="user-service"}[5m])) by (le)) > 1'
        for: 5m
        severity: warning
        message: "User service has high latency"
```

#### Health Check Configuration

```yaml
# Application health checks
spec:
  healthCheck:
    # Readiness probe
    readiness:
      httpGet:
        path: /health/ready
        port: 3000
      initialDelaySeconds: 10
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
    
    # Liveness probe
    liveness:
      httpGet:
        path: /health/live
        port: 3000
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    
    # Startup probe (for slow-starting apps)
    startup:
      httpGet:
        path: /health/startup
        port: 3000
      initialDelaySeconds: 0
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 30
```

### Distributed Tracing

```javascript
// Application tracing setup (Node.js example)
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { JaegerExporter } = require('@opentelemetry/exporter-jaeger');

const sdk = new NodeSDK({
  traceExporter: new JaegerExporter({
    endpoint: 'http://jaeger-collector.istio-system:14268/api/traces',
  }),
  serviceName: 'user-service',
});

sdk.start();
```

## Troubleshooting Deployments

### Common Issues and Solutions

#### 1. Image Pull Errors

```bash
# Check image pull secrets
kubectl get secrets -n <namespace> | grep docker

# Describe pod for detailed error
kubectl describe pod <pod-name> -n <namespace>

# Verify image exists
docker pull <image-name>

# Solution: Update image pull secrets
kubectl create secret docker-registry regcred \
  --docker-server=<registry-server> \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email>
```

#### 2. Resource Constraints

```bash
# Check node resources
kubectl top nodes

# Check pod resource usage
kubectl top pods -n <namespace>

# Describe pod for resource issues
kubectl describe pod <pod-name> -n <namespace>

# Solution: Adjust resource requests/limits
kubectl patch webapplication <app-name> -n <namespace> --type='merge' -p='{
  "spec": {
    "resources": {
      "requests": {"cpu": "100m", "memory": "256Mi"},
      "limits": {"cpu": "500m", "memory": "512Mi"}
    }
  }
}'
```

#### 3. Configuration Issues

```bash
# Check configmaps and secrets
kubectl get cm,secrets -n <namespace>

# Verify environment variables
kubectl exec -n <namespace> <pod-name> -- env

# Check mounted volumes
kubectl describe pod <pod-name> -n <namespace>

# Solution: Update configuration
kubectl patch webapplication <app-name> -n <namespace> --type='merge' -p='{
  "spec": {
    "environment": [
      {"name": "NEW_VAR", "value": "new-value"}
    ]
  }
}'
```

#### 4. Network Connectivity

```bash
# Check service endpoints
kubectl get endpoints -n <namespace>

# Test service connectivity
kubectl exec -n <namespace> <pod-name> -- curl -v http://<service-name>:<port>

# Check Istio configuration
istioctl analyze -n <namespace>

# Verify virtual services
kubectl get virtualservice -n <namespace>
```

### Debugging Commands

```bash
# Comprehensive health check
kubectl get all -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
kubectl top pods -n <namespace>

# Application logs
kubectl logs -n <namespace> -l app=<app-name> --tail=100 -f

# Get into pod for debugging
kubectl exec -it -n <namespace> <pod-name> -- /bin/bash

# Port forward for local testing
kubectl port-forward -n <namespace> svc/<service-name> 8080:80

# Check ArgoCD sync status
argocd app get <app-name>
argocd app diff <app-name>
```

## Best Practices

### Deployment Best Practices

1. **Use Health Checks**: Always implement readiness and liveness probes
2. **Resource Limits**: Set appropriate CPU and memory limits
3. **Graceful Shutdown**: Handle SIGTERM signals properly
4. **Rolling Updates**: Use rolling update strategy for zero-downtime
5. **Configuration Management**: Use ConfigMaps and Secrets for configuration

### Security Best Practices

1. **Least Privilege**: Use minimal required permissions
2. **Non-Root User**: Run containers as non-root user
3. **Image Scanning**: Scan images for vulnerabilities
4. **Network Policies**: Implement network segmentation
5. **Secret Management**: Use External Secrets Operator

### Performance Best Practices

1. **Right-sizing**: Monitor and adjust resource allocations
2. **Caching**: Implement appropriate caching strategies
3. **Connection Pooling**: Use connection pooling for databases
4. **Horizontal Scaling**: Use HPA for automatic scaling
5. **CDN**: Use CDN for static assets

This comprehensive guide covers all aspects of deploying applications on the IDP platform. For more specific scenarios or advanced configurations, refer to the platform documentation or contact the platform team.