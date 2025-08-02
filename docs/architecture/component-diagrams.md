# IDP Platform Component Diagrams

## High-Level Platform Architecture

```mermaid
graph TB
    subgraph "Developer Experience"
        DEV[Developer]
        BACKSTAGE[Backstage Portal]
        TEMPLATES[Software Templates]
    end
    
    subgraph "CI/CD Pipeline"
        GITHUB[GitHub Repository]
        ACTIONS[GitHub Actions]
        ECR[Container Registry]
        ARGOCD[ArgoCD]
    end
    
    subgraph "Platform Abstractions"
        WEBAPP[WebApplication CRD]
        CROSSPLANE[Crossplane Compositions]
        OPERATORS[Platform Operators]
    end
    
    subgraph "Kubernetes Cluster"
        CONTROL[Control Plane]
        NODES[Worker Nodes]
        PODS[Application Pods]
    end
    
    subgraph "Service Mesh"
        ISTIO[Istio Control Plane]
        ENVOY[Envoy Sidecars]
        GATEWAY[Istio Gateway]
    end
    
    subgraph "Security & Secrets"
        ESO[External Secrets Operator]
        CERTMGR[cert-manager]
        VAULT[AWS Secrets Manager]
    end
    
    subgraph "Observability"
        PROMETHEUS[Prometheus]
        GRAFANA[Grafana]
        JAEGER[Jaeger]
        LOKI[Loki]
        FLUENTD[Fluentd]
        ALERT[Alertmanager]
    end
    
    subgraph "Infrastructure"
        AWS[AWS Services]
        LOCALSTACK[LocalStack]
        K8S[Kubernetes]
    end
    
    DEV --> BACKSTAGE
    BACKSTAGE --> TEMPLATES
    TEMPLATES --> GITHUB
    GITHUB --> ACTIONS
    ACTIONS --> ECR
    ECR --> ARGOCD
    ARGOCD --> WEBAPP
    WEBAPP --> CROSSPLANE
    CROSSPLANE --> OPERATORS
    OPERATORS --> PODS
    PODS --> ENVOY
    ENVOY --> ISTIO
    ISTIO --> GATEWAY
    ESO --> VAULT
    CERTMGR --> ISTIO
    PROMETHEUS --> GRAFANA
    JAEGER --> GRAFANA
    LOKI --> GRAFANA
    FLUENTD --> LOKI
    ALERT --> PROMETHEUS
    CROSSPLANE --> AWS
    CROSSPLANE --> LOCALSTACK
```

## Network Flow Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant IG as Istio Gateway
    participant E as Envoy Proxy
    participant A as Application
    participant D as Database
    participant P as Prometheus
    participant J as Jaeger
    
    U->>IG: HTTPS Request
    IG->>E: mTLS Request
    E->>A: HTTP Request
    A->>D: Query Data
    D-->>A: Return Data
    A-->>E: HTTP Response
    E-->>IG: mTLS Response
    IG-->>U: HTTPS Response
    
    E->>P: Metrics
    E->>J: Trace Spans
    A->>P: Application Metrics
    A->>J: Application Spans
```

## Data Flow Architecture

```mermaid
flowchart LR
    subgraph "Data Sources"
        APPS[Applications]
        ISTIO[Istio Mesh]
        K8S[Kubernetes]
        INFRA[Infrastructure]
    end
    
    subgraph "Collection"
        PROMETHEUS[Prometheus]
        FLUENTD[Fluentd]
        JAEGER[Jaeger Collector]
    end
    
    subgraph "Storage"
        PROM_TSDB[Prometheus TSDB]
        LOKI_STORE[Loki Storage]
        JAEGER_STORE[Jaeger Storage]
    end
    
    subgraph "Visualization"
        GRAFANA[Grafana]
        KIALI[Kiali]
        JAEGER_UI[Jaeger UI]
    end
    
    subgraph "Alerting"
        ALERT[Alertmanager]
        WEBHOOK[Webhook Notifications]
    end
    
    APPS --> PROMETHEUS
    ISTIO --> PROMETHEUS
    K8S --> PROMETHEUS
    INFRA --> PROMETHEUS
    
    APPS --> FLUENTD
    ISTIO --> FLUENTD
    K8S --> FLUENTD
    
    APPS --> JAEGER
    ISTIO --> JAEGER
    
    PROMETHEUS --> PROM_TSDB
    FLUENTD --> LOKI_STORE
    JAEGER --> JAEGER_STORE
    
    PROM_TSDB --> GRAFANA
    LOKI_STORE --> GRAFANA
    JAEGER_STORE --> JAEGER_UI
    ISTIO --> KIALI
    
    PROMETHEUS --> ALERT
    ALERT --> WEBHOOK
