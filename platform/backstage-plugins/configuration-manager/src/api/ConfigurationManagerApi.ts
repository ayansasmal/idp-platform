import { DiscoveryApi, FetchApi } from '@backstage/core-plugin-api';
import { createApiRef } from '@backstage/core-plugin-api';

export interface ApplicationConfiguration {
  apiVersion: string;
  kind: string;
  metadata: {
    name: string;
    namespace: string;
    labels?: Record<string, string>;
    annotations?: Record<string, string>;
  };
  spec: {
    application: string;
    environments: Record<string, EnvironmentConfig>;
    global?: GlobalConfig;
  };
}

export interface EnvironmentConfig {
  replicas: number;
  resources: {
    requests: ResourceRequirements;
    limits: ResourceRequirements;
  };
  environment: Record<string, string>;
  secrets?: Record<string, string>;
  scaling?: AutoScalingConfig;
  ingress?: IngressConfig;
  database?: DatabaseConfig;
  cache?: CacheConfig;
}

export interface ResourceRequirements {
  cpu: string;
  memory: string;
}

export interface AutoScalingConfig {
  enabled: boolean;
  minReplicas: number;
  maxReplicas: number;
  targetCPUUtilization: number;
  targetMemoryUtilization?: number;
}

export interface IngressConfig {
  enabled: boolean;
  host?: string;
  path?: string;
  tls?: boolean;
  annotations?: Record<string, string>;
}

export interface DatabaseConfig {
  type: 'postgresql' | 'mysql' | 'redis' | 'mongodb';
  size: 'small' | 'medium' | 'large';
  storage: string;
  version?: string;
}

export interface CacheConfig {
  type: 'redis' | 'memcached';
  size: 'small' | 'medium' | 'large';
  nodes: number;
}

export interface GlobalConfig {
  monitoring: {
    enabled: boolean;
    alerts: boolean;
  };
  security: {
    networkPolicies: boolean;
    podSecurityPolicy: string;
  };
  backup: {
    enabled: boolean;
    schedule: string;
    retention: string;
  };
}

export interface ConfigurationTemplate {
  name: string;
  description: string;
  type: 'web-app' | 'api-service' | 'worker' | 'cron-job';
  configuration: Partial<ApplicationConfiguration>;
}

export interface ConfigurationValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
}

export interface ConfigurationManagerApiInterface {
  // Configuration CRUD operations
  getConfiguration(name: string, namespace: string): Promise<ApplicationConfiguration>;
  listConfigurations(namespace?: string): Promise<ApplicationConfiguration[]>;
  createConfiguration(config: ApplicationConfiguration): Promise<ApplicationConfiguration>;
  updateConfiguration(config: ApplicationConfiguration): Promise<ApplicationConfiguration>;
  deleteConfiguration(name: string, namespace: string): Promise<void>;

  // Template operations
  getTemplates(): Promise<ConfigurationTemplate[]>;
  applyTemplate(templateName: string, applicationName: string, namespace: string): Promise<ApplicationConfiguration>;

  // Validation and preview
  validateConfiguration(config: ApplicationConfiguration): Promise<ConfigurationValidationResult>;
  previewConfiguration(config: ApplicationConfiguration): Promise<string>;

  // Environment operations
  promoteConfiguration(name: string, namespace: string, sourceEnv: string, targetEnv: string): Promise<void>;
  rollbackConfiguration(name: string, namespace: string, environment: string, version: string): Promise<void>;

  // History and diff
  getConfigurationHistory(name: string, namespace: string): Promise<any[]>;
  compareConfigurations(name: string, namespace: string, env1: string, env2: string): Promise<any>;

  // Live status
  getApplicationStatus(name: string, namespace: string): Promise<any>;
}

export const configurationManagerApiRef = createApiRef<ConfigurationManagerApiInterface>({
  id: 'plugin.configuration-manager.service',
});

export class ConfigurationManagerApi implements ConfigurationManagerApiInterface {
  private readonly discoveryApi: DiscoveryApi;
  private readonly fetchApi: FetchApi;

  constructor(options: {
    discoveryApi: DiscoveryApi;
    fetchApi: FetchApi;
  }) {
    this.discoveryApi = options.discoveryApi;
    this.fetchApi = options.fetchApi;
  }

  private async getBaseUrl(): Promise<string> {
    const baseUrl = await this.discoveryApi.getBaseUrl('configuration-manager');
    return baseUrl;
  }

