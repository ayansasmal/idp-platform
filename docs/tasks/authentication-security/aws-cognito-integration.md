# Claude Code Task: AWS Cognito Authentication Integration

## Task Overview

**Priority**: High  
**Estimated Time**: 2-3 hours  
**Phase**: Authentication & Security (Phase 2)  
**Dependencies**:

- Kubernetes cluster running
- Backstage deployed
- External Secrets Operator installed

## Context

This task integrates AWS Cognito as the primary authentication provider for all IDP platform services (Backstage, ArgoCD, Grafana). This replaces complex enterprise identity providers with a simpler, cloud-native solution.

## Files to Create

1. `secrets/external-secrets/cognito-secrets.yaml` - External secret for Cognito credentials
2. `applications/backstage/cognito-config.yaml` - Backstage Cognito configuration
3. `applications/argocd/cognito-integration.yaml` - ArgoCD OIDC configuration
4. `applications/monitoring/grafana-cognito.yaml` - Grafana OAuth integration
5. `infrastructure/aws/cognito-setup.yaml` - Cognito User Pool configuration

## Files to Update

1. `applications/backstage/backstage-deployment.yaml` - Add Cognito environment variables
2. `applications/argocd/argocd-server.yaml` - Enable OIDC authentication
3. `applications/monitoring/grafana-config.yaml` - Add OAuth configuration

## Prerequisites Check

```bash
# Verify prerequisites
echo "Checking prerequisites..."

# Check if External Secrets Operator is running
if ! kubectl get crd externalsecrets.external-secrets.io &>/dev/null; then
    echo "❌ External Secrets Operator not installed"
    exit 1
fi

# Check if Backstage is deployed
if ! kubectl get deployment backstage -n backstage &>/dev/null; then
    echo "❌ Backstage not deployed"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS credentials not configured"
    exit 1
fi

echo "✅ All prerequisites met"
```

## Implementation Steps

### Step 1: Create AWS Cognito User Pool

```yaml
# File: infrastructure/aws/cognito-setup.yaml
apiVersion: cognito-idp.aws.crossplane.io/v1alpha1
kind: UserPool
metadata:
  name: idp-platform-users
  labels:
    platform.idp/component: authentication
spec:
  forProvider:
    region: us-east-1
    userPoolName: 'IDP-Platform-Users'
    aliasAttributes:
      - email
      - preferred_username
    autoVerifiedAttributes:
      - email
    policies:
      passwordPolicy:
        minimumLength: 8
        requireLowercase: true
        requireNumbers: true
        requireSymbols: true
        requireUppercase: true
    schema:
      - name: email
        attributeDataType: String
        required: true
        mutable: true
      - name: name
        attributeDataType: String
        required: true
        mutable: true
      - name: groups
        attributeDataType: String
        required: false
        mutable: true
    adminCreateUserConfig:
      allowAdminCreateUserOnly: false
    emailConfiguration:
      emailSendingAccount: COGNITO_DEFAULT
    mfaConfiguration: OPTIONAL
    deviceConfiguration:
      challengeRequiredOnNewDevice: true
      deviceOnlyRememberedOnUserPrompt: false
  providerConfigRef:
    name: default

---
apiVersion: cognito-idp.aws.crossplane.io/v1alpha1
kind: UserPoolClient
metadata:
  name: idp-backstage-client
  labels:
    platform.idp/component: authentication
    platform.idp/service: backstage
spec:
  forProvider:
    region: us-east-1
    userPoolIdSelector:
      matchLabels:
        platform.idp/component: authentication
    clientName: 'backstage-client'
    generateSecret: true
    allowedOAuthFlows:
      - code
    allowedOAuthScopes:
      - email
      - openid
      - profile
    allowedOAuthFlowsUserPoolClient: true
    callbackURLs:
      - 'http://backstage.idp.local/api/auth/cognito/handler/frame'
      - 'https://backstage.idp.local/api/auth/cognito/handler/frame'
    logoutURLs:
      - 'http://backstage.idp.local'
      - 'https://backstage.idp.local'
    supportedIdentityProviders:
      - COGNITO
    explicitAuthFlows:
      - ALLOW_USER_PASSWORD_AUTH
      - ALLOW_REFRESH_TOKEN_AUTH
      - ALLOW_USER_SRP_AUTH
  providerConfigRef:
    name: default

---
apiVersion: cognito-idp.aws.crossplane.io/v1alpha1
kind: UserPoolClient
metadata:
  name: idp-argocd-client
  labels:
    platform.idp/component: authentication
    platform.idp/service: argocd
spec:
  forProvider:
    region: us-east-1
    userPoolIdSelector:
      matchLabels:
        platform.idp/component: authentication
    clientName: 'argocd-client'
    generateSecret: true
    allowedOAuthFlows:
      - code
    allowedOAuthScopes:
      - email
      - openid
      - profile
    allowedOAuthFlowsUserPoolClient: true
    callbackURLs:
      - 'http://argocd.idp.local/auth/callback'
      - 'https://argocd.idp.local/auth/callback'
    logoutURLs:
      - 'http://argocd.idp.local'
      - 'https://argocd.idp.local'
    supportedIdentityProviders:
      - COGNITO
    explicitAuthFlows:
      - ALLOW_USER_PASSWORD_AUTH
      - ALLOW_REFRESH_TOKEN_AUTH
      - ALLOW_USER_SRP_AUTH
  providerConfigRef:
    name: default

---
apiVersion: cognito-idp.aws.crossplane.io/v1alpha1
kind: UserPoolClient
metadata:
  name: idp-grafana-client
  labels:
    platform.idp/component: authentication
    platform.idp/service: grafana
spec:
  forProvider:
    region: us-east-1
    userPoolIdSelector:
      matchLabels:
        platform.idp/component: authentication
    clientName: 'grafana-client'
    generateSecret: true
    allowedOAuthFlows:
      - code
    allowedOAuthScopes:
      - email
      - openid
      - profile
    allowedOAuthFlowsUserPoolClient: true
    callbackURLs:
      - 'http://grafana.idp.local/login/oauth'
      - 'https://grafana.idp.local/login/oauth'
    logoutURLs:
      - 'http://grafana.idp.local'
      - 'https://grafana.idp.local'
    supportedIdentityProviders:
      - COGNITO
    explicitAuthFlows:
      - ALLOW_USER_PASSWORD_AUTH
      - ALLOW_REFRESH_TOKEN_AUTH
      - ALLOW_USER_SRP_AUTH
  providerConfigRef:
    name: default
```

