#!/bin/bash

# Extract ArgoCD Certificates for Local Development
# This script extracts certificates from the Kubernetes cluster for local development use

set -euo pipefail

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
CERT_OUTPUT_DIR="$ROOT_DIR/.certs"

print_header() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $(printf "%-60s" "$1") ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
}

print_status() {
    echo -e "${PURPLE}[CERT-EXTRACT]${NC} $1"
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

# Check prerequisites
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        return 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    return 0
}

# Create certificate output directory
create_cert_directory() {
    print_status "Creating certificate output directory..."
    
    mkdir -p "$CERT_OUTPUT_DIR"
    
    # Create .gitignore to prevent committing certificates
    cat > "$CERT_OUTPUT_DIR/.gitignore" << 'EOF'
# Exclude all certificate files from git
*.crt
*.pem
*.key
*.p12
*.jks
certificate-info.json
README.md
EOF
    
    print_success "Certificate directory created at $CERT_OUTPUT_DIR"
}

# Extract ArgoCD CA certificate
extract_ca_certificate() {
    print_status "Extracting ArgoCD CA certificate..."
    
    if ! kubectl get secret argocd-ca-key-pair -n cert-manager &>/dev/null; then
        print_error "ArgoCD CA certificate not found. Run certificate setup first."
        return 1
    fi
    
    # Extract CA certificate
    kubectl get secret argocd-ca-key-pair -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CERT_OUTPUT_DIR/argocd-ca.crt"
    
    # Extract CA private key (for advanced use cases)
    kubectl get secret argocd-ca-key-pair -n cert-manager -o jsonpath='{.data.tls\.key}' | base64 -d > "$CERT_OUTPUT_DIR/argocd-ca.key"
    
    # Set proper permissions
    chmod 644 "$CERT_OUTPUT_DIR/argocd-ca.crt"
    chmod 600 "$CERT_OUTPUT_DIR/argocd-ca.key"
    
    print_success "CA certificate extracted to $CERT_OUTPUT_DIR/argocd-ca.crt"
}

# Extract ArgoCD server certificate
extract_server_certificate() {
    print_status "Extracting ArgoCD server certificate..."
    
    if ! kubectl get secret argocd-server-tls -n argocd &>/dev/null; then
        print_error "ArgoCD server certificate not found. Run certificate setup first."
        return 1
    fi
    
    # Extract server certificate
    kubectl get secret argocd-server-tls -n argocd -o jsonpath='{.data.tls\.crt}' | base64 -d > "$CERT_OUTPUT_DIR/argocd-server.crt"
    
    # Extract server private key
    kubectl get secret argocd-server-tls -n argocd -o jsonpath='{.data.tls\.key}' | base64 -d > "$CERT_OUTPUT_DIR/argocd-server.key"
    
    # Set proper permissions
    chmod 644 "$CERT_OUTPUT_DIR/argocd-server.crt"
    chmod 600 "$CERT_OUTPUT_DIR/argocd-server.key"
    
    print_success "Server certificate extracted to $CERT_OUTPUT_DIR/argocd-server.crt"
}

# Create certificate bundle
create_certificate_bundle() {
    print_status "Creating certificate bundle..."
    
    # Create full certificate chain
    cat "$CERT_OUTPUT_DIR/argocd-server.crt" "$CERT_OUTPUT_DIR/argocd-ca.crt" > "$CERT_OUTPUT_DIR/argocd-fullchain.crt"
    
    # Create bundle for Node.js applications
    cat "$CERT_OUTPUT_DIR/argocd-ca.crt" > "$CERT_OUTPUT_DIR/node-ca-bundle.crt"
    
    print_success "Certificate bundle created"
}