  async getConfiguration(name: string, namespace: string): Promise<ApplicationConfiguration> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations/${namespace}/${name}`,
    );

    if (!response.ok) {
      throw new Error(`Failed to fetch configuration: ${response.statusText}`);
    }

    return await response.json();
  }

  async listConfigurations(namespace?: string): Promise<ApplicationConfiguration[]> {
    const baseUrl = await this.getBaseUrl();
    const url = namespace 
      ? `${baseUrl}/configurations/${namespace}`
      : `${baseUrl}/configurations`;
    
    const response = await this.fetchApi.fetch(url);

    if (!response.ok) {
      throw new Error(`Failed to list configurations: ${response.statusText}`);
    }

    return await response.json();
  }

  async createConfiguration(config: ApplicationConfiguration): Promise<ApplicationConfiguration> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(config),
      },
    );

    if (!response.ok) {
      throw new Error(`Failed to create configuration: ${response.statusText}`);
    }

    return await response.json();
  }

  async updateConfiguration(config: ApplicationConfiguration): Promise<ApplicationConfiguration> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations/${config.metadata.namespace}/${config.metadata.name}`,
      {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(config),
      },
    );

    if (!response.ok) {
      throw new Error(`Failed to update configuration: ${response.statusText}`);
    }

    return await response.json();
  }

  async deleteConfiguration(name: string, namespace: string): Promise<void> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations/${namespace}/${name}`,
      {
        method: 'DELETE',
      },
    );

    if (!response.ok) {
      throw new Error(`Failed to delete configuration: ${response.statusText}`);
    }
  }

  async getTemplates(): Promise<ConfigurationTemplate[]> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(`${baseUrl}/templates`);

    if (!response.ok) {
      throw new Error(`Failed to fetch templates: ${response.statusText}`);
    }

    return await response.json();
  }

  async applyTemplate(
    templateName: string,
    applicationName: string,
    namespace: string,
  ): Promise<ApplicationConfiguration> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/templates/${templateName}/apply`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          applicationName,
          namespace,
        }),
      },
    );

    if (!response.ok) {
      throw new Error(`Failed to apply template: ${response.statusText}`);
    }

    return await response.json();
  }

  async validateConfiguration(config: ApplicationConfiguration): Promise<ConfigurationValidationResult> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations/validate`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(config),
      },
    );

    if (!response.ok) {
      throw new Error(`Failed to validate configuration: ${response.statusText}`);
    }

    return await response.json();
  }

  async previewConfiguration(config: ApplicationConfiguration): Promise<string> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations/preview`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(config),
      },
    );

    if (!response.ok) {
      throw new Error(`Failed to preview configuration: ${response.statusText}`);
    }

    return await response.text();
  }

  async promoteConfiguration(
    name: string,
    namespace: string,
    sourceEnv: string,
    targetEnv: string,
  ): Promise<void> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations/${namespace}/${name}/promote`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          sourceEnvironment: sourceEnv,
          targetEnvironment: targetEnv,
        }),
      },
    );

    if (!response.ok) {
      throw new Error(`Failed to promote configuration: ${response.statusText}`);
    }
  }

  async rollbackConfiguration(
    name: string,
    namespace: string,
    environment: string,
    version: string,
  ): Promise<void> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations/${namespace}/${name}/rollback`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          environment,
          version,
        }),
      },
    );

    if (!response.ok) {
      throw new Error(`Failed to rollback configuration: ${response.statusText}`);
    }
  }

  async getConfigurationHistory(name: string, namespace: string): Promise<any[]> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations/${namespace}/${name}/history`,
    );

    if (!response.ok) {
      throw new Error(`Failed to fetch configuration history: ${response.statusText}`);
    }

    return await response.json();
  }

  async compareConfigurations(
    name: string,
    namespace: string,
    env1: string,
    env2: string,
  ): Promise<any> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/configurations/${namespace}/${name}/compare?env1=${env1}&env2=${env2}`,
    );

    if (!response.ok) {
      throw new Error(`Failed to compare configurations: ${response.statusText}`);
    }

    return await response.json();
  }

  async getApplicationStatus(name: string, namespace: string): Promise<any> {
    const baseUrl = await this.getBaseUrl();
    const response = await this.fetchApi.fetch(
      `${baseUrl}/applications/${namespace}/${name}/status`,
    );

    if (!response.ok) {
      throw new Error(`Failed to fetch application status: ${response.statusText}`);
    }

    return await response.json();
  }
}