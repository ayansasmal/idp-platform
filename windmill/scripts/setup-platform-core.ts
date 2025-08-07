// Platform Core Setup Script for IDP Platform
// Handles Kubernetes core components: Istio, ArgoCD, Argo Workflows

import { execSync } from "node:child_process";

export async function main(config: {
  action?: string;
  sync?: boolean;
  install_istio?: boolean;
  install_argocd?: boolean;
  install_argo_workflows?: boolean;
  install_crossplane?: boolean;
  install_external_secrets?: boolean;
  dry_run?: boolean;
} = {}) {
  const { 
    action = "setup",
    sync = true,
    install_istio = true,
    install_argocd = true, 
    install_argo_workflows = true,
    install_crossplane = true,
    install_external_secrets = true,
    dry_run = false 
  } = config;
  
  console.log(`⚙️ Platform core setup - Action: ${action}${dry_run ? ' (dry run)' : ''}`);
  
  const results = {
    success: true,
    action,
    dry_run,
    components: {
      istio: { enabled: install_istio, status: "pending", version: null },
      argocd: { enabled: install_argocd, status: "pending", version: null },
      argo_workflows: { enabled: install_argo_workflows, status: "pending", version: null },
      crossplane: { enabled: install_crossplane, status: "pending", version: null },
      external_secrets: { enabled: install_external_secrets, status: "pending", version: null }
    },
    namespaces_created: [],
    services: [],
    errors: [],
    warnings: []
  };

  try {
    switch (action) {
      case "setup":
        await setupPlatformCore(results, dry_run);
        if (sync) {
          await waitForComponentsReady(results);
        }
        break;
      case "status":
        await checkPlatformStatus(results);
        break;
      case "health":
        await healthCheckComponents(results);
        break;
      case "cleanup":
        await cleanupPlatformCore(results, dry_run);
        break;
      default:
        throw new Error(`Unknown action: ${action}`);
    }

    const failedComponents = Object.values(results.components).filter(c => c.enabled && c.status === "failed");
    if (failedComponents.length > 0) {
      results.success = false;
      console.log(`❌ Platform core setup failed - ${failedComponents.length} components failed`);
    } else {
      console.log("✅ Platform core setup completed successfully");
    }

  } catch (error) {
    console.error(`💥 Platform core setup error: ${error.message}`);
    results.success = false;
    results.error = error.message;
  }

  return results;
}

async function setupPlatformCore(results: any, dryRun: boolean) {
  console.log("Setting up platform core components...");

  // Ensure required namespaces exist
  const namespaces = [
    "istio-system",
    "argocd", 
    "argo",
    "crossplane-system",
    "external-secrets"
  ];

  for (const ns of namespaces) {
    try {
      if (!dryRun) {
        // Check if namespace exists
        try {
          execSync(`kubectl get namespace ${ns}`, { timeout: 10000 });
          console.log(`Namespace ${ns} already exists`);
        } catch (error) {
          execSync(`kubectl create namespace ${ns}`, { timeout: 10000 });
          console.log(`Created namespace: ${ns}`);
          results.namespaces_created.push(ns);
        }
      } else {
        console.log(`DRY RUN: Would ensure namespace ${ns} exists`);
      }
    } catch (error) {
      console.warn(`Failed to create namespace ${ns}: ${error.message}`);
      results.warnings.push(`Could not create namespace: ${ns}`);
    }
  }

  // Setup Istio
  if (results.components.istio.enabled) {
    await setupIstio(results, dryRun);
  }

  // Setup ArgoCD
  if (results.components.argocd.enabled) {
    await setupArgoCD(results, dryRun);
  }

  // Setup Argo Workflows
  if (results.components.argo_workflows.enabled) {
    await setupArgoWorkflows(results, dryRun);
  }

  // Setup Crossplane
  if (results.components.crossplane.enabled) {
    await setupCrossplane(results, dryRun);
  }

  // Setup External Secrets
  if (results.components.external_secrets.enabled) {
    await setupExternalSecrets(results, dryRun);
  }
}

