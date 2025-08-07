// Backstage Build and Deploy Script for IDP Platform
// Handles external Backstage repository integration and deployment

import { execSync } from "node:child_process";

export async function main(config: {
  action?: string;
  sync?: boolean;
  wait_for_ready?: boolean;
  backstage_repo?: string;
  build_only?: boolean;
  dry_run?: boolean;
} = {}) {
  const { 
    action = "build-and-deploy",
    sync = true,
    wait_for_ready = true,
    backstage_repo = "https://github.com/ayansasmal/idp-backstage-app.git",
    build_only = false,
    dry_run = false 
  } = config;
  
  console.log(`🎭 Backstage build - Action: ${action}${dry_run ? ' (dry run)' : ''}`);
  
  const results = {
    success: true,
    action,
    dry_run,
    backstage: {
      repository: backstage_repo,
      clone_status: "pending" as const,
      build_status: "pending" as const,
      deploy_status: "pending" as const,
      container_image: null as string | null
    },
    services: [] as Array<{name: string; url: string; status: string; namespace: string}>,
    errors: [] as string[],
    warnings: [] as string[]
  };

  try {
    switch (action) {
      case "build-and-deploy":
        await cloneBackstageRepo(results, dry_run);
        await buildBackstage(results, dry_run);
        if (!build_only) {
          await deployBackstage(results, dry_run);
          if (wait_for_ready) {
            await waitForBackstageReady(results);
          }
        }
        break;
      case "build-only":
        await cloneBackstageRepo(results, dry_run);
        await buildBackstage(results, dry_run);
        break;
      case "deploy-only":
        await deployBackstage(results, dry_run);
        if (wait_for_ready) {
          await waitForBackstageReady(results);
        }
        break;
      case "status":
        await checkBackstageStatus(results);
        break;
      case "cleanup":
        await cleanupBackstage(results, dry_run);
        break;
      default:
        throw new Error(`Unknown action: ${action}`);
    }

  } catch (error: any) {
    console.error(`💥 Backstage build error: ${error.message}`);
    results.success = false;
    (results as any).error = error.message;
  }

  return results;
}

async function cloneBackstageRepo(results: any, dryRun: boolean) {
  console.log("📥 Cloning Backstage repository...");

  try {
    if (!dryRun) {
      const repoDir = "../idp-backstage-app";
      
      // Check if repo already exists
      try {
        execSync(`test -d ${repoDir}/.git`, { timeout: 5000 });
        console.log("Repository already exists, pulling latest changes...");
        
        // Pull latest changes
        execSync(`cd ${repoDir} && git pull origin main`, { timeout: 30000 });
        results.backstage.clone_status = "updated";
      } catch (error) {
        // Repository doesn't exist, clone it
        console.log("Cloning Backstage repository...");
        execSync(`git clone ${results.backstage.repository} ${repoDir}`, { timeout: 60000 });
        results.backstage.clone_status = "cloned";
      }

      // Verify repository structure
      execSync(`test -f ${repoDir}/package.json`, { timeout: 5000 });
      execSync(`test -f ${repoDir}/app-config.yaml`, { timeout: 5000 });
      
      console.log("✅ Backstage repository ready");

    } else {
      console.log("DRY RUN: Would clone Backstage repository");
      results.backstage.clone_status = "dry-run";
    }

  } catch (error: any) {
    console.error(`Failed to clone repository: ${error.message}`);
    results.backstage.clone_status = "failed";
    results.errors.push(`Repository clone failed: ${error.message}`);
    throw error;
  }
}