### Step 2: Create External Secrets for Cognito Credentials

```yaml
# File: secrets/external-secrets/cognito-secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cognito-secrets
  namespace: backstage
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: cognito-secrets
    creationPolicy: Owner
  data:
    - secretKey: COGNITO_USER_POOL_ID
      remoteRef:
        key: idp-platform/cognito
        property: user_pool_id
    - secretKey: COGNITO_CLIENT_ID
      remoteRef:
        key: idp-platform/cognito
        property: backstage_client_id
    - secretKey: COGNITO_CLIENT_SECRET
      remoteRef:
        key: idp-platform/cognito
        property: backstage_client_secret
    - secretKey: COGNITO_DOMAIN
      remoteRef:
        key: idp-platform/cognito
        property: cognito_domain

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-cognito-secrets
  namespace: argocd
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: argocd-cognito-secrets
    creationPolicy: Owner
  data:
    - secretKey: COGNITO_CLIENT_ID
      remoteRef:
        key: idp-platform/cognito
        property: argocd_client_id
    - secretKey: COGNITO_CLIENT_SECRET
      remoteRef:
        key: idp-platform/cognito
        property: argocd_client_secret

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-cognito-secrets
  namespace: monitoring
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: grafana-cognito-secrets
    creationPolicy: Owner
  data:
    - secretKey: COGNITO_CLIENT_ID
      remoteRef:
        key: idp-platform/cognito
        property: grafana_client_id
    - secretKey: COGNITO_CLIENT_SECRET
      remoteRef:
        key: idp-platform/cognito
        property: grafana_client_secret
```

### Step 3: Configure Backstage Cognito Integration

```yaml
# File: applications/backstage/cognito-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backstage-cognito-config
  namespace: backstage
data:
  app-config.cognito.yaml: |
    auth:
      environment: production
      providers:
        cognito:
          production:
            clientId: ${COGNITO_CLIENT_ID}
            clientSecret: ${COGNITO_CLIENT_SECRET}
            region: us-east-1
            userPoolId: ${COGNITO_USER_POOL_ID}
            identityPoolId: "" # Optional
            signInOptions:
              - username
              - email
            additionalScopes:
              - email
              - profile
              - openid

    signInPage: cognito

    catalog:
      rules:
        - allow: [Component, System, API, Resource, Location, User, Group]
      providers:
        cognito:
          production:
            region: us-east-1
            userPoolId: ${COGNITO_USER_POOL_ID}
            schedule:
              frequency: { minutes: 30 }
              timeout: { minutes: 3 }
```

