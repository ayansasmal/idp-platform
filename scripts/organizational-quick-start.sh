#!/bin/bash

# IDP Organizational Quick Start Script
# Automatically discovers AWS organization structure and deploys IDP

set -e

# Default values
AWS_ORG_ID=""
DISCOVERY_ROLE=""
ENVIRONMENT="development"
TEMPLATE="microservices-per-account"
OUTPUT_DIR="./organizational-config"
DRY_RUN="false"
VERBOSE="false"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
IDP Organizational Quick Start Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --aws-org-id ORG_ID         AWS Organization ID (required)
    --discovery-role ROLE_ARN   IAM role for cross-account discovery (required)
    --environment ENV           Target environment [development|staging|production] (default: development)
    --template TEMPLATE         Organizational template (default: microservices-per-account)
    --output-dir DIR            Output directory for generated config (default: ./organizational-config)
    --dry-run                   Generate configuration without deploying
    --verbose                   Enable verbose logging
    --help                      Show this help message

EXAMPLES:
    # Basic discovery and development deployment
    $0 --aws-org-id o-1234567890 --discovery-role arn:aws:iam::123456789012:role/IDPDiscoveryRole

    # Generate configuration only (no deployment)
    $0 --aws-org-id o-1234567890 --discovery-role arn:aws:iam::123456789012:role/IDPDiscoveryRole --dry-run

    # Production deployment with custom template
    $0 --aws-org-id o-1234567890 \\
       --discovery-role arn:aws:iam::123456789012:role/IDPDiscoveryRole \\
       --environment production \\
       --template enterprise-multi-account

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - kubectl configured with target Kubernetes cluster
    - helm installed and configured
    - jq installed for JSON processing

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --aws-org-id)
            AWS_ORG_ID="$2"
            shift 2
            ;;
        --discovery-role)
            DISCOVERY_ROLE="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --template)
            TEMPLATE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --verbose)
            VERBOSE="true"
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$AWS_ORG_ID" || -z "$DISCOVERY_ROLE" ]]; then
    log_error "AWS Organization ID and Discovery Role are required"
    show_help
    exit 1
fi

# Verbose logging
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

log_info "Starting IDP Organizational Quick Start"
log_info "AWS Organization ID: $AWS_ORG_ID"
log_info "Discovery Role: $DISCOVERY_ROLE"
log_info "Environment: $ENVIRONMENT"
log_info "Template: $TEMPLATE"
log_info "Output Directory: $OUTPUT_DIR"
log_info "Dry Run: $DRY_RUN"

# Step 1: Prerequisites Check
log_info "Checking prerequisites..."

# Check required tools
for tool in aws kubectl helm jq; do
    if ! command -v $tool &> /dev/null; then
        log_error "$tool is not installed or not in PATH"
        exit 1
    fi
done

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured or invalid"
    exit 1
fi

# Check Kubernetes connection
if ! kubectl cluster-info &> /dev/null; then
    log_error "kubectl is not configured or cannot connect to cluster"
    exit 1
fi

# Check Helm
if ! helm version &> /dev/null; then
    log_error "Helm is not properly configured"
    exit 1
fi

log_success "Prerequisites check completed"

# Step 2: AWS Organization Discovery
log_info "Discovering AWS Organization structure..."

mkdir -p "$OUTPUT_DIR"

# Create discovery script
cat > "$OUTPUT_DIR/discover-organization.py" << 'EOF'
#!/usr/bin/env python3

import boto3
import json
import yaml
import sys
from botocore.exceptions import ClientError, NoCredentialsError

def assume_role(account_id, role_name, session_name="IDPDiscovery"):
    """Assume role in target account for resource discovery"""
    sts_client = boto3.client('sts')
    
    role_arn = f"arn:aws:iam::{account_id}:role/{role_name}"
    
    try:
        response = sts_client.assume_role(
            RoleArn=role_arn,
            RoleSessionName=session_name
        )
        
        credentials = response['Credentials']
        return {
            'aws_access_key_id': credentials['AccessKeyId'],
            'aws_secret_access_key': credentials['SecretAccessKey'],
            'aws_session_token': credentials['SessionToken']
        }
    except ClientError as e:
        print(f"Error assuming role {role_arn}: {e}")
        return None

