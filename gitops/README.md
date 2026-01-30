# Circle of Trust - GitOps Repository Setup

This directory contains the GitOps configuration for the Circle of Trust application.

## Critical Setup Instructions

### 1. Create Secrets File

Before deploying, you must create the secrets file:

```bash
cd gitops/base/secrets/
cp .env.example .env
# Edit .env with actual secret values
```

**Important**: Never commit the actual `.env` file to version control. Only `.env.example` should be committed.

### 2. Update GitOps Repository URL

In [Jenkinsfile](../../Jenkinsfile), update the GITOPS_REPO URL:

```groovy
GITOPS_REPO = 'https://github.com/YOUR-ORG/circle-gitops.git'
```

### 3. Update Ingress Hostname

In [gitops/base/ingress.yaml](base/ingress.yaml), update the hostname:

```yaml
spec:
  tls:
    - hosts:
        - YOUR-DOMAIN.com  # Change this
      secretName: circle-tls-cert
  rules:
    - host: YOUR-DOMAIN.com  # Change this
```

### 4. ArgoCD Application

The ArgoCD application configuration is in [gitops/argocd/application.yaml](argocd/application.yaml). Update the repository URL there as well.

## Structure

```
gitops/
├── base/                       # Base Kubernetes manifests
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── backend-deployment.yaml
│   ├── backend-service.yaml
│   ├── frontend-deployment.yaml
│   ├── frontend-service.yaml
│   ├── ollama-statefulset.yaml
│   ├── ollama-service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── pdb.yaml
│   ├── service-monitor.yaml
│   ├── network-policy.yaml
│   ├── db-migration-job.yaml
│   └── secrets/
│       └── .env.example
├── overlays/
│   └── production/            # Production-specific configs
│       └── kustomization.yaml
└── argocd/
    └── application.yaml       # ArgoCD application definition
```

## Deployment

The pipeline automatically updates image tags in this repository and ArgoCD syncs the changes to the cluster.

## Validation

Test kustomize build locally:

```bash
kustomize build overlays/production
```
