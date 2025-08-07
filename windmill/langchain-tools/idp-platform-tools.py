"""
LangChain Tools for IDP Platform Integration
Provides AI agents with structured access to IDP platform operations via Windmill flows
"""

import json
import requests
import time
from typing import Any, Dict, List, Optional, Union
from langchain.tools import BaseTool
from langchain.callbacks.manager import CallbackManagerForToolUse
from pydantic import BaseModel, Field


class WindmillConfig(BaseModel):
    """Configuration for Windmill API connection"""
    base_url: str = Field(default="http://localhost:8000", description="Windmill server URL")
    token: Optional[str] = Field(default=None, description="Authentication token")
    workspace: str = Field(default="idp", description="Windmill workspace")
    timeout: int = Field(default=300, description="Request timeout in seconds")


class WindmillClient:
    """Client for interacting with Windmill API"""
    
    def __init__(self, config: WindmillConfig):
        self.config = config
        self.session = requests.Session()
        if config.token:
            self.session.headers.update({"Authorization": f"Bearer {config.token}"})
    
    def run_flow(self, flow_path: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a Windmill flow and return results"""
        url = f"{self.config.base_url}/api/w/{self.config.workspace}/jobs/run/{flow_path}"
        
        try:
            response = self.session.post(
                url,
                json=args,
                timeout=self.config.timeout
            )
            response.raise_for_status()
            
            job_data = response.json()
            job_id = job_data.get("uuid")
            
            if not job_id:
                return {"success": False, "error": "No job ID returned"}
            
            # Poll for completion
            return self._wait_for_completion(job_id)
            
        except requests.RequestException as e:
            return {"success": False, "error": f"Request failed: {str(e)}"}
    
    def _wait_for_completion(self, job_id: str, max_wait: int = 300) -> Dict[str, Any]:
        """Wait for job completion and return results"""
        url = f"{self.config.base_url}/api/w/{self.config.workspace}/jobs_u/completed/{job_id}"
        
        start_time = time.time()
        while time.time() - start_time < max_wait:
            try:
                response = self.session.get(url)
                if response.status_code == 200:
                    job_result = response.json()
                    return {
                        "success": True,
                        "job_id": job_id,
                        "result": job_result.get("result", {}),
                        "logs": job_result.get("logs", [])
                    }
                elif response.status_code == 404:
                    # Job still running
                    time.sleep(5)
                    continue
                else:
                    return {"success": False, "error": f"Job failed with status {response.status_code}"}
                    
            except requests.RequestException as e:
                return {"success": False, "error": f"Error checking job status: {str(e)}"}
        
        return {"success": False, "error": "Job timeout"}


# Initialize Windmill client (can be configured via environment variables)
windmill_client = WindmillClient(WindmillConfig())


class PlatformBootstrapTool(BaseTool):
    """Tool for bootstrapping the complete IDP platform"""
    
    name: str = "platform_bootstrap"
    description: str = """
    Bootstrap the complete IDP platform from scratch. 
    Use this for initial platform setup or disaster recovery.
    
    Parameters:
    - platform_name: Name of the platform (default: "IDP Platform")
    - environment: Target environment (development/staging/production)
    - enable_monitoring: Whether to install monitoring stack
    - enable_auth: Whether to setup authentication
    - skip_backstage: Whether to skip Backstage installation
    - dry_run: Test mode without making actual changes
    
    Example usage: "Set up the complete platform for development"
    """
    
    def _run(
        self,
        platform_name: str = "IDP Platform",
        environment: str = "development",
        enable_monitoring: bool = True,
        enable_auth: bool = True,
        skip_backstage: bool = False,
        dry_run: bool = False,
        run_manager: Optional[CallbackManagerForToolUse] = None,
    ) -> str:
        """Execute the platform bootstrap flow"""
        
        args = {
            "platform_name": platform_name,
            "environment": environment,
            "enable_monitoring": enable_monitoring,
            "enable_auth": enable_auth,
            "skip_backstage": skip_backstage,
            "dry_run": dry_run
        }
        
        result = windmill_client.run_flow("f/idp/bootstrap-platform", args)
        
        if result["success"]:
            flow_result = result["result"]
            if flow_result.get("success", False):
                return f"""
✅ Platform bootstrap completed successfully!

Status: {flow_result.get('results', {}).get('status', 'unknown')}
Duration: {flow_result.get('results', {}).get('duration', 'unknown')}s
Platform URLs: {json.dumps(flow_result.get('platform_urls', {}), indent=2)}

Summary: {flow_result.get('summary', 'No summary available')}
"""
            else:
                failed_steps = flow_result.get('failed_steps', [])
                warnings = flow_result.get('warnings', [])
                return f"""
❌ Platform bootstrap failed!

Failed steps: {', '.join(failed_steps) if failed_steps else 'None'}
Warnings: {', '.join(warnings) if warnings else 'None'}
Error details: {flow_result.get('results', {}).get('error', 'Unknown error')}
"""
        else:
            return f"❌ Failed to execute bootstrap: {result['error']}"


class PlatformOperationsTool(BaseTool):
    """Tool for platform operational tasks"""
    
    name: str = "platform_operations"
    description: str = """
    Perform operational tasks on the IDP platform.
    
    Parameters:
    - operation: Type of operation (start/stop/restart/status/health)
    - services: List of specific services to operate on (optional)
    - comprehensive_health: For health checks, whether to run comprehensive tests
    - dry_run: Test mode without making actual changes
    
    Example usage: 
    - "Start all platform services"
    - "Check the health of the platform"
    - "Restart Backstage service"
    - "Get platform status"
    """
    
    def _run(
        self,
        operation: str = "status",
        services: Optional[List[str]] = None,
        comprehensive_health: bool = True,
        dry_run: bool = False,
        run_manager: Optional[CallbackManagerForToolUse] = None,
    ) -> str:
        """Execute platform operations"""
        
        args = {
            "operation": operation,
            "services": services or [],
            "comprehensive_health": comprehensive_health,
            "dry_run": dry_run
        }
        
        result = windmill_client.run_flow("f/idp/platform-operations", args)
        
        if result["success"]:
            flow_result = result["result"]
            if flow_result.get("success", False):
                operation_result = flow_result.get('results', {})
                services_info = operation_result.get('services', {})
                
                return f"""
✅ Platform {operation} completed successfully!

Status: {operation_result.get('status', 'unknown')}
Duration: {operation_result.get('duration', 'unknown')}s

Services:
{json.dumps(services_info, indent=2)}

Summary: {flow_result.get('summary', 'No summary available')}
"""
            else:
                failed_steps = flow_result.get('failed_steps', [])
                warnings = flow_result.get('warnings', [])
                return f"""
❌ Platform {operation} failed!

Failed steps: {', '.join(failed_steps) if failed_steps else 'None'}
Warnings: {', '.join(warnings) if warnings else 'None'}
"""
        else:
            return f"❌ Failed to execute {operation}: {result['error']}"


class PlatformHealthTool(BaseTool):
    """Specialized tool for platform health monitoring"""
    
    name: str = "platform_health_check"
    description: str = """
    Run comprehensive health checks on the IDP platform.
    Returns detailed information about all platform components.
    
    Parameters:
    - comprehensive: Whether to run detailed checks on all components
    - check_urls: Whether to verify service URL accessibility
    
    Example usage: "Check the overall health of the platform"
    """
    
    def _run(
        self,
        comprehensive: bool = True,
        check_urls: bool = True,
        run_manager: Optional[CallbackManagerForToolUse] = None,
    ) -> str:
        """Execute comprehensive health check"""
        
        args = {
            "operation": "health",
            "comprehensive_health": comprehensive
        }
        
        result = windmill_client.run_flow("f/idp/platform-operations", args)
        
        if result["success"]:
            flow_result = result["result"]
            if flow_result.get("success", False):
                operation_result = flow_result.get('results', {})
                
                # Extract health information from the first health check step
                health_step = None
                for step in operation_result.get('steps', []):
                    if step.get('name') == 'health-check':
                        health_step = step.get('output', {})
                        break
                
                if health_step and health_step.get('success'):
                    health_data = health_step.get('output', {})
                    
                    return f"""
🏥 Platform Health Report

Overall Status: {health_data.get('overall_status', 'unknown').upper()}
Health Score: {health_data.get('health_score', 0)}/100

Component Status:
{self._format_component_status(health_data.get('components', {}))}

Service URLs:
{json.dumps(health_data.get('urls', {}), indent=2)}

Recommendations:
{self._format_recommendations(health_data.get('recommendations', []))}
"""
                else:
                    return "❌ Health check failed to complete successfully"
            else:
                return f"❌ Health check operation failed: {flow_result.get('error', 'Unknown error')}"
        else:
            return f"❌ Failed to execute health check: {result['error']}"
    
    def _format_component_status(self, components: Dict[str, Any]) -> str:
        """Format component status for display"""
        if not components:
            return "No component data available"
        
        lines = []
        for name, info in components.items():
            if isinstance(info, dict):
                status = info.get('status', 'unknown')
                score = info.get('score', 0)
                lines.append(f"  {name}: {status.upper()} (Score: {score}/100)")
            else:
                lines.append(f"  {name}: {str(info)}")
        
        return "\n".join(lines)
    
    def _format_recommendations(self, recommendations: List[str]) -> str:
        """Format recommendations for display"""
        if not recommendations:
            return "No recommendations"
        
        return "\n".join(f"  • {rec}" for rec in recommendations)


class PlatformConfigTool(BaseTool):
    """Tool for platform configuration management"""
    
    name: str = "platform_configuration"
    description: str = """
    Manage platform configuration and settings.
    
    Parameters:
    - action: Configuration action (show/validate/wizard)
    
    Example usage: 
    - "Show current platform configuration"
    - "Validate platform configuration"
    - "Run configuration wizard"
    """
    
    def _run(
        self,
        action: str = "show",
        run_manager: Optional[CallbackManagerForToolUse] = None,
    ) -> str:
        """Execute configuration operations via bridge"""
        
        # This would typically call a configuration-specific Windmill flow
        # For now, return a placeholder
        return f"""
⚙️ Platform Configuration - {action.upper()}

This feature will integrate with the configuration management system.
Available actions: show, validate, wizard

Current action: {action}
Status: Not yet implemented in Windmill flows
"""


# Export all tools for easy import
idp_platform_tools = [
    PlatformBootstrapTool(),
    PlatformOperationsTool(), 
    PlatformHealthTool(),
    PlatformConfigTool()
]


def get_idp_tools(windmill_config: Optional[WindmillConfig] = None) -> List[BaseTool]:
    """
    Get all IDP platform tools with optional custom Windmill configuration
    
    Args:
        windmill_config: Optional custom Windmill configuration
    
    Returns:
        List of configured IDP tools
    """
    if windmill_config:
        global windmill_client
        windmill_client = WindmillClient(windmill_config)
    
    return idp_platform_tools


def create_idp_agent_tools(
    windmill_url: str = "http://localhost:8000",
    windmill_token: Optional[str] = None,
    workspace: str = "idp"
) -> List[BaseTool]:
    """
    Convenience function to create IDP tools with custom configuration
    
    Args:
        windmill_url: Windmill server URL
        windmill_token: Authentication token
        workspace: Windmill workspace name
    
    Returns:
        List of configured IDP tools
    """
    config = WindmillConfig(
        base_url=windmill_url,
        token=windmill_token,
        workspace=workspace
    )
    
    return get_idp_tools(config)


if __name__ == "__main__":
    # Example usage
    tools = get_idp_tools()
    
    print("Available IDP Platform Tools:")
    for tool in tools:
        print(f"- {tool.name}: {tool.description}")