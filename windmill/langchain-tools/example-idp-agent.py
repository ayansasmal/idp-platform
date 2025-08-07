"""
Example IDP Agent Implementation
Demonstrates how to create an AI agent for IDP platform management using LangChain + Windmill
"""

import os
from typing import List, Optional
from langchain.agents import initialize_agent, AgentType
from langchain.llms import OpenAI
from langchain.chat_models import ChatOpenAI
from langchain.memory import ConversationBufferMemory
from langchain.tools import BaseTool
from langchain.schema import SystemMessage

# Import our IDP platform tools
from idp_platform_tools import create_idp_agent_tools, WindmillConfig


class IDPPlatformAgent:
    """
    AI Agent for IDP Platform Management
    
    This agent provides natural language interface for:
    - Platform bootstrapping and setup
    - Service management (start/stop/restart)
    - Health monitoring and diagnostics
    - Configuration management
    - Troubleshooting and recommendations
    """
    
    def __init__(
        self,
        openai_api_key: Optional[str] = None,
        windmill_url: str = "http://localhost:8000",
        windmill_token: Optional[str] = None,
        model_name: str = "gpt-4",
        temperature: float = 0.1,
        verbose: bool = True
    ):
        """
        Initialize the IDP Platform Agent
        
        Args:
            openai_api_key: OpenAI API key (or set OPENAI_API_KEY env var)
            windmill_url: Windmill server URL
            windmill_token: Windmill authentication token
            model_name: OpenAI model to use
            temperature: Model creativity (0.0 = deterministic, 1.0 = creative)
            verbose: Whether to show detailed execution logs
        """
        
        # Set up OpenAI API key
        if openai_api_key:
            os.environ["OPENAI_API_KEY"] = openai_api_key
        elif not os.getenv("OPENAI_API_KEY"):
            raise ValueError("OpenAI API key must be provided or set as OPENAI_API_KEY env var")
        
        # Initialize LLM
        self.llm = ChatOpenAI(
            model_name=model_name,
            temperature=temperature
        )
        
        # Set up memory for conversation context
        self.memory = ConversationBufferMemory(
            memory_key="chat_history",
            return_messages=True
        )
        
        # Get IDP platform tools
        self.tools = create_idp_agent_tools(
            windmill_url=windmill_url,
            windmill_token=windmill_token,
            workspace="idp"
        )
        
        # Initialize the agent
        self.agent = initialize_agent(
            tools=self.tools,
            llm=self.llm,
            agent=AgentType.CHAT_CONVERSATIONAL_REACT_DESCRIPTION,
            memory=self.memory,
            verbose=verbose,
            system_message=self._get_system_message()
        )
    
    def _get_system_message(self) -> SystemMessage:
        """Get the system message that defines the agent's behavior"""
        
        system_prompt = """
You are an expert IDP (Integrated Developer Platform) assistant. You help users manage and operate a comprehensive Kubernetes-based development platform.

Your capabilities include:
- Setting up complete platform infrastructure (Kubernetes, Istio, ArgoCD, Backstage)
- Managing platform services (start, stop, restart, monitor)
- Running health checks and diagnostics
- Providing recommendations for platform optimization
- Troubleshooting platform issues

Platform Components you manage:
- Kubernetes cluster and core services
- Istio service mesh for networking
- ArgoCD for GitOps-based deployments
- Backstage developer portal
- Monitoring stack (Prometheus, Grafana, Jaeger)
- Authentication (AWS Cognito)
- External services (LocalStack for development)

Guidelines:
1. Always confirm destructive operations before executing
2. Provide clear explanations of what operations will do
3. Use dry_run mode when user wants to preview changes
4. Offer specific recommendations based on health check results
5. Help troubleshoot issues by checking logs and component status
6. Explain technical concepts in accessible terms

When users ask about platform status, always run health checks to provide current information.
When setting up environments, ask about requirements (development vs production).
For complex operations, break them down into clear steps.
"""
        
        return SystemMessage(content=system_prompt)
    
    def chat(self, message: str) -> str:
        """
        Process a user message and return the agent's response
        
        Args:
            message: User's natural language input
            
        Returns:
            Agent's response
        """
        try:
            response = self.agent.run(input=message)
            return response
        except Exception as e:
            return f"I encountered an error: {str(e)}. Please try rephrasing your request or check if the platform services are running."
    
    def reset_conversation(self):
        """Reset the conversation memory"""
        self.memory.clear()
    
    def get_available_commands(self) -> List[str]:
        """Get list of available tool commands"""
        return [tool.name for tool in self.tools]


def create_example_conversations():
    """Example conversations to demonstrate agent capabilities"""
    
    examples = [
        {
            "scenario": "Platform Setup",
            "user": "I need to set up a complete development platform. What do I need to do?",
            "expected_flow": "Agent will ask about requirements and use platform_bootstrap tool"
        },
        {
            "scenario": "Health Check", 
            "user": "Is my platform healthy? Are all services running correctly?",
            "expected_flow": "Agent will use platform_health_check tool for comprehensive diagnostics"
        },
        {
            "scenario": "Service Management",
            "user": "Backstage seems to be down. Can you restart it?",
            "expected_flow": "Agent will use platform_operations tool with restart operation"
        },
        {
            "scenario": "Troubleshooting",
            "user": "My deployments are failing. What could be wrong?",
            "expected_flow": "Agent will run health checks and provide diagnostic recommendations"
        },
        {
            "scenario": "Status Check",
            "user": "Show me the current status of all platform services",
            "expected_flow": "Agent will use platform_operations with status operation"
        }
    ]
    
    return examples


def demo_agent_conversation():
    """
    Demonstration of the IDP agent in action
    """
    
    print("🤖 IDP Platform Agent Demo")
    print("=" * 50)
    
    # Initialize agent (you'll need to set OPENAI_API_KEY)
    try:
        agent = IDPPlatformAgent(
            windmill_url="http://localhost:8000",
            verbose=True
        )
        
        print("✅ IDP Agent initialized successfully!")
        print(f"Available tools: {', '.join(agent.get_available_commands())}")
        print("\nYou can now chat with the agent about platform management.")
        print("Example questions:")
        print("- 'Set up a complete development platform'")
        print("- 'Check the health of all services'")
        print("- 'Start the Backstage service'")
        print("- 'What's the current platform status?'")
        print("\nType 'quit' to exit.\n")
        
        # Interactive chat loop
        while True:
            user_input = input("👤 You: ").strip()
            
            if user_input.lower() in ['quit', 'exit', 'bye']:
                print("👋 Goodbye!")
                break
            
            if not user_input:
                continue
            
            print("🤖 Agent: ", end="")
            response = agent.chat(user_input)
            print(response)
            print()
            
    except ValueError as e:
        print(f"❌ Setup error: {e}")
        print("Please set your OPENAI_API_KEY environment variable")
    except Exception as e:
        print(f"❌ Unexpected error: {e}")


if __name__ == "__main__":
    # Run the demo
    demo_agent_conversation()