async function buildBackstage(results: any, dryRun: boolean) {
  console.log("🔨 Building Backstage application...");

  try {
    if (!dryRun) {
      const repoDir = "../idp-backstage-app";
      
      // Check if yarn is available, otherwise use npm
      let packageManager = "yarn";
      try {
        execSync('yarn --version', { timeout: 5000 });
      } catch (error) {
        packageManager = "npm";
        console.log("Yarn not found, using npm");
      }

      // Install dependencies
      console.log("Installing dependencies...");
      if (packageManager === "yarn") {
        execSync(`cd ${repoDir} && yarn install --frozen-lockfile`, { timeout: 300000 });
      } else {
        execSync(`cd ${repoDir} && npm ci`, { timeout: 300000 });
      }

      // Build the application
      console.log("Building Backstage...");
      if (packageManager === "yarn") {
        execSync(`cd ${repoDir} && yarn build:all`, { timeout: 600000 });
      } else {
        execSync(`cd ${repoDir} && npm run build:all`, { timeout: 600000 });
      }

      // Build Docker image
      console.log("Building Docker image...");
      const imageTag = "idp/backstage-app:latest";
      execSync(`cd ${repoDir} && docker build -t ${imageTag} .`, { timeout: 900000 });

      // Tag for LocalStack ECR if needed
      try {
        const localstackECR = "000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566";
        execSync(`docker tag ${imageTag} ${localstackECR}/backstage-app:latest`, { timeout: 30000 });
        console.log("Tagged image for LocalStack ECR");
      } catch (error) {
        console.warn("Could not tag for LocalStack ECR, continuing...");
      }

      results.backstage.build_status = "completed";
      results.backstage.container_image = imageTag;
      console.log("✅ Backstage build completed");

    } else {
      console.log("DRY RUN: Would build Backstage application and Docker image");
      results.backstage.build_status = "dry-run";
      results.backstage.container_image = "idp/backstage-app:latest";
    }

  } catch (error: any) {
    console.error(`Failed to build Backstage: ${error.message}`);
    results.backstage.build_status = "failed";
    results.errors.push(`Backstage build failed: ${error.message}`);
    throw error;
  }
}

async function deployBackstage(results: any, dryRun: boolean) {
  console.log("🚀 Deploying Backstage to Kubernetes...");

  try {
    if (!dryRun) {
      // Create backstage namespace if it doesn't exist
      try {
        execSync('kubectl get namespace backstage', { timeout: 10000 });
      } catch (error) {
        execSync('kubectl create namespace backstage', { timeout: 10000 });
        console.log("Created namespace: backstage");
      }

      // Apply Backstage deployment manifests
      const backstageManifests = `
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backstage
  namespace: backstage
  labels:
    app: backstage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backstage
  template:
    metadata:
      labels:
        app: backstage
    spec:
      containers:
      - name: backstage
        image: ${results.backstage.container_image || "idp/backstage-app:latest"}
        imagePullPolicy: Never
        ports:
        - containerPort: 7007
          name: http
        env:
        - name: NODE_ENV
          value: production
        - name: APP_CONFIG_backend_listen_port
          value: "7007"
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        readinessProbe:
          httpGet:
            path: /healthcheck
            port: 7007
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /healthcheck
            port: 7007
          initialDelaySeconds: 60
          periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: backstage
  namespace: backstage
  labels:
    app: backstage
spec:
  type: LoadBalancer
  ports:
  - port: 3000
    targetPort: 7007
    name: http
  selector:
    app: backstage
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: backstage
  namespace: backstage
spec:
  hosts:
  - backstage.idp.local
  - localhost
  http:
  - match:
    - port: 3000
    route:
    - destination:
        host: backstage.backstage.svc.cluster.local
        port:
          number: 3000
---
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: backstage-gateway
  namespace: backstage
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 3000
      name: http
      protocol: HTTP
    hosts:
    - backstage.idp.local
    - localhost
`;

      console.log("Applying Backstage manifests...");
      execSync(`echo '${backstageManifests}' | kubectl apply -f -`, { timeout: 60000 });

      results.backstage.deploy_status = "deployed";
      results.services.push({
        name: "Backstage",
        url: "http://localhost:3000",
        status: "deployed",
        namespace: "backstage"
      });

      console.log("✅ Backstage deployed to Kubernetes");

    } else {
      console.log("DRY RUN: Would deploy Backstage to Kubernetes");
      results.backstage.deploy_status = "dry-run";
    }

  } catch (error: any) {
    console.error(`Failed to deploy Backstage: ${error.message}`);
    results.backstage.deploy_status = "failed";
    results.errors.push(`Backstage deployment failed: ${error.message}`);
    throw error;
  }
}