# Generate certificate information
generate_cert_info() {
    print_status "Generating certificate information..."
    
    # Get certificate details
    CA_SUBJECT=$(openssl x509 -in "$CERT_OUTPUT_DIR/argocd-ca.crt" -noout -subject 2>/dev/null || echo "Unable to read CA subject")
    CA_VALIDITY=$(openssl x509 -in "$CERT_OUTPUT_DIR/argocd-ca.crt" -noout -dates 2>/dev/null || echo "Unable to read CA dates")
    
    SERVER_SUBJECT=$(openssl x509 -in "$CERT_OUTPUT_DIR/argocd-server.crt" -noout -subject 2>/dev/null || echo "Unable to read server subject")
    SERVER_VALIDITY=$(openssl x509 -in "$CERT_OUTPUT_DIR/argocd-server.crt" -noout -dates 2>/dev/null || echo "Unable to read server dates")
    SERVER_SAN=$(openssl x509 -in "$CERT_OUTPUT_DIR/argocd-server.crt" -noout -text | grep -A1 "Subject Alternative Name" | tail -1 2>/dev/null || echo "Unable to read SAN")
    
    # Create JSON info file
    cat > "$CERT_OUTPUT_DIR/certificate-info.json" << EOF
{
  "extraction_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ca_certificate": {
    "file": "argocd-ca.crt",
    "subject": "$CA_SUBJECT",
    "validity": "$CA_VALIDITY"
  },
  "server_certificate": {
    "file": "argocd-server.crt",
    "subject": "$SERVER_SUBJECT", 
    "validity": "$SERVER_VALIDITY",
    "san": "$SERVER_SAN"
  },
  "bundles": {
    "fullchain": "argocd-fullchain.crt",
    "node_ca": "node-ca-bundle.crt"
  }
}
EOF
    
    print_success "Certificate information saved to certificate-info.json"
}

