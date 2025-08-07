// Monitoring Setup Script for IDP Platform
// Handles Prometheus, Grafana, Jaeger setup for observability

import { execSync } from "node:child_process";

export async function main(config: {
  action?: string;
  install_prometheus?: boolean;
  install_grafana?: boolean;
  install_jaeger?: boolean;
  install_kiali?: boolean;
  dry_run?: boolean;
} = {}) {
  const { 
    action = "setup-stack",
    install_prometheus = true,
    install_grafana = true,
    install_jaeger = true,
    install_kiali = true,
    dry_run = false 
  } = config;
  
  console.log(`📊 Monitoring setup - Action: ${action}${dry_run ? ' (dry run)' : ''}`);
  
  const results = {
    success: true,
    action,
    dry_run,
    components: {
      prometheus: { enabled: install_prometheus, status: "pending" as const },
      grafana: { enabled: install_grafana, status: "pending" as const },
      jaeger: { enabled: install_jaeger, status: "pending" as const },
      kiali: { enabled: install_kiali, status: "pending" as const }
    },
    services: [] as Array<{name: string; url: string; status: string}>,
    dashboards: [] as Array<{name: string; url: string}>,
    errors: [] as string[],
    warnings: [] as string[]
  };

  try {
    switch (action) {
      case "setup-stack":
        await setupMonitoringStack(results, dry_run);
        break;
      case "status":
        await checkMonitoringStatus(results);
        break;
      case "cleanup":
        await cleanupMonitoring(results, dry_run);
        break;
      default:
        throw new Error(`Unknown action: ${action}`);
    }

    const failedComponents = Object.values(results.components).filter(c => c.enabled && c.status === "failed");
    if (failedComponents.length > 0) {
      results.success = false;
      console.log(`❌ Monitoring setup failed - ${failedComponents.length} components failed`);
    } else {
      console.log("✅ Monitoring setup completed successfully");
    }

  } catch (error: any) {
    console.error(`💥 Monitoring setup error: ${error.message}`);
    results.success = false;
    (results as any).error = error.message;
  }

  return results;
}

async function setupMonitoringStack(results: any, dryRun: boolean) {
  console.log("Setting up monitoring stack...");

  // Ensure monitoring namespace exists
  try {
    if (!dryRun) {
      try {
        execSync('kubectl get namespace monitoring', { timeout: 10000 });
        console.log("Namespace monitoring already exists");
      } catch (error) {
        execSync('kubectl create namespace monitoring', { timeout: 10000 });
        console.log("Created namespace: monitoring");
      }
    }
  } catch (error: any) {
    results.warnings.push("Could not create monitoring namespace");
  }

  // Setup Prometheus
  if (results.components.prometheus.enabled) {
    await setupPrometheus(results, dryRun);
  }

  // Setup Grafana
  if (results.components.grafana.enabled) {
    await setupGrafana(results, dryRun);
  }

  // Setup Jaeger
  if (results.components.jaeger.enabled) {
    await setupJaeger(results, dryRun);
  }

  // Setup Kiali
  if (results.components.kiali.enabled) {
    await setupKiali(results, dryRun);
  }
}

async function setupPrometheus(results: any, dryRun: boolean) {
  console.log("📈 Setting up Prometheus...");

  try {
    if (!dryRun) {
      // Check if Prometheus is already installed
      try {
        const prometheusPods = execSync('kubectl get pods -n monitoring -l app=prometheus --no-headers', 
          { encoding: 'utf-8', timeout: 10000 });
        if (prometheusPods.trim()) {
          console.log("Prometheus already installed");
          results.components.prometheus.status = "running";
          results.services.push({
            name: "Prometheus",
            url: "http://localhost:9090",
            status: "running"
          });
          return;
        }
      } catch (error) {
        // Prometheus not installed
      }

      // Add Prometheus Helm repository
      console.log("Adding Prometheus Helm repository...");
      execSync('helm repo add prometheus-community https://prometheus-community.github.io/helm-charts', 
        { timeout: 30000 });
      execSync('helm repo update', { timeout: 30000 });

      // Install Prometheus
      console.log("Installing Prometheus...");
      const prometheusValues = `
server:
  service:
    type: LoadBalancer
  persistentVolume:
    enabled: false
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
alertmanager:
  enabled: true
  service:
    type: LoadBalancer
  persistentVolume:
    enabled: false
nodeExporter:
  enabled: true
pushgateway:
  enabled: false
`;

      execSync(`echo '${prometheusValues}' | helm install prometheus prometheus-community/prometheus --namespace monitoring --create-namespace -f -`, 
        { timeout: 180000 });

      console.log("Waiting for Prometheus to be ready...");
      execSync('kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=prometheus -n monitoring --timeout=180s', 
        { timeout: 200000 });

      results.components.prometheus.status = "installed";
      results.services.push({
        name: "Prometheus",
        url: "http://localhost:9090", 
        status: "installed"
      });

    } else {
      console.log("DRY RUN: Would install Prometheus");
      results.components.prometheus.status = "dry-run";
    }

  } catch (error: any) {
    console.error(`Failed to setup Prometheus: ${error.message}`);
    results.components.prometheus.status = "failed";
    results.errors.push(`Prometheus setup failed: ${error.message}`);
  }
}