async function waitForBackstageReady(results: any) {
  console.log("⏳ Waiting for Backstage to be ready...");

  try {
    // Wait for pods to be ready
    console.log("Waiting for Backstage pods...");
    execSync('kubectl wait --for=condition=Ready pods -l app=backstage -n backstage --timeout=300s', 
      { timeout: 320000 });

    // Check if service is accessible
    let retries = 30;
    while (retries > 0) {
      try {
        // Try to access Backstage health endpoint
        execSync('kubectl port-forward -n backstage svc/backstage 3000:3000 &', { timeout: 5000 });
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        execSync('curl -f http://localhost:3000/healthcheck', { timeout: 10000 });
        console.log("✅ Backstage is ready and accessible");
        break;
      } catch (error) {
        console.log(`Waiting for Backstage to be accessible... (${retries} retries left)`);
        await new Promise(resolve => setTimeout(resolve, 10000));
        retries--;
      }
    }

    if (retries === 0) {
      results.warnings.push("Backstage may not be fully accessible yet");
    } else {
      // Update service status
      for (const service of results.services) {
        if (service.name === "Backstage") {
          service.status = "running";
        }
      }
    }

  } catch (error: any) {
    console.warn(`Backstage readiness check failed: ${error.message}`);
    results.warnings.push("Could not verify Backstage readiness");
  }
}

async function checkBackstageStatus(results: any) {
  console.log("Checking Backstage status...");

  try {
    // Check if namespace exists
    execSync('kubectl get namespace backstage', { timeout: 10000 });

    // Check deployment status
    const deploymentStatus = execSync('kubectl get deployment backstage -n backstage -o json', 
      { encoding: 'utf-8', timeout: 10000 });
    const deployment = JSON.parse(deploymentStatus);

    const readyReplicas = deployment.status.readyReplicas || 0;
    const replicas = deployment.status.replicas || 0;

    results.backstage.deploy_status = readyReplicas === replicas && replicas > 0 ? "running" : "degraded";
    results.backstage.replicas = { ready: readyReplicas, total: replicas };

    // Check service
    const serviceStatus = execSync('kubectl get service backstage -n backstage -o json', 
      { encoding: 'utf-8', timeout: 10000 });
    const service = JSON.parse(serviceStatus);

    results.services.push({
      name: "Backstage",
      url: "http://localhost:3000",
      status: results.backstage.deploy_status,
      namespace: "backstage"
    });

  } catch (error: any) {
    results.backstage.deploy_status = "not-deployed";
    results.errors.push(`Status check failed: ${error.message}`);
  }
}

async function cleanupBackstage(results: any, dryRun: boolean) {
  console.log("🧹 Cleaning up Backstage deployment...");

  if (dryRun) {
    console.log("DRY RUN: Would cleanup Backstage deployment");
    return;
  }

  try {
    // Delete Backstage namespace (this removes all resources)
    execSync('kubectl delete namespace backstage || true', { timeout: 60000 });
    console.log("Backstage namespace deleted");

    // Remove Docker images
    try {
      execSync('docker rmi idp/backstage-app:latest || true', { timeout: 30000 });
      execSync('docker rmi 000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566/backstage-app:latest || true', 
        { timeout: 30000 });
      console.log("Backstage Docker images removed");
    } catch (error) {
      results.warnings.push("Could not remove all Docker images");
    }

  } catch (error: any) {
    results.warnings.push(`Cleanup failed: ${error.message}`);
  }
}