# Create development README
create_dev_readme() {
    print_status "Creating development README..."
    
    cat > "$CERT_OUTPUT_DIR/README.md" << 'EOF'
# ArgoCD Certificates for Local Development

This directory contains extracted ArgoCD certificates for local development use.

## Files

- `argocd-ca.crt` - Root CA certificate (public)
- `argocd-ca.key` - Root CA private key (KEEP SECURE)
- `argocd-server.crt` - ArgoCD server certificate
- `argocd-server.key` - ArgoCD server private key (KEEP SECURE)
- `argocd-fullchain.crt` - Full certificate chain (server + CA)
- `node-ca-bundle.crt` - CA bundle for Node.js applications
- `certificate-info.json` - Certificate metadata and info

## Usage Examples

### Node.js / Backstage Applications

```javascript
// Method 1: Use NODE_EXTRA_CA_CERTS environment variable
process.env.NODE_EXTRA_CA_CERTS = './path/to/.certs/argocd-ca.crt';

// Method 2: Load CA certificate programmatically
const fs = require('fs');
const https = require('https');

const ca = fs.readFileSync('./path/to/.certs/argocd-ca.crt');
const httpsAgent = new https.Agent({ ca });

// Use with axios
const axios = require('axios');
const client = axios.create({
  httpsAgent,
  baseURL: 'https://argocd-server.argocd.svc.cluster.local'
});

// Use with fetch
const response = await fetch('https://argocd-server.argocd.svc.cluster.local/api/version', {
  agent: httpsAgent
});
```

### Python Applications

```python
import requests
import ssl

# Method 1: Use CA bundle
response = requests.get(
    'https://argocd-server.argocd.svc.cluster.local/api/version',
    verify='./path/to/.certs/argocd-ca.crt'
)

# Method 2: Create SSL context
import ssl
context = ssl.create_default_context(cafile='./path/to/.certs/argocd-ca.crt')
```

### cURL Commands

```bash
# Use CA certificate
curl --cacert .certs/argocd-ca.crt https://argocd-server.argocd.svc.cluster.local/api/version

# Use full certificate bundle
curl --cacert .certs/argocd-fullchain.crt https://localhost:8443/api/version
```

### Docker Containers

```dockerfile
# Add CA certificate to container
COPY .certs/argocd-ca.crt /usr/local/share/ca-certificates/argocd-ca.crt
RUN update-ca-certificates
```

### Environment Variables

```bash
# For Node.js applications
export NODE_EXTRA_CA_CERTS=$(pwd)/.certs/argocd-ca.crt

# For cURL and similar tools
export CURL_CA_BUNDLE=$(pwd)/.certs/argocd-ca.crt

# For Python requests library
export REQUESTS_CA_BUNDLE=$(pwd)/.certs/argocd-ca.crt
```

## ArgoCD API Access

Once you have the certificates, you can access ArgoCD APIs securely:

```bash
# Port-forward to ArgoCD server (HTTPS)
kubectl port-forward -n argocd svc/argocd-server 8443:443

# Login to ArgoCD CLI with certificates
argocd login localhost:8443 --username admin --password <password> --cacert .certs/argocd-ca.crt

# Test API access
curl --cacert .certs/argocd-ca.crt -H "Authorization: Bearer $ARGOCD_TOKEN" \
  https://localhost:8443/api/v1/applications
```

## Certificate Renewal

When certificates are renewed in the cluster, re-run the extraction:

```bash
./scripts/extract-certificates.sh
```

## Security Notes

- **Private keys** (.key files) should be kept secure and not committed to version control
- **CA certificate** is safe to share and commit (it's public)
- **Server certificates** contain public information but should be handled carefully
- These are **development certificates only** - not for production use
- Certificates have **limited validity** - check expiration dates regularly

## Troubleshooting

- Check certificate validity: `openssl x509 -in argocd-ca.crt -noout -dates`
- Verify certificate chain: `openssl verify -CAfile argocd-ca.crt argocd-server.crt`
- Test connectivity: `openssl s_client -connect localhost:8443 -CAfile argocd-ca.crt`
EOF
    
    print_success "Development README created"
}

# Save certificates to LocalStack (optional)
save_to_localstack() {
    if curl -s http://localhost:4566/health > /dev/null 2>&1; then
        print_status "Saving certificates to LocalStack for easy access..."
        
        # Save CA certificate
        awslocal secretsmanager create-secret \
            --name "argocd-ca-cert-local-dev" \
            --description "ArgoCD CA certificate for local development" \
            --secret-binary "fileb://$CERT_OUTPUT_DIR/argocd-ca.crt" \
            --region us-east-1 2>/dev/null || \
        awslocal secretsmanager update-secret \
            --secret-id "argocd-ca-cert-local-dev" \
            --secret-binary "fileb://$CERT_OUTPUT_DIR/argocd-ca.crt" \
            --region us-east-1 2>/dev/null
            
        print_success "Certificates saved to LocalStack"
        
        echo -e "\n${BLUE}LocalStack Access:${NC}"
        echo -e "awslocal secretsmanager get-secret-value --secret-id argocd-ca-cert-local-dev --region us-east-1"
    else
        print_warning "LocalStack not available, skipping LocalStack save"
    fi
}

# Display usage information
show_usage() {
    print_status "Certificate files created in: $CERT_OUTPUT_DIR"
    echo ""
    echo -e "${BLUE}Available Certificate Files:${NC}"
    ls -la "$CERT_OUTPUT_DIR" | grep -E '\.(crt|key|pem)$' | while read -r line; do
        echo -e "  $line"
    done
    echo ""
    echo -e "${BLUE}Quick Usage Examples:${NC}"
    echo -e "  Node.js:  ${YELLOW}NODE_EXTRA_CA_CERTS=$CERT_OUTPUT_DIR/argocd-ca.crt node app.js${NC}"
    echo -e "  cURL:     ${YELLOW}curl --cacert $CERT_OUTPUT_DIR/argocd-ca.crt https://localhost:8443/api/version${NC}"
    echo -e "  Python:   ${YELLOW}requests.get(url, verify='$CERT_OUTPUT_DIR/argocd-ca.crt')${NC}"
    echo ""
    echo -e "${YELLOW}📖 See $CERT_OUTPUT_DIR/README.md for detailed usage examples${NC}"
}

# Main execution
main() {
    print_header "ArgoCD Certificate Extraction for Local Development"
    
    if ! check_prerequisites; then
        exit 1
    fi
    
    create_cert_directory
    extract_ca_certificate
    extract_server_certificate
    create_certificate_bundle
    generate_cert_info
    create_dev_readme
    save_to_localstack
    
    print_header "Certificate Extraction Complete"
    show_usage
}

# Handle command line arguments
case "${1:-extract}" in
    "extract"|"")
        main
        ;;
    "info")
        if [ -f "$CERT_OUTPUT_DIR/certificate-info.json" ]; then
            cat "$CERT_OUTPUT_DIR/certificate-info.json" | python -m json.tool 2>/dev/null || cat "$CERT_OUTPUT_DIR/certificate-info.json"
        else
            print_error "Certificate info not found. Run extraction first."
            exit 1
        fi
        ;;
    "clean")
        print_status "Cleaning certificate directory..."
        rm -rf "$CERT_OUTPUT_DIR"
        print_success "Certificate directory cleaned"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [extract|info|clean|help]"
        echo ""
        echo "Commands:"
        echo "  extract - Extract certificates from Kubernetes cluster (default)"
        echo "  info    - Show certificate information"  
        echo "  clean   - Clean certificate directory"
        echo "  help    - Show this help message"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac