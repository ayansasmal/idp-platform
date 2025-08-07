// Infrastructure Setup Script for IDP Platform
// Handles LocalStack and OPA setup for development environment

import { execSync } from "node:child_process";

export async function main(config: {
  action?: string;
  localstack_enabled?: boolean;
  opa_enabled?: boolean;
  dry_run?: boolean;
} = {}) {
  const { 
    action = "setup-infrastructure",
    localstack_enabled = true, 
    opa_enabled = true,
    dry_run = false 
  } = config;
  
  console.log(`🏗️ Infrastructure setup - Action: ${action}${dry_run ? ' (dry run)' : ''}`);
  
  const results = {
    success: true,
    action,
    dry_run,
    components: {
      localstack: { enabled: localstack_enabled, status: "pending" },
      opa: { enabled: opa_enabled, status: "pending" }
    },
    services: [],
    errors: [],
    warnings: []
  };

  try {
    switch (action) {
      case "setup-infrastructure":
        await setupInfrastructure(results, dry_run);
        break;
      case "status":
        await checkInfrastructureStatus(results);
        break;
      case "test-connectivity":
        await testConnectivity(results);
        break;
      case "cleanup":
        await cleanupInfrastructure(results, dry_run);
        break;
      default:
        throw new Error(`Unknown action: ${action}`);
    }

    const failedComponents = Object.values(results.components).filter(c => c.enabled && c.status === "failed");
    if (failedComponents.length > 0) {
      results.success = false;
      console.log(`❌ Infrastructure setup failed - ${failedComponents.length} components failed`);
    } else {
      console.log("✅ Infrastructure setup completed successfully");
    }

  } catch (error) {
    console.error(`💥 Infrastructure setup error: ${error.message}`);
    results.success = false;
    results.error = error.message;
  }

  return results;
}

async function setupInfrastructure(results: any, dryRun: boolean) {
  console.log("Setting up infrastructure components...");

  // Setup LocalStack if enabled
  if (results.components.localstack.enabled) {
    console.log("🚀 Setting up LocalStack...");
    
    try {
      if (!dryRun) {
        // Check if LocalStack is already running
        try {
          execSync('curl -s http://localhost:4566/_localstack/health', { timeout: 5000 });
          console.log("LocalStack already running, restarting...");
          execSync('docker stop localstack || true', { timeout: 10000 });
          execSync('docker rm localstack || true', { timeout: 10000 });
        } catch (error) {
          // LocalStack not running, which is fine
        }

        // Start LocalStack
        const localstackCmd = `docker run -d \
          --name localstack \
          -p 4566:4566 \
          -e SERVICES=cognito-idp,ecr,rds,secretsmanager,s3,iam \
          -e DEBUG=1 \
          -e PERSISTENCE=1 \
          -e LAMBDA_EXECUTOR=docker \
          -e DOCKER_HOST=unix:///var/run/docker.sock \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v /tmp/localstack:/var/lib/localstack \
          localstack/localstack:latest`;
        
        console.log("Starting LocalStack container...");
        execSync(localstackCmd, { timeout: 30000 });

        // Wait for LocalStack to be ready
        let retries = 30;
        while (retries > 0) {
          try {
            const healthCheck = execSync('curl -s http://localhost:4566/_localstack/health', { 
              encoding: 'utf-8', 
              timeout: 5000 
            });
            const health = JSON.parse(healthCheck);
            
            if (health.services && Object.keys(health.services).length > 0) {
              console.log("LocalStack is ready!");
              break;
            }
          } catch (error) {
            // Still waiting
          }
          
          console.log(`Waiting for LocalStack to be ready... (${retries} retries left)`);
          await new Promise(resolve => setTimeout(resolve, 2000));
          retries--;
        }

        if (retries === 0) {
          throw new Error("LocalStack failed to start within expected time");
        }

        // Verify services
        const healthCheck = execSync('curl -s http://localhost:4566/_localstack/health', { 
          encoding: 'utf-8', 
          timeout: 5000 
        });
        const health = JSON.parse(healthCheck);
        
        results.components.localstack.status = "running";
        results.components.localstack.services = health.services;
        results.services.push({
          name: "LocalStack",
          url: "http://localhost:4566",
          status: "running",
          services: Object.keys(health.services)
        });

      } else {
        console.log("DRY RUN: Would start LocalStack container with AWS services");
        results.components.localstack.status = "dry-run";
      }

    } catch (error) {
      console.error(`Failed to setup LocalStack: ${error.message}`);
      results.components.localstack.status = "failed";
      results.errors.push(`LocalStack setup failed: ${error.message}`);
    }
  }

  // Setup OPA if enabled
  if (results.components.opa.enabled) {
    console.log("🛡️ Setting up Open Policy Agent (OPA)...");
    
    try {
      if (!dryRun) {
        // Check if OPA is already running
        try {
          execSync('docker stop opa || true', { timeout: 10000 });
          execSync('docker rm opa || true', { timeout: 10000 });
        } catch (error) {
          // OPA not running, which is fine
        }

        // Start OPA
        const opaCmd = `docker run -d \
          --name opa \
          -p 8181:8181 \
          openpolicyagent/opa:latest \
          run --server --addr localhost:8181`;
        
        console.log("Starting OPA container...");
        execSync(opaCmd, { timeout: 20000 });

        // Wait for OPA to be ready
        let retries = 15;
        while (retries > 0) {
          try {
            execSync('curl -s http://localhost:8181/health', { timeout: 5000 });
            console.log("OPA is ready!");
            break;
          } catch (error) {
            // Still waiting
          }
          
          console.log(`Waiting for OPA to be ready... (${retries} retries left)`);
          await new Promise(resolve => setTimeout(resolve, 2000));
          retries--;
        }

        if (retries === 0) {
          throw new Error("OPA failed to start within expected time");
        }

        results.components.opa.status = "running";
        results.services.push({
          name: "Open Policy Agent",
          url: "http://localhost:8181",
          status: "running"
        });

        // Load default policies
        console.log("Loading default OPA policies...");
        const defaultPolicy = {
          "kubernetes": {
            "admission": {
              "allow": true
            }
          }
        };

        try {
          execSync(`curl -X PUT http://localhost:8181/v1/data/kubernetes/admission -H 'Content-Type: application/json' -d '${JSON.stringify(defaultPolicy)}'`, 
            { timeout: 10000 });
          console.log("Default OPA policies loaded");
        } catch (error) {
          console.warn("Failed to load default policies, but OPA is running");
          results.warnings.push("Could not load default OPA policies");
        }

      } else {
        console.log("DRY RUN: Would start OPA container and load policies");
        results.components.opa.status = "dry-run";
      }

    } catch (error) {
      console.error(`Failed to setup OPA: ${error.message}`);
      results.components.opa.status = "failed";
      results.errors.push(`OPA setup failed: ${error.message}`);
    }
  }
}