async function setupGrafana(results: any, dryRun: boolean) {
  console.log("📊 Setting up Grafana...");

  try {
    if (!dryRun) {
      // Check if Grafana is already installed
      try {
        const grafanaPods = execSync('kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers', 
          { encoding: 'utf-8', timeout: 10000 });
        if (grafanaPods.trim()) {
          console.log("Grafana already installed");
          results.components.grafana.status = "running";
          results.services.push({
            name: "Grafana",
            url: "http://localhost:3001",
            status: "running"
          });
          return;
        }
      } catch (error) {
        // Grafana not installed
      }

      // Add Grafana Helm repository
      console.log("Adding Grafana Helm repository...");
      execSync('helm repo add grafana https://grafana.github.io/helm-charts', { timeout: 30000 });
      execSync('helm repo update', { timeout: 30000 });

      // Install Grafana
      console.log("Installing Grafana...");
      const grafanaValues = `
service:
  type: LoadBalancer
  port: 3001
  targetPort: 3000
adminPassword: admin
persistence:
  enabled: false
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.monitoring.svc.cluster.local
      access: proxy
      isDefault: true
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/default
dashboards:
  default:
    kubernetes-cluster-monitoring:
      gnetId: 7249
      revision: 1
      datasource: Prometheus
    istio-service-dashboard:
      gnetId: 7636
      revision: 22
      datasource: Prometheus
`;

      execSync(`echo '${grafanaValues}' | helm install grafana grafana/grafana --namespace monitoring -f -`, 
        { timeout: 180000 });

      console.log("Waiting for Grafana to be ready...");
      execSync('kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=grafana -n monitoring --timeout=180s', 
        { timeout: 200000 });

      results.components.grafana.status = "installed";
      results.services.push({
        name: "Grafana",
        url: "http://localhost:3001",
        status: "installed"
      });

      results.dashboards.push(
        { name: "Kubernetes Cluster Monitoring", url: "http://localhost:3001/d/kubernetes-cluster-monitoring" },
        { name: "Istio Service Dashboard", url: "http://localhost:3001/d/istio-service-dashboard" }
      );

    } else {
      console.log("DRY RUN: Would install Grafana");
      results.components.grafana.status = "dry-run";
    }

  } catch (error: any) {
    console.error(`Failed to setup Grafana: ${error.message}`);
    results.components.grafana.status = "failed";
    results.errors.push(`Grafana setup failed: ${error.message}`);
  }
}

async function setupJaeger(results: any, dryRun: boolean) {
  console.log("🔍 Setting up Jaeger for distributed tracing...");

  try {
    if (!dryRun) {
      // Check if Jaeger is already installed
      try {
        const jaegerPods = execSync('kubectl get pods -n monitoring -l app=jaeger --no-headers', 
          { encoding: 'utf-8', timeout: 10000 });
        if (jaegerPods.trim()) {
          console.log("Jaeger already installed");
          results.components.jaeger.status = "running";
          results.services.push({
            name: "Jaeger",
            url: "http://localhost:16686",
            status: "running"
          });
          return;
        }
      } catch (error) {
        // Jaeger not installed
      }

      // Install Jaeger (All-in-One for development)
      console.log("Installing Jaeger...");
      const jaegerManifest = `
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: monitoring
  labels:
    app: jaeger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
      - name: jaeger
        image: jaegertracing/all-in-one:1.42
        env:
        - name: COLLECTOR_OTLP_ENABLED
          value: "true"
        ports:
        - containerPort: 16686
          name: ui
        - containerPort: 14268
          name: collector
        - containerPort: 14250
          name: grpc
        - containerPort: 4317
          name: otlp-grpc
        - containerPort: 4318
          name: otlp-http
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: jaeger
  namespace: monitoring
  labels:
    app: jaeger
spec:
  type: LoadBalancer
  ports:
  - port: 16686
    targetPort: 16686
    name: ui
  - port: 14268
    targetPort: 14268
    name: collector
  - port: 14250
    targetPort: 14250
    name: grpc
  - port: 4317
    targetPort: 4317
    name: otlp-grpc
  - port: 4318
    targetPort: 4318
    name: otlp-http
  selector:
    app: jaeger
`;

      execSync(`echo '${jaegerManifest}' | kubectl apply -f -`, { timeout: 60000 });

      console.log("Waiting for Jaeger to be ready...");
      execSync('kubectl wait --for=condition=Ready pods -l app=jaeger -n monitoring --timeout=120s', 
        { timeout: 140000 });

      results.components.jaeger.status = "installed";
      results.services.push({
        name: "Jaeger",
        url: "http://localhost:16686",
        status: "installed"
      });

    } else {
      console.log("DRY RUN: Would install Jaeger");
      results.components.jaeger.status = "dry-run";
    }

  } catch (error: any) {
    console.error(`Failed to setup Jaeger: ${error.message}`);
    results.components.jaeger.status = "failed";
    results.errors.push(`Jaeger setup failed: ${error.message}`);
  }
}

