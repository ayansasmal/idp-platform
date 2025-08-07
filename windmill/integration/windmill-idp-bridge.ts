// Windmill-IDP Bridge Integration Script
// This script provides integration between Windmill flows and existing IDP bash scripts
// Acts as the orchestration layer for LangChain agents

import { execSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Path to the IDP scripts directory
const IDP_SCRIPTS_DIR = resolve(__dirname, "../../scripts");

interface ScriptResult {
  success: boolean;
  output?: any;
  error?: string;
  execution_time?: number;
  command?: string;
}

export class WindmillIDPBridge {
  private async executeIDPScript(
    scriptName: string, 
    action: string, 
    options: Record<string, any> = {},
    timeout: number = 300000
  ): Promise<ScriptResult> {
    const startTime = Date.now();
    
    try {
      // Build command arguments
      const args = [];
      
      // Add action
      if (action) {
        args.push(action);
      }
      
      // Add options as flags
      for (const [key, value] of Object.entries(options)) {
        if (typeof value === 'boolean' && value) {
          args.push(`--${key.replace(/_/g, '-')}`);
        } else if (value !== null && value !== undefined && value !== false) {
          args.push(`--${key.replace(/_/g, '-')}`, String(value));
        }
      }
      
      // Add JSON flag for structured output
      args.push('--json');
      
      const scriptPath = resolve(IDP_SCRIPTS_DIR, scriptName);
      const command = `${scriptPath} ${args.join(' ')}`;
      
      console.log(`Executing: ${command}`);
      
      const output = execSync(command, {
        encoding: 'utf-8',
        timeout,
        cwd: IDP_SCRIPTS_DIR,
        env: { ...process.env, PATH: process.env.PATH }
      });
      
      const executionTime = Date.now() - startTime;
      
      // Try to parse JSON output
      let parsedOutput;
      try {
        parsedOutput = JSON.parse(output);
      } catch (error) {
        // If not JSON, return as string
        parsedOutput = output.trim();
      }
      
      return {
        success: true,
        output: parsedOutput,
        execution_time: executionTime,
        command
      };
      
    } catch (error: any) {
      const executionTime = Date.now() - startTime;
      
      return {
        success: false,
        error: error.message,
        execution_time: executionTime,
        command: `${scriptName} ${action}`
      };
    }
  }

  // Async task management integration
  async runAsyncTask(
    taskName: string, 
    scriptName: string, 
    action: string, 
    options: Record<string, any> = {}
  ): Promise<ScriptResult> {
    try {
      const command = `${resolve(IDP_SCRIPTS_DIR, scriptName)} ${action}`;
      const taskResult = await this.executeIDPScript(
        'async-task-manager.sh',
        'run',
        {
          task_name: taskName,
          script: command,
          ...options
        }
      );
      
      return taskResult;
    } catch (error: any) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  async getTaskStatus(taskName: string): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'async-task-manager.sh',
      'status',
      { task_name: taskName }
    );
  }

  async waitForTask(taskName: string, timeout: number = 3600): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'async-task-manager.sh', 
      'wait',
      { task_name: taskName, timeout }
    );
  }

  async cancelTask(taskName: string): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'async-task-manager.sh',
      'cancel', 
      { task_name: taskName }
    );
  }

  // Core IDP operations
  async setupInfrastructure(options: {
    action?: string;
    localstack_enabled?: boolean;
    opa_enabled?: boolean;
    dry_run?: boolean;
  } = {}): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'infrastructure-setup.sh',
      options.action || 'setup-infrastructure',
      options
    );
  }

  async setupAuthentication(options: {
    action?: string;
    create_test_users?: boolean;
    dry_run?: boolean;
  } = {}): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'auth-management.sh',
      options.action || 'setup-full',
      options
    );
  }

  async setupPlatformCore(options: {
    action?: string;
    sync?: boolean;
    install_istio?: boolean;
    install_argocd?: boolean;
    install_argo_workflows?: boolean;
    dry_run?: boolean;
  } = {}): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'idp.sh',
      'setup',
      options
    );
  }

  async buildBackstage(options: {
    action?: string;
    sync?: boolean;
    wait_for_ready?: boolean;
    dry_run?: boolean;
  } = {}): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'idp.sh',
      'build-backstage',
      options
    );
  }

  async startPlatform(options: {
    services?: string[];
    async?: boolean;
    dry_run?: boolean;
  } = {}): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'idp.sh',
      'start',
      options
    );
  }

  async stopPlatform(options: {
    services?: string[];
    dry_run?: boolean;
  } = {}): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'idp.sh',
      'stop', 
      options
    );
  }

  async getPlatformStatus(): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'idp.sh',
      'status',
      { json: true }
    );
  }

  async runHealthCheck(comprehensive: boolean = true): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'idp.sh',
      'health-check',
      { comprehensive, json: true }
    );
  }

  // Configuration management
  async runConfigurationWizard(): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'configuration-manager.sh',
      'wizard',
      {}
    );
  }

  async getConfiguration(): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'configuration-manager.sh',
      'show',
      { json: true }
    );
  }

  async validateConfiguration(): Promise<ScriptResult> {
    return await this.executeIDPScript(
      'configuration-manager.sh',
      'validate',
      { json: true }
    );
  }

  // Utility methods for LangChain integration
  async executeCustomCommand(
    command: string, 
    options: Record<string, any> = {}
  ): Promise<ScriptResult> {
    const startTime = Date.now();
    
    try {
      const output = execSync(command, {
        encoding: 'utf-8',
        timeout: options.timeout || 300000,
        cwd: options.working_directory || IDP_SCRIPTS_DIR,
        env: { ...process.env, ...options.environment }
      });
      
      const executionTime = Date.now() - startTime;
      
      return {
        success: true,
        output: output.trim(),
        execution_time: executionTime,
        command
      };
      
    } catch (error: any) {
      const executionTime = Date.now() - startTime;
      
      return {
        success: false,
        error: error.message,
        execution_time: executionTime,
        command
      };
    }
  }

  // Batch operations for complex workflows
  async executeBatch(operations: Array<{
    name: string;
    script: string;
    action: string;
    options?: Record<string, any>;
    async?: boolean;
  }>): Promise<Record<string, ScriptResult>> {
    const results: Record<string, ScriptResult> = {};
    
    for (const operation of operations) {
      console.log(`Executing batch operation: ${operation.name}`);
      
      if (operation.async) {
        // Execute as async task
        results[operation.name] = await this.runAsyncTask(
          operation.name,
          operation.script,
          operation.action,
          operation.options
        );
      } else {
        // Execute synchronously
        results[operation.name] = await this.executeIDPScript(
          operation.script,
          operation.action,
          operation.options
        );
      }
    }
    
    return results;
  }

  // Platform lifecycle management
  async bootstrapPlatform(config: {
    environment?: string;
    enable_monitoring?: boolean;
    enable_auth?: boolean;
    skip_backstage?: boolean;
    dry_run?: boolean;
  } = {}): Promise<Record<string, ScriptResult>> {
    const operations = [
      {
        name: "prerequisites",
        script: "idp.sh", 
        action: "health-check",
        options: { comprehensive: false }
      },
      {
        name: "infrastructure",
        script: "infrastructure-setup.sh",
        action: "setup-infrastructure",
        options: { 
          localstack_enabled: config.environment === "development",
          dry_run: config.dry_run
        }
      }
    ];

    if (config.enable_auth !== false) {
      operations.push({
        name: "authentication", 
        script: "auth-management.sh",
        action: "setup-full",
        options: {
          create_test_users: config.environment === "development",
          dry_run: config.dry_run
        }
      });
    }

    operations.push({
      name: "platform-core",
      script: "idp.sh",
      action: "setup", 
      options: {
        sync: true,
        dry_run: config.dry_run
      }
    });

    if (!config.skip_backstage) {
      operations.push({
        name: "backstage",
        script: "idp.sh",
        action: "build-backstage",
        options: {
          sync: true,
          wait_for_ready: true,
          dry_run: config.dry_run
        }
      });
    }

    return await this.executeBatch(operations);
  }
}

// Export singleton instance
export const idpBridge = new WindmillIDPBridge();

// Windmill-compatible functions for direct use in flows
export async function executeIDPCommand(
  script: string,
  action: string, 
  options: Record<string, any> = {}
): Promise<ScriptResult> {
  return await idpBridge.executeIDPScript(script, action, options);
}

export async function runPlatformBootstrap(config: {
  environment?: string;
  enable_monitoring?: boolean; 
  enable_auth?: boolean;
  skip_backstage?: boolean;
  dry_run?: boolean;
} = {}): Promise<Record<string, ScriptResult>> {
  return await idpBridge.bootstrapPlatform(config);
}

export async function getPlatformHealth(): Promise<ScriptResult> {
  return await idpBridge.runHealthCheck(true);
}

export async function startPlatformServices(): Promise<ScriptResult> {
  return await idpBridge.startPlatform({ async: true });
}

export async function stopPlatformServices(): Promise<ScriptResult> {
  return await idpBridge.stopPlatform();
}