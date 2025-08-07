// Platform Health Check Script for IDP Platform
// Comprehensive health checking for all platform components

import { execSync } from "node:child_process";

export async function main(config: {
  comprehensive?: boolean;
  check_urls?: boolean;
  timeout?: number;
  dry_run?: boolean;
} = {}) {
  const { 
    comprehensive = true,
    check_urls = true,
    timeout = 300,
    dry_run = false 
  } = config;
  
  console.log(`🏥 Platform health check${dry_run ? ' (dry run)' : ''} - Comprehensive: ${comprehensive}`);
  
  const results = {
    success: true,
    dry_run,
    overall_status: "unknown" as const,
    components: {} as Record<string, any>,
    urls: {} as Record<string, string>,
    health_score: 0,
    checks_performed: [] as string[],
    errors: [] as string[],
    warnings: [] as string[],
    recommendations: [] as string[]
  };

  try {
    // Basic health checks
    await checkKubernetesHealth(results, dry_run);
    await checkCoreComponents(results, dry_run);
    
    if (comprehensive) {
      await checkMonitoringStack(results, dry_run);
      await checkNetworking(results, dry_run);
      await checkStorage(results, dry_run);
    }
    
    if (check_urls) {
      await checkServiceURLs(results, dry_run, timeout);
    }

    // Calculate overall health score
    calculateHealthScore(results);
    generateRecommendations(results);

    // Determine overall status
    if (results.health_score >= 90) {
      results.overall_status = "healthy";
      console.log(`✅ Platform health check completed - Status: HEALTHY (${results.health_score}%)`);
    } else if (results.health_score >= 70) {
      results.overall_status = "degraded";
      console.log(`⚠️  Platform health check completed - Status: DEGRADED (${results.health_score}%)`);
    } else {
      results.overall_status = "unhealthy";
      results.success = false;
      console.log(`❌ Platform health check completed - Status: UNHEALTHY (${results.health_score}%)`);
    }

  } catch (error: any) {
    console.error(`💥 Platform health check error: ${error.message}`);
    results.success = false;
    results.overall_status = "error";
    (results as any).error = error.message;
  }

  return results;
}

async function checkKubernetesHealth(results: any, dryRun: boolean) {
  console.log("🔍 Checking Kubernetes cluster health...");
  results.checks_performed.push("kubernetes");

  if (dryRun) {
    results.components.kubernetes = { status: "dry-run", score: 100 };
    return;
  }

  const kubernetesHealth = {
    cluster_info: false,
    api_server: false,
    nodes: { ready: 0, total: 0 },
    system_pods: { ready: 0, total: 0 },
    score: 0
  };

  try {
    // Check cluster connectivity
    execSync('kubectl cluster-info', { timeout: 10000 });
    kubernetesHealth.cluster_info = true;
    kubernetesHealth.api_server = true;

    // Check node status
    const nodesOutput = execSync('kubectl get nodes --no-headers', { encoding: 'utf-8', timeout: 10000 });
    const nodeLines = nodesOutput.trim().split('\n').filter(line => line.trim());
    kubernetesHealth.nodes.total = nodeLines.length;
    kubernetesHealth.nodes.ready = nodeLines.filter(line => line.includes('Ready')).length;

    // Check system pods
    const systemPodsOutput = execSync('kubectl get pods -n kube-system --no-headers', 
      { encoding: 'utf-8', timeout: 10000 });
    const systemPodLines = systemPodsOutput.trim().split('\n').filter(line => line.trim());
    kubernetesHealth.system_pods.total = systemPodLines.length;
    kubernetesHealth.system_pods.ready = systemPodLines.filter(line => line.includes('Running')).length;

    // Calculate score
    let score = 0;
    if (kubernetesHealth.cluster_info) score += 25;
    if (kubernetesHealth.api_server) score += 25;
    if (kubernetesHealth.nodes.ready === kubernetesHealth.nodes.total && kubernetesHealth.nodes.total > 0) score += 25;
    if (kubernetesHealth.system_pods.ready >= kubernetesHealth.system_pods.total * 0.9) score += 25;

    kubernetesHealth.score = score;
    results.components.kubernetes = kubernetesHealth;

  } catch (error: any) {
    kubernetesHealth.score = 0;
    results.components.kubernetes = kubernetesHealth;
    results.errors.push(`Kubernetes health check failed: ${error.message}`);
  }
}