```

## Security Architecture

```mermaid
graph TB
    subgraph "External Access"
        USER[User]
        INTERNET[Internet]
    end
    
    subgraph "Edge Security"
        WAF[Web Application Firewall]
        LB[Load Balancer]
        DDOS[DDoS Protection]
    end
    
    subgraph "Ingress Layer"
        GATEWAY[Istio Gateway]
        TLS[TLS Termination]
    end
    
    subgraph "Service Mesh Security"
        MTLS[mTLS Enforcement]
        AUTHZ[Authorization Policies]
        RBAC[Service-to-Service RBAC]
    end
    
    subgraph "Application Security"
        PODS[Application Pods]
        PSP[Pod Security Policies]
        SECCTX[Security Context]
    end
    
    subgraph "Data Security"
        ESO[External Secrets Operator]
        VAULT[Secret Store]
        ENCRYPT[Encryption at Rest]
    end
    
    subgraph "Network Security"
        NETPOL[Network Policies]
        FIREWALL[Firewall Rules]
        VPC[VPC Isolation]
    end
    
    USER --> WAF
    INTERNET --> DDOS
    WAF --> LB
    LB --> GATEWAY
    GATEWAY --> TLS
    TLS --> MTLS
    MTLS --> AUTHZ
    AUTHZ --> RBAC
    RBAC --> PODS
    PODS --> PSP
    PSP --> SECCTX
    ESO --> VAULT
    VAULT --> ENCRYPT
    NETPOL --> FIREWALL
    FIREWALL --> VPC
```

## CI/CD Pipeline Flow

```mermaid
flowchart TD
    subgraph "Development"
        DEV[Developer Code]
        BACKSTAGE[Backstage Template]
        REPO[Git Repository]
    end
    
    subgraph "Continuous Integration"
        TRIGGER[Push Trigger]
        BUILD[Build Application]
        TEST[Run Tests]
        SCAN[Security Scan]
        IMAGE[Build Container]
        PUSH[Push to Registry]
    end
    
    subgraph "Continuous Deployment"
        ARGOCD[ArgoCD]
        SYNC[Git Sync]
        DEPLOY[Deploy to K8s]
        HEALTH[Health Check]
        PROMOTE[Environment Promotion]
    end
    
    subgraph "Environments"
        DEV_ENV[Development]
        STAGING[Staging]
        PROD[Production]
    end
    
    subgraph "Monitoring"
        METRICS[Metrics Collection]
        ALERTS[Alert Generation]
        FEEDBACK[Developer Feedback]
    end
    
    DEV --> BACKSTAGE
    BACKSTAGE --> REPO
    REPO --> TRIGGER
    TRIGGER --> BUILD
    BUILD --> TEST
    TEST --> SCAN
    SCAN --> IMAGE
    IMAGE --> PUSH
    PUSH --> ARGOCD
    ARGOCD --> SYNC
    SYNC --> DEPLOY
    DEPLOY --> HEALTH
    HEALTH --> DEV_ENV
    DEV_ENV --> PROMOTE
    PROMOTE --> STAGING
    STAGING --> PROMOTE
    PROMOTE --> PROD
    DEPLOY --> METRICS
    METRICS --> ALERTS
    ALERTS --> FEEDBACK
    FEEDBACK --> DEV
```

## WebApplication CRD Workflow

```mermaid
flowchart TD
    subgraph "Developer Input"
        SPEC[WebApplication Spec]
        CONFIG[Application Config]
    end
    
    subgraph "Platform Processing"
        CONTROLLER[WebApp Controller]
        VALIDATE[Validation]
        GENERATE[Resource Generation]
    end
    
    subgraph "Generated Resources"
        DEPLOYMENT[Deployment]
        SERVICE[Service]
        VS[VirtualService]
        HPA[HorizontalPodAutoscaler]
        SM[ServiceMonitor]
    end
    
    subgraph "Infrastructure Resources"
        XPLANE[Crossplane Claims]
        DB[Database]
        STORAGE[Storage]
        SECRETS[Secrets]
    end
    
    subgraph "Observability Setup"
        MONITORING[Metrics Scraping]
        LOGGING[Log Collection]
        TRACING[Trace Collection]
        DASHBOARDS[Grafana Dashboards]
    end
    
    SPEC --> CONTROLLER
    CONFIG --> CONTROLLER
    CONTROLLER --> VALIDATE
    VALIDATE --> GENERATE
    GENERATE --> DEPLOYMENT
    GENERATE --> SERVICE
    GENERATE --> VS
    GENERATE --> HPA
    GENERATE --> SM
    GENERATE --> XPLANE
    XPLANE --> DB
    XPLANE --> STORAGE
    XPLANE --> SECRETS
    SM --> MONITORING
    DEPLOYMENT --> LOGGING
    SERVICE --> TRACING
    MONITORING --> DASHBOARDS