### Step 4: Update Backstage Deployment

```yaml
# File: applications/backstage/backstage-deployment.yaml
# Add these environment variables to the existing deployment

# Find the existing deployment and add these env vars to the container spec:
env:
  # ... existing environment variables ...
  - name: COGNITO_CLIENT_ID
    valueFrom:
      secretKeyRef:
        name: cognito-secrets
        key: COGNITO_CLIENT_ID
  - name: COGNITO_CLIENT_SECRET
    valueFrom:
      secretKeyRef:
        name: cognito-secrets
        key: COGNITO_CLIENT_SECRET
  - name: COGNITO_USER_POOL_ID
    valueFrom:
      secretKeyRef:
        name: cognito-secrets
        key: COGNITO_USER_POOL_ID
  - name: COGNITO_DOMAIN
    valueFrom:
      secretKeyRef:
        name: cognito-secrets
        key: COGNITO_DOMAIN

# Add the config map as a volume mount
volumeMounts:
  # ... existing volume mounts ...
  - name: cognito-config
    mountPath: /app/app-config.cognito.yaml
    subPath: app-config.cognito.yaml

volumes:
  # ... existing volumes ...
  - name: cognito-config
    configMap:
      name: backstage-cognito-config
```

### Step 5: Configure ArgoCD OIDC

```yaml
# File: applications/argocd/cognito-integration.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cognito-config
  namespace: argocd
data:
  argocd-cm.yaml: |
    url: https://argocd.idp.local
    oidc.config: |
      name: Cognito
      issuer: https://cognito-idp.us-east-1.amazonaws.com/${COGNITO_USER_POOL_ID}
      clientId: ${COGNITO_CLIENT_ID}
      clientSecret: ${COGNITO_CLIENT_SECRET}
      requestedScopes: ["openid", "profile", "email"]
      requestedIDTokenClaims: {"groups": {"essential": true}}

    policy.default: role:readonly
    policy.csv: |
      p, role:admin, applications, *, */*, allow
      p, role:admin, clusters, *, *, allow
      p, role:admin, repositories, *, *, allow
      p, role:readonly, applications, get, */*, allow
      p, role:readonly, applications, sync, */*, allow
      g, platform-admins, role:admin
      g, developers, role:readonly

---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-oidc-secret
  namespace: argocd
type: Opaque
stringData:
  oidc.cognito.clientSecret: ${COGNITO_CLIENT_SECRET}
```

### Step 6: Configure Grafana OAuth

```yaml
# File: applications/monitoring/grafana-cognito.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-cognito-config
  namespace: monitoring
data:
  grafana.ini: |
    [auth.generic_oauth]
    enabled = true
    name = Cognito
    allow_sign_up = true
    client_id = ${COGNITO_CLIENT_ID}
    client_secret = ${COGNITO_CLIENT_SECRET}
    scopes = openid email profile
    empty_scopes = false
    auth_url = https://${COGNITO_DOMAIN}.auth.us-east-1.amazoncognito.com/oauth2/authorize
    token_url = https://${COGNITO_DOMAIN}.auth.us-east-1.amazoncognito.com/oauth2/token
    api_url = https://${COGNITO_DOMAIN}.auth.us-east-1.amazoncognito.com/oauth2/userInfo
    role_attribute_path = contains(groups[*], 'platform-admins') && 'Admin' || 'Viewer'
    allow_assign_grafana_admin = true

    [server]
    root_url = https://grafana.idp.local
```

## Deployment Commands

