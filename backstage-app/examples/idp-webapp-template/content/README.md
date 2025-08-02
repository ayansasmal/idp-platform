# ${{ values.name }}

${{ values.description }}

## Overview

This application was created using the IDP Platform Backstage template and is managed as a WebApplication custom resource in Kubernetes.

## Configuration

- **Name**: ${{ values.name }}
- **Environment**: ${{ values.environment }}
- **Replicas**: ${{ values.replicas }}
- **Image**: ${{ values.image }}
- **Port**: ${{ values.port }}
{%- if values.enableDatabase %}
- **Database**: PostgreSQL (enabled)
{%- endif %}
{%- if values.enableIngress %}
- **Public URL**: https://${{ values.hostname or values.name + '.' + values.environment + '.idp.local' }}
{%- endif %}

## Deployment

This application is deployed using the IDP Platform's WebApplication CRD, which automatically creates:

- Kubernetes Deployment
- Service
- Horizontal Pod Autoscaler
{%- if values.enableIngress %}
- Istio VirtualService for ingress
{%- endif %}
{%- if values.enableDatabase %}
- PostgreSQL database via Crossplane
{%- endif %}

## Monitoring

The application includes:
- Prometheus metrics endpoint on port 9090
- Health checks (liveness and readiness probes)
- Istio service mesh integration

## Development

To modify this application:

1. Update the WebApplication manifest in `webapp-manifest.yaml`
2. Apply changes: `kubectl apply -f webapp-manifest.yaml`
3. Monitor status: `kubectl get webapp ${{ values.name }} -n ${{ values.environment }}`

## Support

For platform support and issues, visit the [IDP Platform repository](https://github.com/your-org/idp-platform/issues).