```

## Multi-Environment Architecture

```mermaid
graph TB
    subgraph "Local Development"
        LOCAL_K8S[Docker Desktop/Kind]
        LOCALSTACK[LocalStack Services]
        LOCAL_ECR[LocalStack ECR]
    end
    
    subgraph "Staging Environment"
        STAGING_K8S[EKS Cluster]
        STAGING_AWS[AWS Services]
        STAGING_ECR[AWS ECR]
    end
    
    subgraph "Production Environment"
        PROD_K8S[EKS Cluster]
        PROD_AWS[AWS Services]
        PROD_ECR[AWS ECR]
    end
    
    subgraph "GitOps Repository"
        GIT[Git Repository]
        MANIFESTS[K8s Manifests]
        CONFIGS[Environment Configs]
    end
    
    subgraph "CI/CD Pipeline"
        GITHUB_ACTIONS[GitHub Actions]
        ARGOCD_LOCAL[ArgoCD Local]
        ARGOCD_STAGING[ArgoCD Staging]
        ARGOCD_PROD[ArgoCD Production]
    end
    
    GIT --> GITHUB_ACTIONS
    GITHUB_ACTIONS --> LOCAL_ECR
    GITHUB_ACTIONS --> STAGING_ECR
    GITHUB_ACTIONS --> PROD_ECR
    
    GIT --> ARGOCD_LOCAL
    GIT --> ARGOCD_STAGING
    GIT --> ARGOCD_PROD
    
    ARGOCD_LOCAL --> LOCAL_K8S
    ARGOCD_STAGING --> STAGING_K8S
    ARGOCD_PROD --> PROD_K8S
    
    LOCAL_K8S --> LOCALSTACK
    STAGING_K8S --> STAGING_AWS
    PROD_K8S --> PROD_AWS
```

## Secrets Management Flow

```mermaid
sequenceDiagram
    participant A as Application
    participant ESO as External Secrets Operator
    participant AWS as AWS Secrets Manager
    participant LS as LocalStack Secrets
    participant K8S as Kubernetes Secret
    
    Note over ESO: Watches SecretStore & ExternalSecret CRDs
    
    ESO->>AWS: Fetch Secret (Production)
    ESO->>LS: Fetch Secret (Local)
    AWS-->>ESO: Return Secret Value
    LS-->>ESO: Return Secret Value
    ESO->>K8S: Create/Update Secret
    K8S-->>A: Mount Secret as Volume/Env
    
    Note over ESO: Automatic Secret Rotation
    ESO->>AWS: Check for Updates
    AWS-->>ESO: Updated Secret
    ESO->>K8S: Update Secret
    K8S->>A: Signal Restart (if configured)
```

## Observability Stack Integration

```mermaid
graph TB
    subgraph "Metrics Pipeline"
        M_SOURCE[Metric Sources]
        PROMETHEUS[Prometheus]
        M_STORAGE[TSDB Storage]
        GRAFANA[Grafana]
        ALERT[Alertmanager]
    end
    
    subgraph "Logging Pipeline"
        L_SOURCE[Log Sources]
        FLUENTD[Fluentd]
        LOKI[Loki]
        L_QUERY[LogQL Queries]
    end
    
    subgraph "Tracing Pipeline"
        T_SOURCE[Trace Sources]
        JAEGER_COL[Jaeger Collector]
        JAEGER_STORE[Jaeger Storage]
        JAEGER_UI[Jaeger UI]
    end
    
    subgraph "Service Mesh Observability"
        ISTIO[Istio]
        KIALI[Kiali]
        ENVOY[Envoy Metrics]
    end
    
    subgraph "Unified Dashboard"
        MONITORING[Monitoring Dashboard]
        CORRELATION[Data Correlation]
    end
    
    M_SOURCE --> PROMETHEUS
    PROMETHEUS --> M_STORAGE
    M_STORAGE --> GRAFANA
    PROMETHEUS --> ALERT
    
    L_SOURCE --> FLUENTD
    FLUENTD --> LOKI
    LOKI --> L_QUERY
    L_QUERY --> GRAFANA
    
    T_SOURCE --> JAEGER_COL
    JAEGER_COL --> JAEGER_STORE
    JAEGER_STORE --> JAEGER_UI
    
    ISTIO --> ENVOY
    ENVOY --> PROMETHEUS
    ISTIO --> KIALI
    
    GRAFANA --> MONITORING
    JAEGER_UI --> MONITORING
    KIALI --> MONITORING
    
    MONITORING --> CORRELATION
```