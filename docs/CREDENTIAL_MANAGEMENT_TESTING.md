# 🧪 Testing Interactive Credential Management System

## 🎯 Quick Test Plan

### **1. Start Platform (In New Terminal)**
```bash
cd idp-platform

# Option 1: Quick start (uses existing credentials if available)
./scripts/idp.sh start

# Option 2: Fresh setup with new credentials
./scripts/idp.sh setup
```

### **2. Test Credential Manager (In Current Terminal)**
```bash
# Interactive credential setup
./scripts/idp.sh credentials setup

# Or directly
./scripts/credential-manager.sh interactive
```

### **3. Test Developer Onboarding**
```bash
# Add a test developer
./scripts/developer-onboarding.sh interactive

# Test with sample user:
# Username: john.doe
# Email: john@test.com
# Full Name: John Doe
```

## 🔍 What to Validate

### **Credential Manager Tests:**
- ✅ Password complexity validation
- ✅ Auto-generation of secure passwords
- ✅ AWS Cognito configuration (if enabled)
- ✅ Kubernetes secret generation
- ✅ File permissions (600 for credentials.yaml)

### **Generated Files to Check:**
```bash
# Check credential files were created
ls -la .idp-config/credentials.yaml
ls -la secrets/generated/

# Verify Kubernetes secrets (after platform is running)
kubectl get secrets -n argocd argocd-admin-credentials
kubectl get secrets -n monitoring grafana-admin-credentials
kubectl get secrets -n idp-system platform-service-secrets
```

### **Platform Integration Tests:**
- ✅ ArgoCD login with generated credentials
- ✅ Grafana login with generated credentials  
- ✅ Backstage OAuth (if Cognito enabled)
- ✅ Service-to-service authentication working

### **Developer Onboarding Tests:**
- ✅ Kubernetes namespace creation (dev-john-doe)
- ✅ RBAC policies applied correctly
- ✅ Resource quotas enforced
- ✅ Backstage user entity created
- ✅ Cognito user created (if enabled)

## 🐛 Common Issues & Fixes

### **Issue: kubectl not accessible**
```bash
# Make sure kubectl is configured
kubectl cluster-info

# If using Docker Desktop, ensure Kubernetes is enabled
```

### **Issue: yq tool missing**
```bash
# Install yq for YAML processing
pip install yq
# OR
brew install yq
```

### **Issue: AWS CLI not configured (for Cognito)**
```bash
# Configure AWS CLI for LocalStack
aws configure set aws_access_key_id test
aws configure set aws_secret_access_key test
aws configure set region us-east-1
aws configure set endpoint_url http://localhost:4566
```

### **Issue: Permissions error**
```bash
# Fix credential file permissions
chmod 600 .idp-config/credentials.yaml
```

## ⚡ Quick Validation Commands

```bash
# 1. Test platform startup
./scripts/idp.sh status

# 2. Test credential management
./scripts/idp.sh credentials setup

# 3. Test developer onboarding  
./scripts/developer-onboarding.sh interactive

# 4. Test versioning (from previous task)
./scripts/idp.sh versions

# 5. Health check all components
./scripts/health-check.sh
```

## 🎯 Success Criteria

**✅ Credential Manager Working:**
- Interactive prompts appear correctly
- Password validation enforces complexity
- Kubernetes secrets generated properly
- Files created with correct permissions

**✅ Platform Integration Working:**
- Can login to ArgoCD with generated credentials
- Can login to Grafana with generated credentials
- Services start up successfully
- No authentication errors in logs

**✅ Developer Onboarding Working:**
- Developer namespace created
- RBAC permissions applied
- Resource quotas enforced
- Backstage user entity appears

## 📋 Test Results Template

```
[ ] Credential manager interactive flow completed
[ ] Generated passwords meet complexity requirements  
[ ] Kubernetes secrets applied successfully
[ ] ArgoCD accessible with generated credentials
[ ] Grafana accessible with generated credentials
[ ] Developer onboarding creates namespace
[ ] Developer onboarding creates RBAC
[ ] Backstage shows new user entity
[ ] Platform health check passes
[ ] No errors in component logs
```

Let me know how the testing goes! 🚀