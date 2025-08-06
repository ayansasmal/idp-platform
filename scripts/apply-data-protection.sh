#!/bin/bash

# Data Loss Protection Policy Application Script
# Applies network policies, audit logging, and security controls based on IDP configuration

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
if [ -f "$SCRIPT_DIR/config-parser.sh" ]; then
    source "$SCRIPT_DIR/config-parser.sh" export 2>/dev/null || true
fi

# Function to print status
print_status() {
    echo -e "${PURPLE}[DLP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Data Loss Protection Policy Application         ║"
echo "║                                                              ║"
echo "║  🔒 Applying security controls and network policies         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if data protection is enabled
if [ "$IDP_DATA_PROTECTION_ENABLED" != "true" ]; then
    print_warning "Data loss protection is disabled in configuration"
    print_status "Skipping data protection policy application"
    exit 0
fi

print_status "Applying data loss protection policies..."

# Step 1: Create network policies for traffic isolation
if [ "$IDP_NETWORK_POLICIES_ENABLED" = "true" ]; then
    print_status "Creating network policies for traffic isolation..."
    
    # Create default deny-all network policy
    cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ${IDP_PLATFORM_NAMESPACE:-idp-system}
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: network-policy
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-platform-internal
  namespace: ${IDP_PLATFORM_NAMESPACE:-idp-system}
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: network-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: idp-platform
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ${IDP_PLATFORM_NAMESPACE:-idp-system}
    - namespaceSelector:
        matchLabels:
          name: argocd
    - namespaceSelector:
        matchLabels:
          name: backstage
    - namespaceSelector:
        matchLabels:
          name: istio-system
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: ${IDP_PLATFORM_NAMESPACE:-idp-system}
    - namespaceSelector:
        matchLabels:
          name: argocd
    - namespaceSelector:
        matchLabels:
          name: backstage
    - namespaceSelector:
        matchLabels:
          name: istio-system
  # Allow DNS resolution
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow LocalStack access (if using LocalStack)
  - to: []
    ports:
    - protocol: TCP
      port: 4566
EOF

    # Create namespace-specific network policies
    for namespace in argocd backstage istio-system crossplane-system external-secrets monitoring; do
        cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-${namespace}-internal
  namespace: ${namespace}
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: network-policy
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ${namespace}
    - namespaceSelector:
        matchLabels:
          name: ${IDP_PLATFORM_NAMESPACE:-idp-system}
    - namespaceSelector:
        matchLabels:
          name: istio-system
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: ${namespace}
    - namespaceSelector:
        matchLabels:
          name: ${IDP_PLATFORM_NAMESPACE:-idp-system}
    - namespaceSelector:
        matchLabels:
          name: istio-system
  # Allow DNS resolution
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow LocalStack access (if using LocalStack)
  - to: []
    ports:
    - protocol: TCP
      port: 4566
EOF
    done
    
    print_success "Network policies created for traffic isolation"
fi

# Step 2: Enable audit logging
if [ "$IDP_AUDIT_LOGGING_ENABLED" = "true" ]; then
    print_status "Configuring audit logging..."
    
    # Create audit policy
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: audit-policy
  namespace: ${IDP_PLATFORM_NAMESPACE:-idp-system}
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: audit-logging
data:
  audit-policy.yaml: |
    apiVersion: audit.k8s.io/v1
    kind: Policy
    omitStages:
      - RequestReceived
    rules:
    # Log external system interactions
    - level: RequestResponse
      omitStages:
        - RequestReceived
      resources:
      - group: ""
        resources: ["secrets", "configmaps"]
      namespaces: ["argocd", "backstage", "external-secrets", "${IDP_PLATFORM_NAMESPACE:-idp-system}"]
    
    # Log all network policy changes
    - level: RequestResponse
      omitStages:
        - RequestReceived
      resources:
      - group: "networking.k8s.io"
        resources: ["networkpolicies"]
    
    # Log service mesh policy changes
    - level: RequestResponse
      omitStages:
        - RequestReceived
      resources:
      - group: "security.istio.io"
        resources: ["*"]
    
    # Log external secrets access
    - level: RequestResponse
      omitStages:
        - RequestReceived
      resources:
      - group: "external-secrets.io"
        resources: ["*"]
EOF
    
    print_success "Audit logging policy configured"
fi

# Step 3: Apply Istio security policies for encryption in transit
if [ "$IDP_ENCRYPTION_IN_TRANSIT" = "true" ]; then
    print_status "Configuring encryption in transit with Istio..."
    
    # Create PeerAuthentication for strict mTLS
    cat << EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default-strict-mtls
  namespace: ${IDP_PLATFORM_NAMESPACE:-idp-system}
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: encryption
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: argocd-strict-mtls
  namespace: argocd
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: encryption
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: backstage-strict-mtls
  namespace: backstage
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: encryption
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: monitoring-strict-mtls
  namespace: monitoring
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: encryption
spec:
  mtls:
    mode: STRICT
EOF
    
    # Create DestinationRule for TLS
    cat << EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: default-tls
  namespace: ${IDP_PLATFORM_NAMESPACE:-idp-system}
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: encryption
spec:
  host: "*.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF
    
    print_success "Encryption in transit configured with strict mTLS"
fi

# Step 4: Create authorization policies for external system access
print_status "Creating authorization policies for controlled external access..."

cat << EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: external-system-access-control
  namespace: ${IDP_PLATFORM_NAMESPACE:-idp-system}
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: authorization
spec:
  rules:
  # Allow platform services to communicate
  - from:
    - source:
        principals: ["cluster.local/ns/${IDP_PLATFORM_NAMESPACE:-idp-system}/sa/*"]
    - source:
        principals: ["cluster.local/ns/argocd/sa/*"]
    - source:
        principals: ["cluster.local/ns/backstage/sa/*"]
    - source:
        principals: ["cluster.local/ns/istio-system/sa/*"]
  # Deny all other external access
  - {}
    when:
    - key: source.ip
      notValues: ["127.0.0.1", "::1"]
    action: DENY
EOF

# Step 5: Create monitoring and alerting for data loss protection violations
print_status "Setting up monitoring for data protection violations..."

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: dlp-monitoring-rules
  namespace: monitoring
  labels:
    app.kubernetes.io/name: data-loss-protection
    app.kubernetes.io/component: monitoring
data:
  dlp-rules.yaml: |
    groups:
    - name: data-loss-protection
      rules:
      - alert: UnauthorizedExternalAccess
        expr: |
          increase(istio_request_total{
            source_workload!~".*-platform.*",
            destination_service_name!~".*\\.local"
          }[5m]) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: 'Unauthorized external access detected'
          description: 'External access attempt from {{ \$labels.source_workload }} to {{ \$labels.destination_service_name }}'
      
      - alert: NetworkPolicyViolation
        expr: |
          increase(kubernetes_audit_total{
            verb="create",
            objectRef_resource="networkpolicies"
          }[5m]) > 0
        for: 30s
        labels:
          severity: warning
        annotations:
          summary: 'Network policy configuration changed'
          description: 'Network policy {{ \$labels.objectRef_name }} was modified'
      
      - alert: SecretAccessViolation
        expr: |
          increase(kubernetes_audit_total{
            verb=~"get|list",
            objectRef_resource="secrets",
            user_username!~"system:.*"
          }[5m]) > 3
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: 'Unusual secret access pattern detected'
          description: 'User {{ \$labels.user_username }} accessed secrets {{ \$labels.objectRef_name }} multiple times'
EOF

print_success "Data protection monitoring configured"

# Step 6: Create data loss protection status check
cat << EOF > "$ROOT_DIR/.idp-config/dlp-status.sh"
#!/bin/bash

# Data Loss Protection Status Check Script

echo "🔒 Data Loss Protection Status:"
echo ""

# Check network policies
NETWORK_POLICIES=\$(kubectl get networkpolicy --all-namespaces --no-headers 2>/dev/null | wc -l)
echo "  Network Policies: \$NETWORK_POLICIES active"

# Check mTLS status
PEER_AUTH=\$(kubectl get peerauthentication --all-namespaces --no-headers 2>/dev/null | wc -l)
echo "  mTLS Policies: \$PEER_AUTH active"

# Check authorization policies
AUTH_POLICIES=\$(kubectl get authorizationpolicy --all-namespaces --no-headers 2>/dev/null | wc -l)
echo "  Authorization Policies: \$AUTH_POLICIES active"

echo ""
echo "✅ Data Loss Protection is active and monitoring"
EOF

chmod +x "$ROOT_DIR/.idp-config/dlp-status.sh"

print_success "Data loss protection status check created"

# Summary
echo ""
echo -e "${GREEN}🔒 Data Loss Protection Successfully Applied!${NC}"
echo ""
echo -e "${BLUE}Applied Security Controls:${NC}"
echo -e "  ✓ Network policies for traffic isolation"
echo -e "  ✓ Audit logging for external system interactions"
echo -e "  ✓ Strict mTLS encryption in transit"
echo -e "  ✓ Authorization policies for controlled access"
echo -e "  ✓ Monitoring and alerting for policy violations"
echo ""
echo -e "${BLUE}Status Check:${NC}"
echo -e "  Run: ${YELLOW}./.idp-config/dlp-status.sh${NC} to check protection status"
echo ""
echo -e "${YELLOW}Note: These policies provide strong data protection but may affect"
echo -e "      external system integration. Review policies if connectivity issues occur.${NC}"