async function checkInfrastructureStatus(results: any) {
  console.log("Checking infrastructure status...");

  // Check LocalStack
  if (results.components.localstack.enabled) {
    try {
      const healthCheck = execSync('curl -s http://localhost:4566/_localstack/health', { 
        encoding: 'utf-8', 
        timeout: 5000 
      });
      const health = JSON.parse(healthCheck);
      
      results.components.localstack.status = "running";
      results.components.localstack.services = health.services;
      results.services.push({
        name: "LocalStack",
        url: "http://localhost:4566",
        status: "running",
        services: Object.keys(health.services)
      });
    } catch (error) {
      results.components.localstack.status = "failed";
      results.errors.push("LocalStack not accessible");
    }
  }

  // Check OPA
  if (results.components.opa.enabled) {
    try {
      execSync('curl -s http://localhost:8181/health', { timeout: 5000 });
      results.components.opa.status = "running";
      results.services.push({
        name: "Open Policy Agent",
        url: "http://localhost:8181", 
        status: "running"
      });
    } catch (error) {
      results.components.opa.status = "failed";
      results.errors.push("OPA not accessible");
    }
  }
}

async function testConnectivity(results: any) {
  console.log("Testing infrastructure connectivity...");

  const tests = [];

  // Test LocalStack connectivity
  if (results.components.localstack.enabled) {
    try {
      // Test basic connectivity
      execSync('curl -s http://localhost:4566/_localstack/health', { timeout: 5000 });
      
      // Test specific services
      try {
        execSync('aws --endpoint-url=http://localhost:4566 --region=us-east-1 cognito-idp list-user-pools --max-results 10', 
          { timeout: 10000 });
        tests.push({ service: "LocalStack Cognito", status: "connected" });
      } catch (error) {
        tests.push({ service: "LocalStack Cognito", status: "error", message: error.message });
      }

      try {
        execSync('aws --endpoint-url=http://localhost:4566 --region=us-east-1 ecr describe-repositories', 
          { timeout: 10000 });
        tests.push({ service: "LocalStack ECR", status: "connected" });
      } catch (error) {
        tests.push({ service: "LocalStack ECR", status: "error", message: error.message });
      }

    } catch (error) {
      tests.push({ service: "LocalStack", status: "failed", message: "Not accessible" });
    }
  }

  // Test OPA connectivity
  if (results.components.opa.enabled) {
    try {
      execSync('curl -s http://localhost:8181/v1/data', { timeout: 5000 });
      tests.push({ service: "OPA", status: "connected" });
    } catch (error) {
      tests.push({ service: "OPA", status: "failed", message: "Not accessible" });
    }
  }

  results.connectivity_tests = tests;
  
  const failedTests = tests.filter(t => t.status === "failed" || t.status === "error");
  if (failedTests.length > 0) {
    results.success = false;
    results.errors.push(`${failedTests.length} connectivity tests failed`);
  }
}

async function cleanupInfrastructure(results: any, dryRun: boolean) {
  console.log("Cleaning up infrastructure...");

  if (!dryRun) {
    // Stop and remove LocalStack
    try {
      execSync('docker stop localstack || true', { timeout: 10000 });
      execSync('docker rm localstack || true', { timeout: 10000 });
      console.log("LocalStack container removed");
    } catch (error) {
      results.warnings.push("Could not remove LocalStack container");
    }

    // Stop and remove OPA
    try {
      execSync('docker stop opa || true', { timeout: 10000 });
      execSync('docker rm opa || true', { timeout: 10000 });
      console.log("OPA container removed");
    } catch (error) {
      results.warnings.push("Could not remove OPA container");
    }

    // Cleanup volumes
    try {
      execSync('docker volume prune -f', { timeout: 10000 });
      console.log("Docker volumes cleaned");
    } catch (error) {
      results.warnings.push("Could not cleanup docker volumes");
    }

  } else {
    console.log("DRY RUN: Would stop and remove LocalStack and OPA containers");
  }

  results.components.localstack.status = "removed";
  results.components.opa.status = "removed";
}