// Platform Operations Flow - Start/Stop/Monitor Platform Services
// Provides operational control over the IDP platform

import * as wmill from "windmill-client";
import { idpBridge } from "../integration/windmill-idp-bridge.js";

interface OperationResult {
  name: string;
  status: "completed" | "failed" | "warning";
  output: any;
  timestamp: string;
}

interface PlatformOperationsResults {
  job_id: any;
  operation: string;
  environment: string;
  steps: OperationResult[];
  status: string;
  start_time: string;
  end_time?: string;
  duration?: number;
  services: Record<string, string>;
  error?: string;
}

export async function main(config: {
  operation?: "start" | "stop" | "restart" | "status" | "health";
  services?: string[];
  environment?: "development" | "staging" | "production";
  comprehensive_health?: boolean;
  dry_run?: boolean;
} = {}) {
  const {
    operation = "status",
    services = [],
    environment = "development",
    comprehensive_health = true,
    dry_run = false
  } = config;

  console.log(`⚙️ Platform Operations - ${operation.toUpperCase()}${dry_run ? ' (dry run)' : ''}`);

  const results: PlatformOperationsResults = {
    job_id: wmill.getStaticValue("WM_JOB_ID"),
    operation,
    environment,
    steps: [],
    status: "running",
    start_time: new Date().toISOString(),
    services: {}
  };

  try {
    switch (operation) {
      case "start":
        await startPlatformOperation(results, services, dry_run);
        break;
      case "stop":
        await stopPlatformOperation(results, services, dry_run);
        break;
      case "restart":
        await restartPlatformOperation(results, services, dry_run);
        break;
      case "status":
        await statusPlatformOperation(results, dry_run);
        break;
      case "health":
        await healthCheckOperation(results, comprehensive_health, dry_run);
        break;
      default:
        throw new Error(`Unknown operation: ${operation}`);
    }

    // Final status determination
    const failedSteps = results.steps.filter((step: OperationResult) => step.status === "failed");
    const warningSteps = results.steps.filter((step: OperationResult) => step.status === "warning");

    if (failedSteps.length === 0) {
      results.status = warningSteps.length > 0 ? "completed_with_warnings" : "completed";
      console.log(`✅ Platform ${operation} completed successfully!`);
    } else {
      results.status = "failed";
      console.log(`❌ Platform ${operation} failed with ${failedSteps.length} failed steps`);
    }

  } catch (error: any) {
    console.error(`💥 Platform operations error: ${error.message}`);
    results.status = "failed";
    results.error = error.message;
    results.steps.push({
      name: "operation-error",
      status: "failed",
      output: { error: error.message },
      timestamp: new Date().toISOString()
    });
  }

  results.end_time = new Date().toISOString();
  results.duration = Math.round(
    (new Date(results.end_time).getTime() - new Date(results.start_time).getTime()) / 1000
  );

  console.log(`🏁 Platform ${operation} completed in ${results.duration}s with status: ${results.status}`);

  return {
    success: results.status.startsWith("completed"),
    results,
    platform_ready: results.status === "completed" && operation === "start",
    services: results.services,
    failed_steps: results.steps.filter(s => s.status === "failed").map(s => s.name),
    warnings: results.steps.filter(s => s.status === "warning").map(s => s.name),
    summary: `Platform ${operation} ${results.status} in ${results.duration}s. Services: ${Object.keys(results.services).length}`
  };
}

async function startPlatformOperation(results: PlatformOperationsResults, services: string[], dryRun: boolean) {
  console.log("🚀 Starting platform services...");

  try {
    const startResult = await idpBridge.startPlatform({
      services: services.length > 0 ? services : undefined,
      async: true,
      dry_run: dryRun
    });

    results.steps.push({
      name: "start-services",
      status: startResult.success ? "completed" : "failed",
      output: startResult,
      timestamp: new Date().toISOString()
    });

    if (!startResult.success) {
      throw new Error(`Platform start failed: ${startResult.error}`);
    }

    // Get service URLs after start
    const statusResult = await idpBridge.getPlatformStatus();
    if (statusResult.success && statusResult.output && statusResult.output.services) {
      results.services = statusResult.output.services;
    }

  } catch (error: any) {
    results.steps.push({
      name: "start-services",
      status: "failed",
      output: { error: error.message },
      timestamp: new Date().toISOString()
    });
    throw error;
  }
}

async function stopPlatformOperation(results: PlatformOperationsResults, services: string[], dryRun: boolean) {
  console.log("🛑 Stopping platform services...");

  try {
    const stopResult = await idpBridge.stopPlatform({
      services: services.length > 0 ? services : undefined,
      dry_run: dryRun
    });

    results.steps.push({
      name: "stop-services",
      status: stopResult.success ? "completed" : "failed",
      output: stopResult,
      timestamp: new Date().toISOString()
    });

    if (!stopResult.success) {
      throw new Error(`Platform stop failed: ${stopResult.error}`);
    }

  } catch (error: any) {
    results.steps.push({
      name: "stop-services",
      status: "failed",
      output: { error: error.message },
      timestamp: new Date().toISOString()
    });
    throw error;
  }
}

async function restartPlatformOperation(results: PlatformOperationsResults, services: string[], dryRun: boolean) {
  console.log("🔄 Restarting platform services...");

  // First stop
  await stopPlatformOperation(results, services, dryRun);
  
  // Wait a moment
  if (!dryRun) {
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
  
  // Then start
  await startPlatformOperation(results, services, dryRun);
}

async function statusPlatformOperation(results: PlatformOperationsResults, dryRun: boolean) {
  console.log("📊 Getting platform status...");

  try {
    const statusResult = await idpBridge.getPlatformStatus();

    results.steps.push({
      name: "get-status",
      status: statusResult.success ? "completed" : "failed",
      output: statusResult,
      timestamp: new Date().toISOString()
    });

    if (statusResult.success && statusResult.output) {
      if (statusResult.output.services) {
        results.services = statusResult.output.services;
      }
    }

  } catch (error: any) {
    results.steps.push({
      name: "get-status",
      status: "failed", 
      output: { error: error.message },
      timestamp: new Date().toISOString()
    });
    throw error;
  }
}

async function healthCheckOperation(results: PlatformOperationsResults, comprehensive: boolean, dryRun: boolean) {
  console.log("🏥 Running platform health check...");

  try {
    const healthResult = await idpBridge.runHealthCheck(comprehensive);

    results.steps.push({
      name: "health-check",
      status: healthResult.success ? "completed" : "warning",
      output: healthResult,
      timestamp: new Date().toISOString()
    });

    if (healthResult.success && healthResult.output) {
      if (healthResult.output.urls) {
        results.services = healthResult.output.urls;
      }
      
      // Add health warnings if any
      if (healthResult.output.overall_status !== "healthy") {
        results.steps.push({
          name: "health-warnings",
          status: "warning",
          output: {
            status: healthResult.output.overall_status,
            score: healthResult.output.health_score,
            recommendations: healthResult.output.recommendations
          },
          timestamp: new Date().toISOString()
        });
      }
    }

  } catch (error: any) {
    results.steps.push({
      name: "health-check",
      status: "failed",
      output: { error: error.message },
      timestamp: new Date().toISOString()
    });
    throw error;
  }
}