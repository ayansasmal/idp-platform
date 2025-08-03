#!/usr/bin/env python3
"""
Configuration Manager Backend Service for IDP Platform

This service provides REST APIs for managing application configurations
through the Backstage Configuration Manager plugin.
"""

import asyncio
import json
import logging
import os
import yaml
from datetime import datetime
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
from pathlib import Path

from fastapi import FastAPI, HTTPException, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import kubernetes
from kubernetes import client, config as k8s_config
import git
import jinja2

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Kubernetes client
try:
    k8s_config.load_incluster_config()
except:
    k8s_config.load_kube_config()

k8s_client = client.ApiClient()
apps_v1 = client.AppsV1Api()
core_v1 = client.CoreV1Api()
custom_objects_api = client.CustomObjectsApi()

app = FastAPI(
    title="Configuration Manager API",
    description="Backend service for managing application configurations",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Pydantic Models
class ResourceRequirements(BaseModel):
    cpu: str = Field(..., description="CPU requirement (e.g., '100m', '1')")
    memory: str = Field(..., description="Memory requirement (e.g., '128Mi', '1Gi')")

class AutoScalingConfig(BaseModel):
    enabled: bool = False
    minReplicas: int = 1
    maxReplicas: int = 10
    targetCPUUtilization: int = 70
    targetMemoryUtilization: Optional[int] = None

class IngressConfig(BaseModel):
    enabled: bool = False
    host: Optional[str] = None
    path: str = "/"
    tls: bool = False
    annotations: Dict[str, str] = Field(default_factory=dict)

class DatabaseConfig(BaseModel):
    type: str = Field(..., description="Database type: postgresql, mysql, redis, mongodb")
    size: str = Field(..., description="Size: small, medium, large")
    storage: str = "10Gi"
    version: Optional[str] = None

class CacheConfig(BaseModel):
    type: str = Field(..., description="Cache type: redis, memcached")
    size: str = Field(..., description="Size: small, medium, large")
    nodes: int = 1

class EnvironmentConfig(BaseModel):
    replicas: int = 1
    resources: Dict[str, ResourceRequirements]
    environment: Dict[str, str] = Field(default_factory=dict)
    secrets: Dict[str, str] = Field(default_factory=dict)
    scaling: Optional[AutoScalingConfig] = None
    ingress: Optional[IngressConfig] = None
    database: Optional[DatabaseConfig] = None
    cache: Optional[CacheConfig] = None

class GlobalConfig(BaseModel):
    monitoring: Dict[str, bool] = Field(default_factory=lambda: {"enabled": True, "alerts": True})
    security: Dict[str, Any] = Field(default_factory=lambda: {"networkPolicies": True, "podSecurityPolicy": "restricted"})
    backup: Dict[str, str] = Field(default_factory=lambda: {"enabled": "true", "schedule": "0 2 * * *", "retention": "30d"})

class ApplicationConfiguration(BaseModel):
    apiVersion: str = "platform.idp/v1alpha1"
    kind: str = "ApplicationConfiguration"
    metadata: Dict[str, Any]
    spec: Dict[str, Any]

class ConfigurationTemplate(BaseModel):
    name: str
    description: str
    type: str = Field(..., description="Template type: web-app, api-service, worker, cron-job")
    configuration: Dict[str, Any]

class ValidationResult(BaseModel):
    valid: bool
    errors: List[str] = Field(default_factory=list)
    warnings: List[str] = Field(default_factory=list)

class ConfigurationManager:
    """Core configuration management logic"""
    
    def __init__(self):
        self.templates_path = Path("/app/templates")
        self.configurations_path = Path("/app/configurations")
        self.git_repo = os.getenv("GIT_REPO_URL")
        self.jinja_env = jinja2.Environment(
            loader=jinja2.FileSystemLoader(str(self.templates_path))
        )
        
    async def list_configurations(self, namespace: Optional[str] = None) -> List[ApplicationConfiguration]:
        """List all configurations or configurations in a specific namespace"""
        try:
            if namespace:
                # Get configurations from specific namespace
                configs = custom_objects_api.list_namespaced_custom_object(
                    group="platform.idp",
                    version="v1alpha1",
                    namespace=namespace,
                    plural="applicationconfigurations"
                )
            else:
                # Get configurations from all namespaces
                configs = custom_objects_api.list_cluster_custom_object(
                    group="platform.idp",
                    version="v1alpha1",
                    plural="applicationconfigurations"
                )
            
            return [ApplicationConfiguration(**item) for item in configs.get("items", [])]
        except kubernetes.client.exceptions.ApiException as e:
            logger.error(f"Failed to list configurations: {e}")
            return []
    
    async def get_configuration(self, name: str, namespace: str) -> Optional[ApplicationConfiguration]:
        """Get a specific configuration"""
        try:
            config = custom_objects_api.get_namespaced_custom_object(
                group="platform.idp",
                version="v1alpha1",
                namespace=namespace,
                plural="applicationconfigurations",
                name=name
            )
            return ApplicationConfiguration(**config)
        except kubernetes.client.exceptions.ApiException as e:
            if e.status == 404:
                return None
            logger.error(f"Failed to get configuration {name}: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to get configuration: {e}")
    
    async def create_configuration(self, config: ApplicationConfiguration) -> ApplicationConfiguration:
        """Create a new configuration"""
        try:
            # Add creation timestamp
            config.metadata.setdefault("annotations", {})
            config.metadata["annotations"]["created"] = datetime.utcnow().isoformat()
            config.metadata["annotations"]["lastModified"] = datetime.utcnow().isoformat()
            
            result = custom_objects_api.create_namespaced_custom_object(
                group="platform.idp",
                version="v1alpha1",
                namespace=config.metadata["namespace"],
                plural="applicationconfigurations",
                body=config.dict()
            )
            
            # Trigger GitOps sync if configured
            await self._sync_to_git(config)
            
            return ApplicationConfiguration(**result)
        except kubernetes.client.exceptions.ApiException as e:
            logger.error(f"Failed to create configuration: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to create configuration: {e}")
    
    async def update_configuration(self, config: ApplicationConfiguration) -> ApplicationConfiguration:
        """Update an existing configuration"""
        try:
            # Update modification timestamp
            config.metadata.setdefault("annotations", {})
            config.metadata["annotations"]["lastModified"] = datetime.utcnow().isoformat()
            
            result = custom_objects_api.patch_namespaced_custom_object(
                group="platform.idp",
                version="v1alpha1",
                namespace=config.metadata["namespace"],
                plural="applicationconfigurations",
                name=config.metadata["name"],
                body=config.dict()
            )
            
            # Trigger GitOps sync if configured
            await self._sync_to_git(config)
            
            return ApplicationConfiguration(**result)
        except kubernetes.client.exceptions.ApiException as e:
            logger.error(f"Failed to update configuration: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to update configuration: {e}")
    
    async def delete_configuration(self, name: str, namespace: str) -> None:
        """Delete a configuration"""
        try:
            custom_objects_api.delete_namespaced_custom_object(
                group="platform.idp",
                version="v1alpha1",
                namespace=namespace,
                plural="applicationconfigurations",
                name=name
            )
            
            # Remove from Git if configured
            await self._remove_from_git(name, namespace)
            
        except kubernetes.client.exceptions.ApiException as e:
            if e.status != 404:
                logger.error(f"Failed to delete configuration {name}: {e}")
                raise HTTPException(status_code=500, detail=f"Failed to delete configuration: {e}")
    
    async def validate_configuration(self, config: ApplicationConfiguration) -> ValidationResult:
        """Validate a configuration"""
        errors = []
        warnings = []
        
        # Basic validation
        if not config.metadata.get("name"):
            errors.append("Configuration name is required")
        
        if not config.metadata.get("namespace"):
            errors.append("Namespace is required")
        
        if not config.spec.get("application"):
            errors.append("Application name is required")
        
        # Environment validation
        environments = config.spec.get("environments", {})
        if not environments:
            warnings.append("No environments configured")
        
        for env_name, env_config in environments.items():
            if not isinstance(env_config.get("replicas"), int) or env_config.get("replicas", 0) <= 0:
                errors.append(f"Invalid replica count for environment {env_name}")
            
            resources = env_config.get("resources", {})
            if not resources.get("requests") or not resources.get("limits"):
                warnings.append(f"Resource requests/limits not fully specified for environment {env_name}")
        
        return ValidationResult(valid=len(errors) == 0, errors=errors, warnings=warnings)
    
    async def preview_configuration(self, config: ApplicationConfiguration) -> str:
        """Generate YAML preview of the configuration"""
        try:
            # Generate the actual Kubernetes manifests that would be created
            manifests = await self._generate_manifests(config)
            
            # Convert to YAML
            yaml_docs = []
            for manifest in manifests:
                yaml_docs.append(yaml.dump(manifest, default_flow_style=False))
            
            return "\n---\n".join(yaml_docs)
        except Exception as e:
            logger.error(f"Failed to generate preview: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to generate preview: {e}")
    
    async def get_templates(self) -> List[ConfigurationTemplate]:
        """Get available configuration templates"""
        templates = []
        
        # Built-in templates
        builtin_templates = [
            ConfigurationTemplate(
                name="web-application",
                description="Standard web application with load balancer",
                type="web-app",
                configuration={
                    "spec": {
                        "environments": {
                            "development": {
                                "replicas": 1,
                                "resources": {
                                    "requests": {"cpu": "100m", "memory": "128Mi"},
                                    "limits": {"cpu": "500m", "memory": "512Mi"}
                                }
                            },
                            "production": {
                                "replicas": 3,
                                "resources": {
                                    "requests": {"cpu": "500m", "memory": "512Mi"},
                                    "limits": {"cpu": "1000m", "memory": "1Gi"}
                                }
                            }
                        }
                    }
                }
            ),
            ConfigurationTemplate(
                name="api-service",
                description="REST API service with database",
                type="api-service",
                configuration={
                    "spec": {
                        "environments": {
                            "development": {
                                "replicas": 1,
                                "resources": {
                                    "requests": {"cpu": "200m", "memory": "256Mi"},
                                    "limits": {"cpu": "500m", "memory": "512Mi"}
                                },
                                "database": {
                                    "type": "postgresql",
                                    "size": "small"
                                }
                            },
                            "production": {
                                "replicas": 3,
                                "resources": {
                                    "requests": {"cpu": "500m", "memory": "512Mi"},
                                    "limits": {"cpu": "1000m", "memory": "1Gi"}
                                },
                                "database": {
                                    "type": "postgresql",
                                    "size": "large"
                                }
                            }
                        }
                    }
                }
            )
        ]
        
        templates.extend(builtin_templates)
        
        # Load custom templates from filesystem
        if self.templates_path.exists():
            for template_file in self.templates_path.glob("*.yaml"):
                try:
                    with open(template_file, 'r') as f:
                        template_data = yaml.safe_load(f)
                    templates.append(ConfigurationTemplate(**template_data))
                except Exception as e:
                    logger.warning(f"Failed to load template {template_file}: {e}")
        
        return templates
    
    async def apply_template(self, template_name: str, app_name: str, namespace: str) -> ApplicationConfiguration:
        """Apply a template to create a new configuration"""
        templates = await self.get_templates()
        template = next((t for t in templates if t.name == template_name), None)
        
        if not template:
            raise HTTPException(status_code=404, detail=f"Template {template_name} not found")
        
        # Create configuration from template
        config_data = {
            "apiVersion": "platform.idp/v1alpha1",
            "kind": "ApplicationConfiguration",
            "metadata": {
                "name": f"{app_name}-config",
                "namespace": namespace,
                "labels": {
                    "app": app_name,
                    "template": template_name
                }
            },
            "spec": {
                "application": app_name,
                **template.configuration.get("spec", {})
            }
        }
        
        return ApplicationConfiguration(**config_data)
    
    async def _generate_manifests(self, config: ApplicationConfiguration) -> List[Dict[str, Any]]:
        """Generate Kubernetes manifests from configuration"""
        manifests = []
        
        # Generate WebApplication CRD
        web_app_manifest = {
            "apiVersion": "platform.idp/v1alpha1",
            "kind": "WebApplication",
            "metadata": {
                "name": config.spec["application"],
                "namespace": config.metadata["namespace"]
            },
            "spec": {
                "environments": config.spec.get("environments", {})
            }
        }
        manifests.append(web_app_manifest)
        
        # Generate additional manifests based on configuration
        for env_name, env_config in config.spec.get("environments", {}).items():
            # Database manifests
            if env_config.get("database"):
                db_config = env_config["database"]
                db_manifest = {
                    "apiVersion": "platform.idp/v1alpha1",
                    "kind": "DatabaseInstance",
                    "metadata": {
                        "name": f"{config.spec['application']}-{env_name}-db",
                        "namespace": config.metadata["namespace"]
                    },
                    "spec": {
                        "type": db_config["type"],
                        "size": db_config["size"],
                        "environment": env_name
                    }
                }
                manifests.append(db_manifest)
            
            # Cache manifests
            if env_config.get("cache"):
                cache_config = env_config["cache"]
                cache_manifest = {
                    "apiVersion": "platform.idp/v1alpha1",
                    "kind": "CacheInstance",
                    "metadata": {
                        "name": f"{config.spec['application']}-{env_name}-cache",
                        "namespace": config.metadata["namespace"]
                    },
                    "spec": {
                        "type": cache_config["type"],
                        "size": cache_config["size"],
                        "nodes": cache_config.get("nodes", 1),
                        "environment": env_name
                    }
                }
                manifests.append(cache_manifest)
        
        return manifests
    
    async def _sync_to_git(self, config: ApplicationConfiguration) -> None:
        """Sync configuration to Git repository"""
        if not self.git_repo:
            return
        
        try:
            # Implementation would sync to GitOps repository
            logger.info(f"Syncing configuration {config.metadata['name']} to Git")
        except Exception as e:
            logger.error(f"Failed to sync to Git: {e}")
    
    async def _remove_from_git(self, name: str, namespace: str) -> None:
        """Remove configuration from Git repository"""
        if not self.git_repo:
            return
        
        try:
            # Implementation would remove from GitOps repository
            logger.info(f"Removing configuration {name} from Git")
        except Exception as e:
            logger.error(f"Failed to remove from Git: {e}")

# Initialize configuration manager
config_manager = ConfigurationManager()

# API Dependencies
async def get_config_manager() -> ConfigurationManager:
    return config_manager

# API Routes
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

@app.get("/configurations", response_model=List[ApplicationConfiguration])
async def list_configurations(
    namespace: Optional[str] = None,
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """List all configurations"""
    return await manager.list_configurations(namespace)

@app.get("/configurations/{namespace}", response_model=List[ApplicationConfiguration])
async def list_configurations_in_namespace(
    namespace: str,
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """List configurations in a specific namespace"""
    return await manager.list_configurations(namespace)

@app.get("/configurations/{namespace}/{name}", response_model=ApplicationConfiguration)
async def get_configuration(
    name: str,
    namespace: str,
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """Get a specific configuration"""
    config = await manager.get_configuration(name, namespace)
    if not config:
        raise HTTPException(status_code=404, detail="Configuration not found")
    return config

@app.post("/configurations", response_model=ApplicationConfiguration)
async def create_configuration(
    config: ApplicationConfiguration,
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """Create a new configuration"""
    return await manager.create_configuration(config)

@app.put("/configurations/{namespace}/{name}", response_model=ApplicationConfiguration)
async def update_configuration(
    name: str,
    namespace: str,
    config: ApplicationConfiguration,
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """Update an existing configuration"""
    # Ensure the name and namespace match
    config.metadata["name"] = name
    config.metadata["namespace"] = namespace
    return await manager.update_configuration(config)

@app.delete("/configurations/{namespace}/{name}")
async def delete_configuration(
    name: str,
    namespace: str,
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """Delete a configuration"""
    await manager.delete_configuration(name, namespace)
    return {"message": "Configuration deleted successfully"}

@app.post("/configurations/validate", response_model=ValidationResult)
async def validate_configuration(
    config: ApplicationConfiguration,
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """Validate a configuration"""
    return await manager.validate_configuration(config)

@app.post("/configurations/preview")
async def preview_configuration(
    config: ApplicationConfiguration,
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """Generate YAML preview of configuration"""
    yaml_content = await manager.preview_configuration(config)
    return {"preview": yaml_content}

@app.get("/templates", response_model=List[ConfigurationTemplate])
async def get_templates(
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """Get available configuration templates"""
    return await manager.get_templates()

@app.post("/templates/{template_name}/apply", response_model=ApplicationConfiguration)
async def apply_template(
    template_name: str,
    application_name: str,
    namespace: str,
    manager: ConfigurationManager = Depends(get_config_manager)
):
    """Apply a template to create a new configuration"""
    return await manager.apply_template(template_name, application_name, namespace)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)