```bash
# Step 1: Deploy Cognito infrastructure
kubectl apply -f infrastructure/aws/cognito-setup.yaml

# Wait for Cognito resources to be ready
kubectl wait --for=condition=Ready userpool idp-platform-users --timeout=300s

# Step 2: Deploy external secrets
kubectl apply -f secrets/external-secrets/cognito-secrets.yaml

# Wait for secrets to be synced
kubectl wait --for=condition=Ready externalsecret cognito-secrets -n backstage --timeout=120s

# Step 3: Deploy Backstage configuration
kubectl apply -f applications/backstage/cognito-config.yaml

# Step 4: Update Backstage deployment
kubectl apply -f applications/backstage/backstage-deployment.yaml

# Step 5: Deploy ArgoCD configuration
kubectl apply -f applications/argocd/cognito-integration.yaml

# Step 6: Deploy Grafana configuration
kubectl apply -f applications/monitoring/grafana-cognito.yaml

# Restart services to pick up new configuration
kubectl rollout restart deployment/backstage -n backstage
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/grafana -n monitoring
```

## Validation Steps

```bash
# Wait for all deployments to be ready
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/backstage -n backstage --timeout=300s
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl rollout status deployment/grafana -n monitoring --timeout=300s

# Test Backstage authentication
echo "Testing Backstage authentication..."
curl -I http://backstage.idp.local/api/auth/cognito/start
expected_status="302"  # Should redirect to Cognito
actual_status=$(curl -s -o /dev/null -w "%{http_code}" http://backstage.idp.local/api/auth/cognito/start)
if [ "$actual_status" = "$expected_status" ]; then
    echo "✅ Backstage Cognito authentication configured correctly"
else
    echo "❌ Backstage authentication failed - got status $actual_status, expected $expected_status"
fi

# Test ArgoCD authentication
echo "Testing ArgoCD authentication..."
curl -I http://argocd.idp.local/auth/login
actual_status=$(curl -s -o /dev/null -w "%{http_code}" http://argocd.idp.local/auth/login)
if [ "$actual_status" = "200" ]; then
    echo "✅ ArgoCD authentication page accessible"
else
    echo "❌ ArgoCD authentication failed - got status $actual_status"
fi

# Test Grafana authentication
echo "Testing Grafana authentication..."
curl -I http://grafana.idp.local/login
actual_status=$(curl -s -o /dev/null -w "%{http_code}" http://grafana.idp.local/login)
if [ "$actual_status" = "200" ]; then
    echo "✅ Grafana authentication page accessible"
else
    echo "❌ Grafana authentication failed - got status $actual_status"
fi

# Check external secrets status
echo "Checking external secrets..."
kubectl get externalsecrets -A
```

## Success Criteria

- [ ] AWS Cognito User Pool created with appropriate clients
- [ ] External Secrets synchronized from AWS Secrets Manager
- [ ] Backstage redirects to Cognito for authentication
- [ ] ArgoCD shows Cognito login option
- [ ] Grafana configured for OAuth with Cognito
- [ ] All services accessible via single sign-on
- [ ] User groups properly mapped to service roles

## Rollback Plan

```bash
# Emergency rollback procedure
echo "Performing rollback..."

# 1. Revert to previous deployment configurations
kubectl rollout undo deployment/backstage -n backstage
kubectl rollout undo deployment/argocd-server -n argocd
kubectl rollout undo deployment/grafana -n monitoring

# 2. Remove Cognito configurations
kubectl delete configmap backstage-cognito-config -n backstage
kubectl delete configmap argocd-cognito-config -n argocd
kubectl delete configmap grafana-cognito-config -n monitoring

# 3. Remove external secrets
kubectl delete externalsecret cognito-secrets -n backstage
kubectl delete externalsecret argocd-cognito-secrets -n argocd
kubectl delete externalsecret grafana-cognito-secrets -n monitoring

# 4. Remove Cognito infrastructure (only if safe to do so)
# kubectl delete -f infrastructure/aws/cognito-setup.yaml

echo "Rollback completed. Services should return to previous authentication method."
```

## Next Steps

After successful completion:

1. **Create test users in Cognito User Pool**
2. **Configure user groups and permissions**
3. **Test end-to-end authentication flow**
4. **Update documentation with new login procedures**
5. **Train team on new authentication system**

## Related Tasks

- [ ] [OPA JWT Authorization Integration](./opa-jwt-integration.md)
- [ ] [Service Mesh Security Policies](./service-mesh-security.md)
- [ ] [User Management and RBAC](./user-management-rbac.md)

## Documentation Updates Required

After completion, update these documentation files:

- `docs/architecture/authentication-architecture.md`
- `docs/guides/user-management.md`
- `docs/troubleshooting/authentication-issues.md`
- `docs/onboarding/NEW_ENGINEER_GUIDE.md` (login instructions)