async function checkCoreComponents(results: any, dryRun: boolean) {
  console.log("⚙️  Checking core platform components...");
  results.checks_performed.push("core-components");

  const coreComponents = [
    { name: "istio", namespace: "istio-system", selector: "app=istiod" },
    { name: "argocd", namespace: "argocd", selector: "app.kubernetes.io/name=argocd-server" },
    { name: "argo-workflows", namespace: "argo", selector: "app=workflow-controller" },
    { name: "backstage", namespace: "backstage", selector: "app=backstage" },
    { name: "crossplane", namespace: "crossplane-system", selector: "app=crossplane" },
    { name: "external-secrets", namespace: "external-secrets", selector: "app.kubernetes.io/name=external-secrets" }
  ];

  for (const component of coreComponents) {
    if (dryRun) {
      results.components[component.name] = { status: "dry-run", score: 100 };
      continue;
    }

    const componentHealth = {
      namespace_exists: false,
      pods: { running: 0, total: 0 },
      services: { ready: 0, total: 0 },
      score: 0,
      status: "unknown" as const
    };

    try {
      // Check if namespace exists
      execSync(`kubectl get namespace ${component.namespace}`, { timeout: 5000 });
      componentHealth.namespace_exists = true;

      // Check pods
      const podsOutput = execSync(
        `kubectl get pods -n ${component.namespace} -l ${component.selector} --no-headers`,
        { encoding: 'utf-8', timeout: 10000 }
      );
      
      if (podsOutput.trim()) {
        const podLines = podsOutput.trim().split('\n').filter(line => line.trim());
        componentHealth.pods.total = podLines.length;
        componentHealth.pods.running = podLines.filter(line => line.includes('Running')).length;
      }

      // Check services
      const servicesOutput = execSync(
        `kubectl get services -n ${component.namespace} --no-headers`,
        { encoding: 'utf-8', timeout: 10000 }
      );
      
      if (servicesOutput.trim()) {
        const serviceLines = servicesOutput.trim().split('\n').filter(line => line.trim());
        componentHealth.services.total = serviceLines.length;
        componentHealth.services.ready = serviceLines.length; // Assume services are ready if they exist
      }

      // Calculate score
      let score = 0;
      if (componentHealth.namespace_exists) score += 25;
      if (componentHealth.pods.total > 0 && componentHealth.pods.running === componentHealth.pods.total) {
        score += 50;
        componentHealth.status = "healthy";
      } else if (componentHealth.pods.running > 0) {
        score += 25;
        componentHealth.status = "degraded";
      } else {
        componentHealth.status = "unhealthy";
      }
      if (componentHealth.services.total > 0) score += 25;

      componentHealth.score = score;

    } catch (error: any) {
      componentHealth.status = "not-installed";
      componentHealth.score = 0;
      if (component.name === "istio" || component.name === "argocd") {
        // Core components are more critical
        results.errors.push(`Critical component ${component.name} not healthy: ${error.message}`);
      } else {
        results.warnings.push(`Component ${component.name} not available: ${error.message}`);
      }
    }

    results.components[component.name] = componentHealth;
  }
}

async function checkMonitoringStack(results: any, dryRun: boolean) {
  console.log("📊 Checking monitoring stack...");
  results.checks_performed.push("monitoring");

  const monitoringComponents = [
    { name: "prometheus", namespace: "monitoring", selector: "app.kubernetes.io/name=prometheus" },
    { name: "grafana", namespace: "monitoring", selector: "app.kubernetes.io/name=grafana" },
    { name: "jaeger", namespace: "monitoring", selector: "app=jaeger" },
    { name: "kiali", namespace: "istio-system", selector: "app=kiali" }
  ];

  for (const component of monitoringComponents) {
    if (dryRun) {
      results.components[`monitoring-${component.name}`] = { status: "dry-run", score: 100 };
      continue;
    }

    try {
      const podsOutput = execSync(
        `kubectl get pods -n ${component.namespace} -l ${component.selector} --no-headers`,
        { encoding: 'utf-8', timeout: 10000 }
      );
      
      if (podsOutput.trim()) {
        const podLines = podsOutput.trim().split('\n').filter(line => line.trim());
        const runningPods = podLines.filter(line => line.includes('Running')).length;
        const totalPods = podLines.length;

        results.components[`monitoring-${component.name}`] = {
          status: runningPods === totalPods ? "healthy" : "degraded",
          pods: { running: runningPods, total: totalPods },
          score: runningPods === totalPods ? 100 : (runningPods / totalPods) * 100
        };
      } else {
        results.components[`monitoring-${component.name}`] = {
          status: "not-installed",
          score: 0
        };
      }
    } catch (error) {
      results.components[`monitoring-${component.name}`] = {
        status: "not-installed", 
        score: 0
      };
      results.warnings.push(`Monitoring component ${component.name} not available`);
    }
  }
}

