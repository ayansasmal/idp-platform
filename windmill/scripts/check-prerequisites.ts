// Prerequisites Check Script for IDP Platform
// Validates environment and dependencies before platform setup

import { execSync } from "node:child_process";

interface CheckResult {
  name: string;
  status: "passed" | "failed" | "warning";
  message: string;
  required: boolean;
}

interface PortResult {
  port: number;
  status: "available" | "in_use";
  service: string;
}

export async function main(config: {
  environment?: "development" | "staging" | "production";
  dry_run?: boolean;
} = {}) {
  const { environment = "development", dry_run = false } = config;
  
  console.log(`🔍 Checking prerequisites for ${environment} environment${dry_run ? ' (dry run)' : ''}...`);
  
  const results: {
    success: boolean;
    environment: string;
    dry_run: boolean;
    checks: CheckResult[];
    errors: string[];
    warnings: string[];
    summary: Record<string, any>;
    error?: string;
  } = {
    success: true,
    environment,
    dry_run,
    checks: [],
    errors: [],
    warnings: [],
    summary: {}
  };

  try {
    // Check 1: Docker availability
    try {
      const dockerVersion = execSync('docker --version', { encoding: 'utf-8', timeout: 5000 }).trim();
      results.checks.push({
        name: "docker",
        status: "passed",
        message: `Docker available: ${dockerVersion}`,
        required: true
      });
    } catch (error) {
      results.checks.push({
        name: "docker",
        status: "failed", 
        message: "Docker not found or not running",
        required: true
      });
      results.errors.push("Docker is required but not available");
      results.success = false;
    }

    // Check 2: Kubernetes cluster access
    try {
      const kubectlVersion = execSync('kubectl version --client=true --short', { encoding: 'utf-8', timeout: 10000 }).trim();
      results.checks.push({
        name: "kubectl",
        status: "passed",
        message: `kubectl available: ${kubectlVersion}`,
        required: true
      });

      // Try to access cluster
      try {
        execSync('kubectl cluster-info --request-timeout=10s', { encoding: 'utf-8', timeout: 15000 });
        results.checks.push({
          name: "kubernetes-cluster",
          status: "passed",
          message: "Kubernetes cluster accessible",
          required: true
        });
      } catch (error) {
        results.checks.push({
          name: "kubernetes-cluster",
          status: "failed",
          message: "Cannot access Kubernetes cluster",
          required: true
        });
        results.errors.push("Kubernetes cluster access required");
        results.success = false;
      }
    } catch (error) {
      results.checks.push({
        name: "kubectl",
        status: "failed",
        message: "kubectl not found",
        required: true
      });
      results.errors.push("kubectl is required but not available");
      results.success = false;
    }

    // Check 3: Node.js (for Backstage)
    try {
      const nodeVersion = execSync('node --version', { encoding: 'utf-8', timeout: 5000 }).trim();
      const majorVersion = parseInt(nodeVersion.replace('v', '').split('.')[0]);
      
      if (majorVersion >= 16) {
        results.checks.push({
          name: "nodejs",
          status: "passed",
          message: `Node.js ${nodeVersion} (compatible)`,
          required: true
        });
      } else {
        results.checks.push({
          name: "nodejs",
          status: "failed",
          message: `Node.js ${nodeVersion} (requires >=16)`,
          required: true
        });
        results.errors.push("Node.js version 16+ required for Backstage");
        results.success = false;
      }
    } catch (error) {
      results.checks.push({
        name: "nodejs",
        status: "failed",
        message: "Node.js not found",
        required: true
      });
      results.errors.push("Node.js is required for Backstage");
      results.success = false;
    }

    // Check 4: Yarn (for Backstage)
    try {
      const yarnVersion = execSync('yarn --version', { encoding: 'utf-8', timeout: 5000 }).trim();
      results.checks.push({
        name: "yarn",
        status: "passed",
        message: `Yarn ${yarnVersion}`,
        required: true
      });
    } catch (error) {
      results.checks.push({
        name: "yarn",
        status: "warning",
        message: "Yarn not found, will use npm",
        required: false
      });
      results.warnings.push("Yarn preferred for Backstage development");
    }

    // Check 5: Git
    try {
      const gitVersion = execSync('git --version', { encoding: 'utf-8', timeout: 5000 }).trim();
      results.checks.push({
        name: "git",
        status: "passed",
        message: gitVersion,
        required: true
      });
    } catch (error) {
      results.checks.push({
        name: "git",
        status: "failed",
        message: "Git not found",
        required: true
      });
      results.errors.push("Git is required for repository operations");
      results.success = false;
    }

    // Check 6: Helm (for Kubernetes deployments)
    try {
      const helmVersion = execSync('helm version --short', { encoding: 'utf-8', timeout: 5000 }).trim();
      results.checks.push({
        name: "helm",
        status: "passed",
        message: helmVersion,
        required: true
      });
    } catch (error) {
      results.checks.push({
        name: "helm",
        status: "failed",
        message: "Helm not found",
        required: true
      });
      results.errors.push("Helm is required for Kubernetes package management");
      results.success = false;
    }

    // Check 7: Available ports
    const requiredPorts = [3000, 8080, 4566, 3001, 9090, 16686, 20001];
    const portResults: PortResult[] = [];
    
    for (const port of requiredPorts) {
      try {
        // Check if port is in use
        execSync(`lsof -ti:${port}`, { encoding: 'utf-8', timeout: 2000 });
        portResults.push({
          port,
          status: "in_use",
          service: getServiceForPort(port)
        });
      } catch (error) {
        portResults.push({
          port,
          status: "available",
          service: getServiceForPort(port)
        });
      }
    }

    const portsInUse = portResults.filter(p => p.status === "in_use");
    if (portsInUse.length > 0) {
      results.checks.push({
        name: "ports",
        status: "warning",
        message: `Ports in use: ${portsInUse.map(p => `${p.port} (${p.service})`).join(', ')}`,
        required: false
      });
      results.warnings.push("Some required ports are in use - services may conflict");
    } else {
      results.checks.push({
        name: "ports",
        status: "passed", 
        message: "All required ports are available",
        required: false
      });
    }

    // Check 8: Disk space
    try {
      const diskInfo = execSync('df -h .', { encoding: 'utf-8', timeout: 5000 });
      const availableSpace = diskInfo.split('\n')[1].split(/\s+/)[3];
      results.checks.push({
        name: "disk-space",
        status: "passed",
        message: `Available space: ${availableSpace}`,
        required: false
      });
    } catch (error) {
      results.checks.push({
        name: "disk-space",
        status: "warning",
        message: "Could not check disk space",
        required: false
      });
    }

    // Environment-specific checks
    if (environment === "development") {
      // Check for LocalStack in development
      try {
        execSync('which awslocal', { encoding: 'utf-8', timeout: 5000 });
        results.checks.push({
          name: "awslocal",
          status: "passed",
          message: "AWS CLI LocalStack wrapper available",
          required: false
        });
      } catch (error) {
        results.checks.push({
          name: "awslocal",
          status: "warning",
          message: "awslocal not found - will use aws cli",
          required: false
        });
        results.warnings.push("awslocal recommended for LocalStack integration");
      }
    }

    // Generate summary
    const passedChecks = results.checks.filter(c => c.status === "passed").length;
    const failedChecks = results.checks.filter(c => c.status === "failed").length;
    const warningChecks = results.checks.filter(c => c.status === "warning").length;

    results.summary = {
      total_checks: results.checks.length,
      passed: passedChecks,
      failed: failedChecks,
      warnings: warningChecks,
      ready_for_setup: results.success
    };

    if (results.success) {
      console.log(`✅ Prerequisites check completed successfully (${passedChecks}/${results.checks.length} passed)`);
      if (results.warnings.length > 0) {
        console.log(`⚠️  ${results.warnings.length} warnings found`);
      }
    } else {
      console.log(`❌ Prerequisites check failed (${failedChecks} errors, ${warningChecks} warnings)`);
    }

  } catch (error) {
    console.error(`💥 Prerequisites check error: ${error.message}`);
    results.success = false;
    results.error = error.message;
  }

  return results;
}

// Helper function to map ports to services
function getServiceForPort(port: number): string {
  const portMap = {
    3000: "Backstage",
    8080: "ArgoCD",
    4566: "LocalStack",
    3001: "Grafana", 
    9090: "Prometheus",
    16686: "Jaeger",
    20001: "Kiali"
  };
  return portMap[port] || "Unknown";
}