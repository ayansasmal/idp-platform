// IDP Bootstrap Flow - Complete Platform Setup
// This flow sets up the entire IDP platform from scratch
// Designed for initial deployment and disaster recovery scenarios

import * as wmill from "windmill-client";

interface StepResult {
  name: string;
  status: "completed" | "failed" | "warning";
  output: any;
  timestamp: string;
}

interface BootstrapResults {
  job_id: any;
  platform_name: string;
  environment: string;
  steps: StepResult[];
  status: string;
  start_time: string;
  end_time?: string;
  duration?: number;
  urls: Record<string, string>;
  error?: string;
}

export async function main(
  config: {
    platform_name?: string;
    environment?: "development" | "staging" | "production";
    enable_monitoring?: boolean;
    enable_auth?: boolean;
    skip_backstage?: boolean;
    dry_run?: boolean;
  } = {}
) {
  const {
    platform_name = "IDP Platform",
    environment = "development", 
    enable_monitoring = true,
    enable_auth = true,
    skip_backstage = false,
    dry_run = false
  } = config;

  console.log(`🚀 Starting IDP Bootstrap for ${platform_name} (${environment})`);
  
  const results: BootstrapResults = {
    job_id: wmill.getStaticValue("WM_JOB_ID"),
    platform_name,
    environment,
    steps: [],
    status: "running",
    start_time: new Date().toISOString(),
    urls: {}
  };

  try {
    // Step 1: Prerequisites Check
    console.log("📋 Step 1: Checking prerequisites...");
    const prereqResult = await wmill.runScript(
      "f/idp/check-prerequisites",
      { environment, dry_run },
      { stepName: "prerequisites" }
    );
    
    results.steps.push({
      name: "prerequisites",
      status: prereqResult.success ? "completed" : "failed",
      output: prereqResult,
      timestamp: new Date().toISOString()
    });

    if (!prereqResult.success && !dry_run) {
      throw new Error(`Prerequisites check failed: ${prereqResult.error}`);
    }

    // Step 2: Infrastructure Setup (LocalStack + OPA)
    console.log("🏗️  Step 2: Setting up infrastructure...");
    const infraResult = await wmill.runScript(
      "f/idp/setup-infrastructure", 
      { 
        action: "setup-infrastructure",
        localstack_enabled: environment === "development",
        dry_run
      },
      { stepName: "infrastructure" }
    );
    
    results.steps.push({
      name: "infrastructure", 
      status: infraResult.success ? "completed" : "failed",
      output: infraResult,
      timestamp: new Date().toISOString()
    });

    if (!infraResult.success && !dry_run) {
      throw new Error(`Infrastructure setup failed: ${infraResult.error}`);
    }

    // Step 3: Authentication Setup (if enabled)
    if (enable_auth) {
      console.log("🔐 Step 3: Setting up authentication...");
      const authResult = await wmill.runScript(
        "f/idp/setup-authentication",
        {
          action: "setup-full",
          create_test_users: environment === "development", 
          dry_run
        },
        { stepName: "authentication" }
      );
      
      results.steps.push({
        name: "authentication",
        status: authResult.success ? "completed" : "failed", 
        output: authResult,
        timestamp: new Date().toISOString()
      });

      if (!authResult.success && !dry_run) {
        throw new Error(`Authentication setup failed: ${authResult.error}`);
      }
    }

    // Step 4: Core Platform Setup (Istio, ArgoCD, Argo Workflows)
    console.log("⚙️  Step 4: Setting up core platform...");
    const platformResult = await wmill.runScript(
      "f/idp/setup-platform-core",
      {
        action: "setup", 
        sync: true,
        install_istio: true,
        install_argocd: true,
        install_argo_workflows: true,
        dry_run
      },
      { stepName: "platform-core" }
    );
    
    results.steps.push({
      name: "platform-core",
      status: platformResult.success ? "completed" : "failed",
      output: platformResult, 
      timestamp: new Date().toISOString()
    });

    if (!platformResult.success && !dry_run) {
      throw new Error(`Platform core setup failed: ${platformResult.error}`);
    }

    // Step 5: Monitoring Stack (if enabled)
    if (enable_monitoring) {
      console.log("📊 Step 5: Setting up monitoring stack...");
      const monitoringResult = await wmill.runScript(
        "f/idp/setup-monitoring",
        {
          action: "setup-stack",
          install_prometheus: true,
          install_grafana: true, 
          install_jaeger: true,
          dry_run
        },
        { stepName: "monitoring" }
      );
      
      results.steps.push({
        name: "monitoring",
        status: monitoringResult.success ? "completed" : "failed",
        output: monitoringResult,
        timestamp: new Date().toISOString()
      });

      if (!monitoringResult.success && !dry_run) {
        console.warn(`Monitoring setup failed: ${monitoringResult.error}`);
        // Continue execution - monitoring is not critical for basic platform
      }
    }

    // Step 6: Backstage Setup (if enabled)
    if (!skip_backstage) {
      console.log("🎭 Step 6: Setting up Backstage...");
      const backstageResult = await wmill.runScript(
        "f/idp/build-backstage",
        {
          action: "build-and-deploy",
          sync: true,
          wait_for_ready: true,
          dry_run
        },
        { stepName: "backstage" }
      );
      
      results.steps.push({
        name: "backstage", 
        status: backstageResult.success ? "completed" : "failed",
        output: backstageResult,
        timestamp: new Date().toISOString()
      });

      if (!backstageResult.success && !dry_run) {
        console.warn(`Backstage setup failed: ${backstageResult.error}`);
        // Continue execution - platform can work without Backstage
      }
    }

    // Step 7: Final Health Check
    console.log("🏥 Step 7: Running final health check...");
    const healthResult = await wmill.runScript(
      "f/idp/health-check-platform",
      {
        comprehensive: true,
        check_urls: true,
        timeout: 300,
        dry_run
      },
      { stepName: "health-check" }
    );
    
    results.steps.push({
      name: "health-check",
      status: healthResult.success ? "completed" : "warning",
      output: healthResult,
      timestamp: new Date().toISOString()
    });

    // Set platform URLs from health check
    if (healthResult.success && healthResult.urls) {
      results.urls = healthResult.urls;
    }

    // Final status determination
    const failedSteps = results.steps.filter((step: StepResult) => step.status === "failed");
    const warningSteps = results.steps.filter((step: StepResult) => step.status === "warning");
    
    if (failedSteps.length === 0) {
      results.status = warningSteps.length > 0 ? "completed_with_warnings" : "completed";
      console.log("✅ IDP Bootstrap completed successfully!");
    } else {
      results.status = "failed";
      console.log(`❌ IDP Bootstrap failed with ${failedSteps.length} failed steps`);
    }

  } catch (error) {
    console.error(`💥 IDP Bootstrap failed: ${error.message}`);
    results.status = "failed";
    results.error = error.message;
    results.steps.push({
      name: "bootstrap-error",
      status: "failed", 
      output: { error: error.message },
      timestamp: new Date().toISOString()
    });
  }

  results.end_time = new Date().toISOString();
  results.duration = Math.round(
    (new Date(results.end_time).getTime() - new Date(results.start_time).getTime()) / 1000
  );

  console.log(`🏁 Bootstrap completed in ${results.duration}s with status: ${results.status}`);

  // Return structured results for IDP-Agent consumption
  return {
    success: results.status.startsWith("completed"),
    results,
    // Quick access fields for agents
    platform_ready: results.status === "completed",
    platform_urls: results.urls,
    failed_steps: results.steps.filter(s => s.status === "failed").map(s => s.name),
    warnings: results.steps.filter(s => s.status === "warning").map(s => s.name),
    // Agent-friendly summary
    summary: `IDP Bootstrap ${results.status} in ${results.duration}s. ${
      results.urls.backstage ? `Backstage: ${results.urls.backstage}` : 'Backstage not available'
    }${results.urls.argocd ? `, ArgoCD: ${results.urls.argocd}` : ''}`,
  };
}