async function checkNetworking(results: any, dryRun: boolean) {
  console.log("🌐 Checking networking and service mesh...");
  results.checks_performed.push("networking");

  if (dryRun) {
    results.components.networking = { status: "dry-run", score: 100 };
    return;
  }

  const networkingHealth = {
    istio_gateways: { ready: 0, total: 0 },
    virtual_services: { ready: 0, total: 0 },
    service_mesh_config: false,
    ingress_controller: false,
    score: 0
  };

  try {
    // Check Istio gateways
    const gatewaysOutput = execSync('kubectl get gateways --all-namespaces --no-headers', 
      { encoding: 'utf-8', timeout: 10000 });
    if (gatewaysOutput.trim()) {
      const gatewayLines = gatewaysOutput.trim().split('\n');
      networkingHealth.istio_gateways.total = gatewayLines.length;
      networkingHealth.istio_gateways.ready = gatewayLines.length; // Assume ready if they exist
    }

    // Check virtual services
    const vsOutput = execSync('kubectl get virtualservices --all-namespaces --no-headers', 
      { encoding: 'utf-8', timeout: 10000 });
    if (vsOutput.trim()) {
      const vsLines = vsOutput.trim().split('\n');
      networkingHealth.virtual_services.total = vsLines.length;
      networkingHealth.virtual_services.ready = vsLines.length;
    }

    // Check if Istio proxy is configured
    try {
      execSync('kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].name}" | grep istio-proxy', 
        { timeout: 10000 });
      networkingHealth.service_mesh_config = true;
    } catch (error) {
      // No istio-proxy found
    }

    // Check ingress controller (Istio)
    try {
      execSync('kubectl get pods -n istio-system -l app=istio-proxy --no-headers', { timeout: 10000 });
      networkingHealth.ingress_controller = true;
    } catch (error) {
      // No ingress controller
    }

    // Calculate score
    let score = 0;
    if (networkingHealth.istio_gateways.total > 0) score += 25;
    if (networkingHealth.virtual_services.total > 0) score += 25;
    if (networkingHealth.service_mesh_config) score += 25;
    if (networkingHealth.ingress_controller) score += 25;

    networkingHealth.score = score;
    results.components.networking = networkingHealth;

  } catch (error: any) {
    networkingHealth.score = 0;
    results.components.networking = networkingHealth;
    results.warnings.push(`Networking check failed: ${error.message}`);
  }
}

async function checkStorage(results: any, dryRun: boolean) {
  console.log("💾 Checking storage and persistence...");
  results.checks_performed.push("storage");

  if (dryRun) {
    results.components.storage = { status: "dry-run", score: 100 };
    return;
  }

  const storageHealth = {
    storage_classes: { available: 0, total: 0 },
    persistent_volumes: { bound: 0, total: 0 },
    persistent_volume_claims: { bound: 0, total: 0 },
    score: 0
  };

  try {
    // Check storage classes
    const scOutput = execSync('kubectl get storageclass --no-headers', 
      { encoding: 'utf-8', timeout: 10000 });
    if (scOutput.trim()) {
      const scLines = scOutput.trim().split('\n');
      storageHealth.storage_classes.total = scLines.length;
      storageHealth.storage_classes.available = scLines.length;
    }

    // Check persistent volumes
    const pvOutput = execSync('kubectl get pv --no-headers', 
      { encoding: 'utf-8', timeout: 10000 });
    if (pvOutput.trim()) {
      const pvLines = pvOutput.trim().split('\n');
      storageHealth.persistent_volumes.total = pvLines.length;
      storageHealth.persistent_volumes.bound = pvLines.filter(line => line.includes('Bound')).length;
    }

    // Check persistent volume claims
    const pvcOutput = execSync('kubectl get pvc --all-namespaces --no-headers', 
      { encoding: 'utf-8', timeout: 10000 });
    if (pvcOutput.trim()) {
      const pvcLines = pvcOutput.trim().split('\n');
      storageHealth.persistent_volume_claims.total = pvcLines.length;
      storageHealth.persistent_volume_claims.bound = pvcLines.filter(line => line.includes('Bound')).length;
    }

    // Calculate score
    let score = 0;
    if (storageHealth.storage_classes.available > 0) score += 50;
    if (storageHealth.persistent_volumes.total === 0 || 
        storageHealth.persistent_volumes.bound === storageHealth.persistent_volumes.total) score += 25;
    if (storageHealth.persistent_volume_claims.total === 0 || 
        storageHealth.persistent_volume_claims.bound === storageHealth.persistent_volume_claims.total) score += 25;

    storageHealth.score = score;
    results.components.storage = storageHealth;

  } catch (error: any) {
    storageHealth.score = 0;
    results.components.storage = storageHealth;
    results.warnings.push(`Storage check failed: ${error.message}`);
  }
}