async function setupIstio(results: any, dryRun: boolean) {
  console.log("🕸️ Setting up Istio service mesh...");

  try {
    if (!dryRun) {
      // Check if Istio is already installed
      try {
        const istioVersion = execSync('kubectl get pods -n istio-system --no-headers', 
          { encoding: 'utf-8', timeout: 10000 });
        if (istioVersion.trim()) {
          console.log("Istio already installed");
          results.components.istio.status = "running";
          results.components.istio.existing = true;
          return;
        }
      } catch (error) {
        // Istio not installed
      }

      // Download and install Istio
      console.log("Downloading Istio...");
      execSync('curl -L https://istio.io/downloadIstio | sh -', { timeout: 60000 });
      
      // Find the Istio directory
      const istioDir = execSync('ls -d istio-*', { encoding: 'utf-8', timeout: 5000 }).trim();
      console.log(`Found Istio directory: ${istioDir}`);

      // Install Istio
      console.log("Installing Istio...");
      execSync(`${istioDir}/bin/istioctl install --set values.defaultRevision=default -y`, { timeout: 300000 });

      // Enable automatic sidecar injection for default namespace
      execSync('kubectl label namespace default istio-injection=enabled --overwrite', { timeout: 10000 });

      // Verify installation
      const istioStatus = execSync('kubectl get pods -n istio-system', { encoding: 'utf-8', timeout: 15000 });
      console.log("Istio pods status:");
      console.log(istioStatus);

      results.components.istio.status = "installed";
      results.components.istio.version = "latest";

    } else {
      console.log("DRY RUN: Would download and install Istio");
      results.components.istio.status = "dry-run";
    }

  } catch (error) {
    console.error(`Failed to setup Istio: ${error.message}`);
    results.components.istio.status = "failed";
    results.errors.push(`Istio setup failed: ${error.message}`);
  }
}

async function setupArgoCD(results: any, dryRun: boolean) {
  console.log("🔄 Setting up ArgoCD for GitOps...");

  try {
    if (!dryRun) {
      // Check if ArgoCD is already installed
      try {
        const argoCDPods = execSync('kubectl get pods -n argocd --no-headers', 
          { encoding: 'utf-8', timeout: 10000 });
        if (argoCDPods.trim()) {
          console.log("ArgoCD already installed");
          results.components.argocd.status = "running";
          results.components.argocd.existing = true;
          return;
        }
      } catch (error) {
        // ArgoCD not installed
      }

      // Install ArgoCD
      console.log("Installing ArgoCD...");
      execSync('kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml', 
        { timeout: 120000 });

      // Wait for ArgoCD to be ready
      console.log("Waiting for ArgoCD pods to be ready...");
      execSync('kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s', { timeout: 320000 });

      // Patch ArgoCD server service to LoadBalancer for easier access
      execSync('kubectl patch svc argocd-server -n argocd -p \'{"spec": {"type": "LoadBalancer"}}\'', 
        { timeout: 10000 });

      // Get initial admin password
      try {
        const adminPassword = execSync('kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d', 
          { encoding: 'utf-8', timeout: 10000 });
        results.components.argocd.admin_password = adminPassword;
        console.log(`ArgoCD admin password: ${adminPassword}`);
      } catch (error) {
        console.warn("Could not retrieve ArgoCD admin password");
      }

      results.components.argocd.status = "installed";
      results.services.push({
        name: "ArgoCD",
        namespace: "argocd",
        url: "http://localhost:8080"
      });

    } else {
      console.log("DRY RUN: Would install ArgoCD");
      results.components.argocd.status = "dry-run";
    }

  } catch (error) {
    console.error(`Failed to setup ArgoCD: ${error.message}`);
    results.components.argocd.status = "failed";
    results.errors.push(`ArgoCD setup failed: ${error.message}`);
  }
}