def discover_account_resources(account_id, credentials):
    """Discover resources in an AWS account"""
    session = boto3.Session(**credentials)
    
    # Initialize clients
    ec2 = session.client('ec2', region_name='us-east-1')
    ecs = session.client('ecs', region_name='us-east-1')
    rds = session.client('rds', region_name='us-east-1')
    lambda_client = session.client('lambda', region_name='us-east-1')
    
    resources = {
        'account_id': account_id,
        'applications': []
    }
    
    try:
        # Discover ECS services
        clusters = ecs.list_clusters()
        for cluster_arn in clusters['clusterArns']:
            cluster_name = cluster_arn.split('/')[-1]
            services = ecs.list_services(cluster=cluster_arn)
            
            for service_arn in services['serviceArns']:
                service_name = service_arn.split('/')[-1]
                app_name = service_name.replace('-service', '').replace('-api', '')
                
                # Check if application already exists
                existing_app = next((app for app in resources['applications'] if app['name'] == app_name), None)
                if not existing_app:
                    resources['applications'].append({
                        'name': app_name,
                        'type': 'backend-api',
                        'components': ['ecs-cluster']
                    })
                else:
                    if 'ecs-cluster' not in existing_app['components']:
                        existing_app['components'].append('ecs-cluster')
        
        # Discover RDS instances
        rds_instances = rds.describe_db_instances()
        for db_instance in rds_instances['DBInstances']:
            db_name = db_instance['DBInstanceIdentifier']
            app_name = db_name.split('-')[0] if '-' in db_name else db_name
            
            # Find or create application
            existing_app = next((app for app in resources['applications'] if app['name'] == app_name), None)
            if not existing_app:
                resources['applications'].append({
                    'name': app_name,
                    'type': 'backend-api',
                    'components': ['rds-database']
                })
            else:
                if 'rds-database' not in existing_app['components']:
                    existing_app['components'].append('rds-database')
        
        # Discover Lambda functions
        lambda_functions = lambda_client.list_functions()
        for function in lambda_functions['Functions']:
            function_name = function['FunctionName']
            app_name = function_name.split('-')[0] if '-' in function_name else function_name
            
            # Find or create application
            existing_app = next((app for app in resources['applications'] if app['name'] == app_name), None)
            if not existing_app:
                resources['applications'].append({
                    'name': app_name,
                    'type': 'serverless',
                    'components': ['lambda-functions']
                })
            else:
                if 'lambda-functions' not in existing_app['components']:
                    existing_app['components'].append('lambda-functions')
    
    except ClientError as e:
        print(f"Error discovering resources in account {account_id}: {e}")
    
    return resources

