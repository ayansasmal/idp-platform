# IDP Platform Access Guide

## Current Status ✅

All services are running correctly! The platform now includes comprehensive automation scripts that eliminate the need for manual port forwarding. The platform is configured with HTTPS/TLS security for production-grade deployments.

**🚀 NEW: Automated Platform Management** - Use the automation scripts for one-command platform startup!

## 🌐 Access Methods

### Method 1: Automated Scripts (⭐ RECOMMENDED)

**One-command platform startup:**

```bash
# Start entire platform with automation
./scripts/quick-start.sh

# Alternative: Advanced management
./scripts/start-platform.sh start

# Platform management commands
./scripts/start-platform.sh status   # Check all services
./scripts/start-platform.sh health   # Health check
./scripts/start-platform.sh stop     # Stop all services
```

**All services automatically accessible at:**
- **ArgoCD**: http://localhost:8080
- **Backstage**: http://localhost:3000  
- **Grafana**: http://localhost:3001
- **Prometheus**: http://localhost:9090
- **Jaeger**: http://localhost:16686
- **Kiali**: http://localhost:20001
- **Monitoring Dashboard**: http://localhost:8090
- **Alertmanager**: http://localhost:9093

### Method 2: Manual Port Forward (Advanced Users)

```bash
# ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:80

# Backstage
kubectl port-forward -n backstage svc/backstage 3000:80

# Grafana
kubectl port-forward -n istio-system svc/grafana 3001:3000

# Prometheus
kubectl port-forward -n istio-system svc/prometheus 9090:9090

# Jaeger
kubectl port-forward -n istio-system svc/jaeger-query 16686:16686

# Kiali
kubectl port-forward -n istio-system svc/kiali 20001:20001

# Monitoring Dashboard
kubectl port-forward -n istio-system svc/monitoring-dashboard 8090:80
```

### Method 3: DNS + HTTPS (Production-like)

Add to your `/etc/hosts` file:
```bash
127.0.0.1 argocd.idp.local
127.0.0.1 backstage.idp.local
127.0.0.1 grafana.idp.local
127.0.0.1 prometheus.idp.local
127.0.0.1 jaeger.idp.local
127.0.0.1 kiali.idp.local
127.0.0.1 monitoring.idp.local
```

Then access via HTTPS:
```bash
# Setup Istio gateway port forward
kubectl port-forward -n istio-system svc/istio-ingressgateway 8443:443

# Access services
https://argocd.idp.local:8443
https://backstage.idp.local:8443
https://grafana.idp.local:8443
https://prometheus.idp.local:8443
https://jaeger.idp.local:8443
https://kiali.idp.local:8443
https://monitoring.idp.local:8443
```

### Method 4: HTTP via Istio Gateway (Simplified)

For development, you can temporarily access via HTTP through the gateway:

```bash
# Setup gateway port forward
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80

# Access with host headers
curl -H "Host: argocd.idp.local" http://localhost:8080
curl -H "Host: backstage.idp.local" http://localhost:8080
curl -H "Host: grafana.idp.local" http://localhost:8080
```

## 🔐 ArgoCD Login

### Get Initial Admin Password

```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Username: admin
# Password: [output from above command]
```

### Login via CLI

```bash
# Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

# Login (using port-forward)
kubectl port-forward -n argocd svc/argocd-server 8080:80 &
argocd login localhost:8080 --username admin --password [password-from-above] --insecure

# List applications
argocd app list
```

## 📊 Quick Platform Health Check

```bash
# Check all platform components
kubectl get pods --all-namespaces | grep -E "(argocd|backstage|istio|grafana|prometheus|kiali|jaeger)"

# Check ArgoCD applications
kubectl get applications -n argocd

# Check Istio gateway
kubectl get gateway -n istio-system
kubectl get virtualservice --all-namespaces
```

## 🛠️ Troubleshooting

### If services are not accessible:

1. **Check pod status:**
```bash
kubectl get pods -n argocd
kubectl get pods -n backstage
kubectl get pods -n istio-system
```

2. **Check service endpoints:**
```bash
kubectl get svc -n argocd
kubectl get svc -n backstage
kubectl get svc -n istio-system
```

3. **Check Istio configuration:**
```bash
istioctl proxy-status
istioctl analyze
```

4. **Check logs:**
```bash
kubectl logs -n argocd deployment/argocd-server
kubectl logs -n istio-system deployment/istio-ingressgateway
```

## 🎯 Quick Start Commands

**🚀 Automated (Recommended):**

```bash
# One command to start everything
./scripts/quick-start.sh

# Platform management
./scripts/start-platform.sh status    # Check all services
./scripts/start-platform.sh health    # Health check  
./scripts/start-platform.sh stop      # Stop all services

# Development shortcuts (after ./scripts/dev-setup.sh)
idp-start          # Start platform
idp-backstage      # Open Backstage
idp-argocd         # Open ArgoCD
idp-grafana        # Open Grafana
```

**📊 Manual (Advanced):**

```bash
# Multiple terminals needed for manual approach
# Terminal 1: ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:80

# Terminal 2: Backstage  
kubectl port-forward -n backstage svc/backstage 3000:80

# Terminal 3: Monitoring
kubectl port-forward -n istio-system svc/grafana 3001:3000

# Terminal 4: Observability
kubectl port-forward -n istio-system svc/monitoring-dashboard 8090:80
```

**🌐 Access URLs:**
- ArgoCD: http://localhost:8080
- Backstage: http://localhost:3000  
- Grafana: http://localhost:3001
- Monitoring Hub: http://localhost:8090

## 🔑 Service Credentials

- **ArgoCD**: admin / [get password with command above]
- **Grafana**: admin / admin (default)
- **PostgreSQL**: backstage / backstage123

Your IDP platform is running successfully! 🎉