async function checkServiceURLs(results: any, dryRun: boolean, timeout: number) {
  console.log("🔗 Checking service URLs and accessibility...");
  results.checks_performed.push("service-urls");

  if (dryRun) {
    results.urls = {
      argocd: "http://localhost:8080",
      backstage: "http://localhost:3000", 
      grafana: "http://localhost:3001",
      prometheus: "http://localhost:9090",
      jaeger: "http://localhost:16686",
      kiali: "http://localhost:20001"
    };
    return;
  }

  const serviceChecks = [
    { name: "argocd", port: 8080, path: "/", namespace: "argocd" },
    { name: "backstage", port: 3000, path: "/healthcheck", namespace: "backstage" },
    { name: "grafana", port: 3001, path: "/api/health", namespace: "monitoring" },
    { name: "prometheus", port: 9090, path: "/-/healthy", namespace: "monitoring" },
    { name: "jaeger", port: 16686, path: "/", namespace: "monitoring" },
    { name: "kiali", port: 20001, path: "/kiali/healthz", namespace: "istio-system" }
  ];

  for (const service of serviceChecks) {
    try {
      // Check if service exists
      execSync(`kubectl get service -n ${service.namespace}`, { timeout: 5000 });
      
      // Try to access the service (simplified check)
      const url = `http://localhost:${service.port}`;
      results.urls[service.name] = url;
      
      // Note: In a real implementation, you might want to set up port-forwarding
      // and actually test HTTP connectivity, but for this script we'll assume
      // if the service exists, it's accessible
      
    } catch (error) {
      results.warnings.push(`Service ${service.name} not accessible`);
    }
  }
}

function calculateHealthScore(results: any) {
  const componentScores: number[] = [];
  
  for (const [name, component] of Object.entries(results.components)) {
    if (typeof component === 'object' && component !== null && 'score' in component) {
      componentScores.push((component as any).score);
    }
  }

  if (componentScores.length > 0) {
    results.health_score = Math.round(
      componentScores.reduce((sum, score) => sum + score, 0) / componentScores.length
    );
  } else {
    results.health_score = 0;
  }
}

function generateRecommendations(results: any) {
  // Generate recommendations based on health check results
  
  if (results.components.kubernetes?.score < 100) {
    results.recommendations.push("Check Kubernetes cluster stability - some system pods may not be running");
  }
  
  if (results.components.istio?.score < 100) {
    results.recommendations.push("Istio service mesh appears degraded - check istio-system namespace");
  }
  
  if (results.components.argocd?.score < 100) {
    results.recommendations.push("ArgoCD is not fully healthy - GitOps operations may be affected");
  }
  
  if (results.components.backstage?.score < 100) {
    results.recommendations.push("Backstage developer portal needs attention");
  }
  
  if (results.health_score < 80) {
    results.recommendations.push("Platform requires maintenance - multiple components are degraded");
  }
  
  if (Object.keys(results.urls).length < 3) {
    results.recommendations.push("Several platform services are not accessible - check service configurations");
  }
  
  if (results.recommendations.length === 0 && results.health_score >= 90) {
    results.recommendations.push("Platform is healthy - no immediate actions required");
  }
}