async function setupArgoWorkflows(results: any, dryRun: boolean) {
  console.log("🏗️ Setting up Argo Workflows for CI/CD...");

  try {
    if (!dryRun) {
      // Check if Argo Workflows is already installed
      try {
        const argoWorkflowsPods = execSync('kubectl get pods -n argo --no-headers', 
          { encoding: 'utf-8', timeout: 10000 });
        if (argoWorkflowsPods.trim()) {
          console.log("Argo Workflows already installed");
          results.components.argo_workflows.status = "running";
          results.components.argo_workflows.existing = true;
          return;
        }
      } catch (error) {
        // Argo Workflows not installed
      }

      // Install Argo Workflows
      console.log("Installing Argo Workflows...");
      execSync('kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.4.4/install.yaml', 
        { timeout: 60000 });

      // Wait for Argo Workflows to be ready
      console.log("Waiting for Argo Workflows to be ready...");
      execSync('kubectl wait --for=condition=Ready pods --all -n argo --timeout=180s', { timeout: 200000 });

      // Create service account and RBAC for workflows
      const workflowRBAC = `
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argo-workflow
  namespace: argo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argo-workflow-role
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "configmaps"]
  verbs: ["get", "watch", "patch", "create", "delete", "list"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["argoproj.io"]
  resources: ["workflows", "workflowtemplates"]
  verbs: ["get", "list", "create", "update", "patch", "delete", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argo-workflow-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argo-workflow-role
subjects:
- kind: ServiceAccount
  name: argo-workflow
  namespace: argo
`;

      // Apply RBAC
      execSync(`echo '${workflowRBAC}' | kubectl apply -f -`, { timeout: 30000 });

      // Patch argo-server service for easier access
      execSync('kubectl patch svc argo-server -n argo -p \'{"spec": {"type": "LoadBalancer"}}\'', 
        { timeout: 10000 });

      results.components.argo_workflows.status = "installed";
      results.services.push({
        name: "Argo Workflows",
        namespace: "argo",
        url: "http://localhost:4000"
      });

    } else {
      console.log("DRY RUN: Would install Argo Workflows");
      results.components.argo_workflows.status = "dry-run";
    }

  } catch (error) {
    console.error(`Failed to setup Argo Workflows: ${error.message}`);
    results.components.argo_workflows.status = "failed";
    results.errors.push(`Argo Workflows setup failed: ${error.message}`);
  }
}

async function setupCrossplane(results: any, dryRun: boolean) {
  console.log("🔗 Setting up Crossplane for infrastructure management...");

  try {
    if (!dryRun) {
      // Check if Crossplane is already installed
      try {
        const crossplanePods = execSync('kubectl get pods -n crossplane-system --no-headers', 
          { encoding: 'utf-8', timeout: 10000 });
        if (crossplanePods.trim()) {
          console.log("Crossplane already installed");
          results.components.crossplane.status = "running";
          results.components.crossplane.existing = true;
          return;
        }
      } catch (error) {
        // Crossplane not installed
      }

      // Install Crossplane
      console.log("Installing Crossplane...");
      execSync('helm repo add crossplane-stable https://charts.crossplane.io/stable', { timeout: 30000 });
      execSync('helm repo update', { timeout: 30000 });
      
      execSync(`helm install crossplane \\
        crossplane-stable/crossplane \\
        --namespace crossplane-system \\
        --create-namespace \\
        --wait \\
        --timeout 300s`, { timeout: 320000 });

      // Wait for Crossplane to be ready
      console.log("Waiting for Crossplane to be ready...");
      execSync('kubectl wait --for=condition=Ready pods --all -n crossplane-system --timeout=180s', 
        { timeout: 200000 });

      results.components.crossplane.status = "installed";

    } else {
      console.log("DRY RUN: Would install Crossplane");
      results.components.crossplane.status = "dry-run";
    }

  } catch (error) {
    console.error(`Failed to setup Crossplane: ${error.message}`);
    results.components.crossplane.status = "failed";
    results.errors.push(`Crossplane setup failed: ${error.message}`);
  }
}

async function setupExternalSecrets(results: any, dryRun: boolean) {
  console.log("🔐 Setting up External Secrets Operator...");

  try {
    if (!dryRun) {
      // Check if External Secrets is already installed
      try {
        const externalSecretsPods = execSync('kubectl get pods -n external-secrets --no-headers', 
          { encoding: 'utf-8', timeout: 10000 });
        if (externalSecretsPods.trim()) {
          console.log("External Secrets Operator already installed");
          results.components.external_secrets.status = "running";
          results.components.external_secrets.existing = true;
          return;
        }
      } catch (error) {
        // External Secrets not installed
      }

      // Install External Secrets Operator
      console.log("Installing External Secrets Operator...");
      execSync('helm repo add external-secrets https://charts.external-secrets.io', { timeout: 30000 });
      execSync('helm repo update', { timeout: 30000 });
      
      execSync(`helm install external-secrets \\
        external-secrets/external-secrets \\
        --namespace external-secrets \\
        --create-namespace \\
        --wait \\
        --timeout 180s`, { timeout: 200000 });

      results.components.external_secrets.status = "installed";

    } else {
      console.log("DRY RUN: Would install External Secrets Operator");
      results.components.external_secrets.status = "dry-run";
    }

  } catch (error) {
    console.error(`Failed to setup External Secrets: ${error.message}`);
    results.components.external_secrets.status = "failed";
    results.errors.push(`External Secrets setup failed: ${error.message}`);
  }
}