def main():
    if len(sys.argv) != 3:
        print("Usage: python discover-organization.py <org-id> <discovery-role-name>")
        sys.exit(1)
    
    org_id = sys.argv[1]
    discovery_role_name = sys.argv[2].split('/')[-1]  # Extract role name from ARN
    
    try:
        # Get organization accounts
        org_client = boto3.client('organizations')
        accounts = org_client.list_accounts()
        
        organizational_structure = {
            'organization_id': org_id,
            'services': []
        }
        
        for account in accounts['Accounts']:
            if account['Status'] == 'ACTIVE':
                account_id = account['Id']
                account_name = account['Name']
                
                print(f"Discovering resources in account: {account_name} ({account_id})")
                
                # Assume role for resource discovery
                credentials = assume_role(account_id, discovery_role_name)
                if credentials:
                    resources = discover_account_resources(account_id, credentials)
                    
                    if resources['applications']:
                        service_info = {
                            'name': account_name.lower().replace(' ', '-'),
                            'aws_account': account_id,
                            'applications': resources['applications']
                        }
                        organizational_structure['services'].append(service_info)
        
        # Output as YAML
        with open('organizational-mapping.yaml', 'w') as f:
            yaml.dump(organizational_structure, f, default_flow_style=False, indent=2)
        
        print(f"Discovery completed. Found {len(organizational_structure['services'])} services.")
        print("Results saved to organizational-mapping.yaml")
    
    except NoCredentialsError:
        print("Error: AWS credentials not configured")
        sys.exit(1)
    except ClientError as e:
        print(f"Error accessing AWS Organizations: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF

# Run discovery
cd "$OUTPUT_DIR"
python3 discover-organization.py "$AWS_ORG_ID" "$DISCOVERY_ROLE"

if [[ ! -f "organizational-mapping.yaml" ]]; then
    log_error "Organization discovery failed - no mapping file generated"
    exit 1
fi

log_success "AWS Organization discovery completed"

# Step 3: Generate IDP Configuration
log_info "Generating IDP configuration..."

# Create configuration generator
cat > "generate-idp-config.py" << 'EOF'
#!/usr/bin/env python3

import yaml
import os
import sys
from pathlib import Path

def load_organizational_mapping(file_path):
    """Load the organizational mapping from YAML file"""
    with open(file_path, 'r') as f:
        return yaml.safe_load(f)

def generate_crossplane_providers(org_data, environment):
    """Generate Crossplane provider configurations"""
    providers = []
    
    for service in org_data['services']:
        provider_name = f"{service['name']}-provider"
        aws_account = service['aws_account']
        
        provider_config = {
            'apiVersion': 'aws.crossplane.io/v1beta1',
            'kind': 'ProviderConfig',
            'metadata': {
                'name': provider_name
            },
            'spec': {
                'credentials': {
                    'source': 'Secret',
                    'secretRef': {
                        'namespace': 'crossplane-system',
                        'name': f'aws-secret-{service["name"]}',
                        'key': 'creds'
                    }
                },
                'assume_role_arn': f'arn:aws:iam::{aws_account}:role/CrossplaneProviderRole'
            }
        }
        providers.append(provider_config)
    
    return providers

def generate_backstage_catalog(org_data):
    """Generate Backstage catalog entries"""
    catalog_entries = []
    
    for service in org_data['services']:
        # Service component
        service_component = {
            'apiVersion': 'backstage.io/v1alpha1',
            'kind': 'Component',
            'metadata': {
                'name': service['name'],
                'description': f"Service: {service['name']}",
                'labels': {
                    'aws-account': service['aws_account']
                },
                'annotations': {
                    'aws.amazon.com/account-id': service['aws_account']
                }
            },
            'spec': {
                'type': 'service',
                'lifecycle': 'production',
                'owner': 'platform-team',
                'system': service['name']
            }
        }
        catalog_entries.append(service_component)
        
        # Application components
        for app in service['applications']:
            app_component = {
                'apiVersion': 'backstage.io/v1alpha1',
                'kind': 'Component',
                'metadata': {
                    'name': f"{service['name']}-{app['name']}",
                    'description': f"Application: {app['name']} in {service['name']}",
                    'labels': {
                        'app-type': app['type'],
                        'service': service['name']
                    }
                },
                'spec': {
                    'type': 'service',
                    'lifecycle': 'production',
                    'owner': 'platform-team',
                    'system': service['name'],
                    'dependsOn': app['components']
                }
            }
            catalog_entries.append(app_component)
    
    return catalog_entries

def generate_web_applications(org_data, environment):
    """Generate WebApplication CRDs for discovered applications"""
    web_applications = []
    
    for service in org_data['services']:
        for app in service['applications']:
            if app['type'] in ['backend-api', 'frontend']:
                web_app = {
                    'apiVersion': 'platform.idp/v1alpha1',
                    'kind': 'WebApplication',
                    'metadata': {
                        'name': f"{service['name']}-{app['name']}",
                        'namespace': service['name'],
                        'labels': {
                            'app.kubernetes.io/name': f"{service['name']}-{app['name']}",
                            'platform.idp/environment': environment,
                            'platform.idp/service': service['name'],
                            'app.kubernetes.io/managed-by': 'idp-platform'
                        }
                    },
                    'spec': {
                        'image': f"nginx:latest",  # Placeholder image
                        'replicas': 2,
                        'port': 80,
                        'environment': environment,
                        'resources': {
                            'requests': {
                                'memory': '128Mi',
                                'cpu': '100m'
                            },
                            'limits': {
                                'memory': '256Mi',
                                'cpu': '200m'
                            }
                        },
                        'infrastructure': {
                            'providerConfigRef': f"{service['name']}-provider"
                        }
                    }
                }
                web_applications.append(web_app)
    
    return web_applications

def main():
    if len(sys.argv) != 3:
        print("Usage: python generate-idp-config.py <mapping-file> <environment>")
        sys.exit(1)
    
    mapping_file = sys.argv[1]
    environment = sys.argv[2]
    
    # Load organizational mapping
    org_data = load_organizational_mapping(mapping_file)
    
    # Create output directories
    os.makedirs('infrastructure/crossplane/providers', exist_ok=True)
    os.makedirs('applications/backstage/catalog', exist_ok=True)
    os.makedirs('applications/workloads', exist_ok=True)
    os.makedirs('platform/namespaces', exist_ok=True)
    
    # Generate Crossplane providers
    providers = generate_crossplane_providers(org_data, environment)
    for i, provider in enumerate(providers):
        with open(f'infrastructure/crossplane/providers/provider-{i+1}.yaml', 'w') as f:
            yaml.dump(provider, f, default_flow_style=False, indent=2)
    
    # Generate Backstage catalog
    catalog_entries = generate_backstage_catalog(org_data)
    for i, entry in enumerate(catalog_entries):
        with open(f'applications/backstage/catalog/catalog-{i+1}.yaml', 'w') as f:
            yaml.dump(entry, f, default_flow_style=False, indent=2)
    
    # Generate WebApplications
    web_apps = generate_web_applications(org_data, environment)
    for i, web_app in enumerate(web_apps):
        with open(f'applications/workloads/webapp-{i+1}.yaml', 'w') as f:
            yaml.dump(web_app, f, default_flow_style=False, indent=2)
    
    # Generate namespaces
    services = org_data['services']
    for service in services:
        namespace = {
            'apiVersion': 'v1',
            'kind': 'Namespace',
            'metadata': {
                'name': service['name'],
                'labels': {
                    'platform.idp/environment': environment,
                    'platform.idp/service': service['name'],
                    'istio-injection': 'enabled'
                }
            }
        }
        with open(f'platform/namespaces/{service["name"]}-namespace.yaml', 'w') as f:
            yaml.dump(namespace, f, default_flow_style=False, indent=2)
    
    print(f"IDP configuration generated for {len(services)} services")
    print(f"Generated {len(providers)} Crossplane providers")
    print(f"Generated {len(catalog_entries)} Backstage catalog entries")
    print(f"Generated {len(web_apps)} WebApplication CRDs")

if __name__ == '__main__':
    main()
EOF

python3 generate-idp-config.py organizational-mapping.yaml "$ENVIRONMENT"

log_success "IDP configuration generated"

# Step 4: Validate Configuration
log_info "Validating generated configuration..."

# Check for required files
required_files=(
    "infrastructure/crossplane/providers"
    "applications/backstage/catalog"
    "applications/workloads"
    "platform/namespaces"
)

for dir in "${required_files[@]}"; do
    if [[ ! -d "$dir" ]]; then
        log_error "Required directory not generated: $dir"
        exit 1
    fi
    
    file_count=$(find "$dir" -name "*.yaml" | wc -l)
    if [[ $file_count -eq 0 ]]; then
        log_error "No YAML files generated in: $dir"
        exit 1
    fi
    
    log_info "Generated $file_count files in $dir"
done

# Validate YAML syntax
log_info "Validating YAML syntax..."
find . -name "*.yaml" -exec yaml-lint {} \; 2>/dev/null || log_warning "YAML validation tool not available"

log_success "Configuration validation completed"

# Step 5: Deploy Configuration (if not dry-run)
if [[ "$DRY_RUN" == "false" ]]; then
    log_info "Deploying IDP configuration..."
    
    # Deploy namespaces first
    log_info "Creating namespaces..."
    kubectl apply -f platform/namespaces/
    
    # Deploy Crossplane providers
    log_info "Deploying Crossplane providers..."
    kubectl apply -f infrastructure/crossplane/providers/
    
    # Wait for providers to be ready
    log_info "Waiting for Crossplane providers to be ready..."
    sleep 30
    
    # Deploy WebApplications
    log_info "Deploying WebApplications..."
    kubectl apply -f applications/workloads/
    
    # Deploy Backstage catalog
    log_info "Updating Backstage catalog..."
    kubectl apply -f applications/backstage/catalog/
    
    log_success "IDP configuration deployed successfully"
    
    # Step 6: Validation and Next Steps
    log_info "Performing post-deployment validation..."
    
    # Check pod status
    log_info "Checking pod status..."
    kubectl get pods -A | grep -E "(Error|CrashLoopBackOff|Pending)" || log_success "All pods are healthy"
    
    # Check WebApplications
    log_info "Checking WebApplications..."
    kubectl get webapplications -A
    
    # Display access information
    log_success "IDP deployment completed successfully!"
    echo ""
    echo "Access Information:"
    echo "=================="
    echo "Backstage:  http://backstage.idp.local"
    echo "ArgoCD:     http://argocd.idp.local"
    echo "Grafana:    http://grafana.idp.local"
    echo ""
    echo "Next Steps:"
    echo "==========="
    echo "1. Access Backstage to view your service catalog"
    echo "2. Review generated WebApplications and update container images"
    echo "3. Configure CI/CD pipelines for your applications"
    echo "4. Set up monitoring and alerting for your services"
    echo ""
    echo "Documentation: http://backstage.idp.local/docs"
    
else
    log_info "Dry run completed - configuration generated but not deployed"
    echo ""
    echo "Generated Configuration:"
    echo "======================="
    echo "Location: $OUTPUT_DIR"
    echo ""
    echo "To deploy manually:"
    echo "kubectl apply -f platform/namespaces/"
    echo "kubectl apply -f infrastructure/crossplane/providers/"
    echo "kubectl apply -f applications/workloads/"
    echo "kubectl apply -f applications/backstage/catalog/"
fi

cd - > /dev/null

log_success "IDP Organizational Quick Start completed successfully!"