async function setupKiali(results: any, dryRun: boolean) {
  console.log("🕸️ Setting up Kiali for service mesh observability...");

  try {
    if (!dryRun) {
      // Check if Istio is installed (required for Kiali)
      try {
        execSync('kubectl get pods -n istio-system --no-headers', { timeout: 10000 });
      } catch (error) {
        console.log("Istio not found, skipping Kiali setup");
        results.components.kiali.status = "skipped";
        results.warnings.push("Kiali requires Istio - skipping installation");
        return;
      }

      // Check if Kiali is already installed
      try {
        const kialiPods = execSync('kubectl get pods -n istio-system -l app=kiali --no-headers', 
          { encoding: 'utf-8', timeout: 10000 });
        if (kialiPods.trim()) {
          console.log("Kiali already installed");
          results.components.kiali.status = "running";
          results.services.push({
            name: "Kiali",
            url: "http://localhost:20001",
            status: "running"
          });
          return;
        }
      } catch (error) {
        // Kiali not installed
      }

      // Install Kiali
      console.log("Installing Kiali...");
      execSync('kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/kiali.yaml', 
        { timeout: 60000 });

      console.log("Waiting for Kiali to be ready...");
      execSync('kubectl wait --for=condition=Ready pods -l app=kiali -n istio-system --timeout=180s', 
        { timeout: 200000 });

      // Patch service for external access
      execSync('kubectl patch svc kiali -n istio-system -p \'{"spec": {"type": "LoadBalancer"}}\'', 
        { timeout: 10000 });

      results.components.kiali.status = "installed";
      results.services.push({
        name: "Kiali",
        url: "http://localhost:20001",
        status: "installed"
      });

    } else {
      console.log("DRY RUN: Would install Kiali");
      results.components.kiali.status = "dry-run";
    }

  } catch (error: any) {
    console.error(`Failed to setup Kiali: ${error.message}`);
    results.components.kiali.status = "failed";
    results.errors.push(`Kiali setup failed: ${error.message}`);
  }
}

async function checkMonitoringStatus(results: any) {
  console.log("Checking monitoring stack status...");

  const components = [
    { name: "prometheus", namespace: "monitoring", selector: "app.kubernetes.io/name=prometheus" },
    { name: "grafana", namespace: "monitoring", selector: "app.kubernetes.io/name=grafana" },
    { name: "jaeger", namespace: "monitoring", selector: "app=jaeger" },
    { name: "kiali", namespace: "istio-system", selector: "app=kiali" }
  ];

  for (const component of components) {
    try {
      const pods = execSync(`kubectl get pods -n ${component.namespace} -l ${component.selector} --no-headers`, 
        { encoding: 'utf-8', timeout: 10000 });
      
      const podLines = pods.trim().split('\n').filter(line => line.trim());
      const runningPods = podLines.filter(line => line.includes('Running')).length;
      const totalPods = podLines.length;

      if (totalPods > 0) {
        results.components[component.name].status = runningPods === totalPods ? "running" : "degraded";
        (results.components[component.name] as any).pods = { running: runningPods, total: totalPods };
      } else {
        results.components[component.name].status = "not-installed";
      }
    } catch (error) {
      results.components[component.name].status = "not-installed";
    }
  }
}

async function cleanupMonitoring(results: any, dryRun: boolean) {
  console.log("Cleaning up monitoring stack...");

  if (dryRun) {
    console.log("DRY RUN: Would cleanup monitoring components");
    return;
  }

  const cleanupOrder = [
    { name: "Kiali", namespace: "istio-system", manifest: true },
    { name: "Jaeger", namespace: "monitoring", manifest: true },
    { name: "Grafana", namespace: "monitoring", helm: "grafana" },
    { name: "Prometheus", namespace: "monitoring", helm: "prometheus" }
  ];

  for (const component of cleanupOrder) {
    try {
      console.log(`Cleaning up ${component.name}...`);
      
      if (component.helm) {
        execSync(`helm uninstall ${component.helm} -n ${component.namespace} || true`, { timeout: 60000 });
      } else if (component.manifest && component.name === "Kiali") {
        execSync('kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/kiali.yaml || true', 
          { timeout: 60000 });
      } else if (component.manifest && component.name === "Jaeger") {
        execSync('kubectl delete deployment,service jaeger -n monitoring || true', { timeout: 30000 });
      }
    } catch (error: any) {
      results.warnings.push(`Could not cleanup ${component.name}: ${error.message}`);
    }
  }

  // Cleanup namespace
  try {
    execSync('kubectl delete namespace monitoring || true', { timeout: 60000 });
  } catch (error: any) {
    results.warnings.push(`Could not cleanup monitoring namespace: ${error.message}`);
  }
}