async function waitForComponentsReady(results: any) {
  console.log("⏳ Waiting for all components to be ready...");

  const checks = [
    { 
      name: "Istio", 
      enabled: results.components.istio.enabled,
      check: () => execSync('kubectl get pods -n istio-system --field-selector=status.phase!=Running --no-headers', 
        { encoding: 'utf-8', timeout: 10000 })
    },
    { 
      name: "ArgoCD", 
      enabled: results.components.argocd.enabled,
      check: () => execSync('kubectl get pods -n argocd --field-selector=status.phase!=Running --no-headers', 
        { encoding: 'utf-8', timeout: 10000 })
    },
    { 
      name: "Argo Workflows", 
      enabled: results.components.argo_workflows.enabled,
      check: () => execSync('kubectl get pods -n argo --field-selector=status.phase!=Running --no-headers', 
        { encoding: 'utf-8', timeout: 10000 })
    }
  ];

  for (const component of checks) {
    if (!component.enabled) continue;

    console.log(`Checking ${component.name}...`);
    let retries = 30;
    
    while (retries > 0) {
      try {
        const notReady = component.check().trim();
        if (!notReady) {
          console.log(`✅ ${component.name} is ready`);
          break;
        }
      } catch (error) {
        // Still waiting
      }
      
      console.log(`Waiting for ${component.name} to be ready... (${retries} retries left)`);
      await new Promise(resolve => setTimeout(resolve, 10000));
      retries--;
    }

    if (retries === 0) {
      results.warnings.push(`${component.name} may not be fully ready`);
    }
  }
}

async function checkPlatformStatus(results: any) {
  console.log("Checking platform core status...");

  const components = [
    { name: "istio", namespace: "istio-system" },
    { name: "argocd", namespace: "argocd" },
    { name: "argo_workflows", namespace: "argo" },
    { name: "crossplane", namespace: "crossplane-system" },
    { name: "external_secrets", namespace: "external-secrets" }
  ];

  for (const component of components) {
    try {
      const pods = execSync(`kubectl get pods -n ${component.namespace} --no-headers`, 
        { encoding: 'utf-8', timeout: 10000 });
      
      const podLines = pods.trim().split('\n').filter(line => line.trim());
      const runningPods = podLines.filter(line => line.includes('Running')).length;
      const totalPods = podLines.length;

      if (totalPods > 0) {
        results.components[component.name].status = runningPods === totalPods ? "running" : "degraded";
        results.components[component.name].pods = { running: runningPods, total: totalPods };
      } else {
        results.components[component.name].status = "not-installed";
      }
    } catch (error) {
      results.components[component.name].status = "not-installed";
    }
  }
}

async function healthCheckComponents(results: any) {
  console.log("Running health checks...");
  
  // This would perform deeper health checks
  // For now, just verify basic connectivity
  const healthChecks = [];

  try {
    // Check cluster connectivity
    execSync('kubectl cluster-info', { timeout: 10000 });
    healthChecks.push({ component: "Kubernetes", status: "healthy" });
  } catch (error) {
    healthChecks.push({ component: "Kubernetes", status: "unhealthy", error: error.message });
  }

  results.health_checks = healthChecks;
}

async function cleanupPlatformCore(results: any, dryRun: boolean) {
  console.log("Cleaning up platform core components...");

  if (dryRun) {
    console.log("DRY RUN: Would cleanup platform core components");
    return;
  }

  const cleanupOrder = [
    { name: "External Secrets", namespace: "external-secrets", helm: "external-secrets" },
    { name: "Crossplane", namespace: "crossplane-system", helm: "crossplane" },
    { name: "Argo Workflows", namespace: "argo", manifest: true },
    { name: "ArgoCD", namespace: "argocd", manifest: true },
    { name: "Istio", namespace: "istio-system", istio: true }
  ];

  for (const component of cleanupOrder) {
    try {
      console.log(`Cleaning up ${component.name}...`);
      
      if (component.helm) {
        execSync(`helm uninstall ${component.helm} -n ${component.namespace} || true`, { timeout: 60000 });
      } else if (component.manifest) {
        execSync(`kubectl delete namespace ${component.namespace} || true`, { timeout: 60000 });
      } else if (component.istio) {
        // Istio cleanup is more complex
        try {
          execSync('istioctl uninstall --purge -y || true', { timeout: 120000 });
          execSync('kubectl delete namespace istio-system || true', { timeout: 60000 });
        } catch (error) {
          console.warn(`Could not fully cleanup Istio: ${error.message}`);
        }
      }
    } catch (error) {
      results.warnings.push(`Could not cleanup ${component.name}: ${error.message}`);
    }
  }
}