# IDP Platform Backstage Application

This is the real Backstage application for the Integrated Developer Platform (IDP). It serves as the central developer portal providing self-service capabilities, software templates, and service catalog.

## 🚀 Production Deployment

This application is deployed as a containerized workload in the IDP platform:

- **Image**: `idp/backstage-app:latest`
- **Registry**: LocalStack ECR (`000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566`)
- **Access**: http://localhost:3000 (via platform automation)
- **Database**: PostgreSQL with persistent storage

## 🏗️ Build Process

The application is built using a multi-stage Docker build:

```bash
# Build Docker image
docker build -f Dockerfile.prebuilt -t idp/backstage-app:latest .

# Push to LocalStack ECR
docker tag idp/backstage-app:latest 000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566/idp/backstage-app:latest
docker push 000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566/idp/backstage-app:latest
```

## 🛠️ Local Development

For development purposes, you can run locally:

```sh
yarn install
yarn start
```

**Note**: The production deployment uses the containerized version deployed via ArgoCD GitOps.
