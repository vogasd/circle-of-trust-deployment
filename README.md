# Circle of Trust - Azure Kubernetes Service (AKS) CI/CD Pipeline

[![Pipeline Status](https://img.shields.io/badge/pipeline-ready-brightgreen)]()
[![Security](https://img.shields.io/badge/security-hardened-blue)]()
[![GitOps](https://img.shields.io/badge/gitops-argocd-orange)]()

## Overview

Enterprise-grade CI/CD pipeline for deploying the Circle of Trust multi-LLM application to Azure Kubernetes Service (AKS). This implementation provides a complete continuous integration and continuous deployment solution with security scanning, testing, monitoring, and GitOps-based deployment.

### Architecture

This implementation deploys the Circle of Trust multi-LLM application to Azure Kubernetes Service (AKS) following the architecture detailed in [AKS-DEPLOYMENT-STRATEGY.md](docs/AKS-DEPLOYMENT-STRATEGY.md). The solution demonstrates production-ready DevOps practices including GitOps, comprehensive security scanning, automated testing, and infrastructure as code.

**Key Features:**

✅ **Build, Test & Deploy Stages**
- Jenkins pipeline ([Jenkinsfile](Jenkinsfile)) with 16 stages
- Parallel execution for optimal performance
- Dynamic versioning and artifact tagging

✅ **Pre-Deployment Testing**
- Unit tests (backend Python/pytest, frontend Node.js/Jest)
- Integration tests with Docker Compose environment
- Code quality enforcement via SonarQube quality gates
- Linting (flake8, ESLint, pylint)

✅ **Security & Vulnerability Scanning**
- SAST: SonarQube code analysis with security hotspots
- SCA: Dependency scanning (Safety for Python, npm audit for Node.js)
- Container scanning: Trivy with CRITICAL severity enforcement
- Secret scanning: Gitleaks integration

✅ **Monitoring, Logging & Audit**
- Prometheus metrics collection with ServiceMonitors
- Grafana dashboards for visualization
- Fluent Bit log aggregation
- Audit logging for all deployments
- Alert rules for critical metrics

✅ **Policy Enforcement**
- OPA (Open Policy Agent) for Kubernetes policy validation
- Polaris security auditing
- Network policies with deny-all baseline
- Security context enforcement

✅ **Automated Deployment & Rollback**
- GitOps workflow via ArgoCD
- Automated rollback pipeline ([Jenkinsfile.rollback](Jenkinsfile.rollback))
- Health checks and smoke tests post-deployment
- Kubernetes rolling updates with PodDisruptionBudgets

✅ **Infrastructure as Code**
- Complete Kubernetes manifests ([gitops/](gitops/))
- Kustomize for environment-specific configurations
- Declarative, drift-free deployments
- Version-controlled infrastructure

## Repository Structure

```
circle-deployment/
├── Jenkinsfile                     # Main CI/CD pipeline
├── Jenkinsfile.rollback            # Rollback pipeline
├── docker-compose.test.yml         # Integration test environment
├── sonar-project.properties        # SonarQube configuration
├── pytest.ini                      # Pytest configuration
├── setup-tests.sh/bat              # Test environment setup scripts
├── gitops/                         # Kubernetes manifests & GitOps config
│   ├── base/                       # Base Kubernetes resources
│   │   ├── namespace.yaml
│   │   ├── backend-deployment.yaml
│   │   ├── frontend-deployment.yaml
│   │   ├── ollama-statefulset.yaml
│   │   ├── *-service.yaml
│   │   ├── ingress.yaml
│   │   ├── hpa.yaml
│   │   ├── pdb.yaml
│   │   ├── network-policy.yaml
│   │   ├── db-migration-job.yaml
│   │   └── kustomization.yaml
│   ├── overlays/production/        # Production-specific configs
│   ├── argocd/                     # ArgoCD application definition
│   └── README.md
├── monitoring/                     # Observability configuration
│   ├── service-monitor.yaml        # Prometheus ServiceMonitors
│   ├── grafana-dashboard.yaml      # Grafana dashboards
│   └── fluent-bit.yaml             # Log aggregation
├── policies/                       # Security & compliance policies
│   └── kubernetes-policies.rego    # OPA policies
├── tests/                          # Test suites
│   ├── smoke/                      # Post-deployment smoke tests
│   ├── integration/                # Integration tests
│   ├── performance/                # k6 performance tests
│   ├── requirements.txt
│   └── README.md
├── PIPELINE.md                     # Requirements specification
├── docs/                            # Architecture documentation
│   ├── AKS-DEPLOYMENT-STRATEGY.md  # Complete architecture design
│   └── MESSAGING-PLATFORM-INTEGRATION.md
└── tests/                          # Test suites
    ├── smoke/                      # Post-deployment smoke tests
    ├── integration/                # Integration tests
    ├── performance/                # k6 performance tests
    └── README.md
```

## Quick Start

### Understanding the Solution

**📋 Start Here:**
1. Review [docs/AKS-DEPLOYMENT-STRATEGY.md](docs/AKS-DEPLOYMENT-STRATEGY.md) - Architecture decisions and rationale
2. Examine [Jenkinsfile](Jenkinsfile) - The complete CI/CD pipeline implementation
3. Browse [gitops/](gitops/) - Kubernetes manifests and GitOps configuration

**🔍 Key Areas to Evaluate:**
- **Pipeline Design:** [Jenkinsfile](Jenkinsfile) - 16 stages with parallel execution
- **Security Integration:** Stages 4, 7, 14 - SAST/SCA/Container scanning
- **Testing Strategy:** [tests/](tests/) - Unit, integration, smoke, performance tests
- **GitOps Implementation:** [gitops/](gitops/) - Kustomize manifests + ArgoCD config
- **Monitoring Setup:** [monitoring/](monitoring/) - Prometheus, Grafana, Fluent Bit
- **Rollback Capability:** [Jenkinsfile.rollback](Jenkinsfile.rollback) - Automated recovery

### Running Tests Locally

The testing infrastructure can be validated without a full deployment:

```bash
# Setup test environment
./setup-tests.sh    # Linux/Mac
setup-tests.bat     # Windows

# Run smoke tests (demonstrates test framework)
cd tests/smoke
pytest test_smoke.py -v

# Validate Kubernetes manifests
cd gitops/overlays/production
kustomize build . | kubectl apply --dry-run=client -f -

# Check policy compliance
kustomize build gitops/overlays/production | conftest test --policy policies/ -
```

### Prerequisites for Full Pipeline Execution

If deploying the complete pipeline to a live environment:

```bash
# Required tools (auto-validated by pipeline in Stage 2)
✓ Jenkins (2.400+)
✓ Azure CLI
✓ kubectl & kustomize
✓ Docker
✓ ArgoCD CLI
✓ Python 3.11+ & Node.js 18+
✓ Trivy, SonarQube Scanner
✓ Conftest, Polaris
```

**Azure Resources Required:**
- AKS cluster (per [AKS-DEPLOYMENT-STRATEGY.md](docs/AKS-DEPLOYMENT-STRATEGY.md))
- Azure Container Registry
- Azure Key Vault (for secrets)
- Azure Log Analytics (optional, for logging)

**Jenkins Configuration:**

Credentials required (configured in Jenkins):
```groovy
- azure-subscription-id (Secret text)
- azure-acr-credentials (Username/Password)
- azure-service-principal (Service Principal)
- github-credentials (Username/Password for GitOps repo)
- argocd-auth-token (Secret text)
- SonarQube (Server connection)
```

Environment variables to update in [Jenkinsfile](Jenkinsfile):
```groovy
ACR_NAME = 'your-acr-name'
AKS_CLUSTER_NAME = 'your-aks-cluster'
AKS_RESOURCE_GROUP = 'your-resource-group'
GITOPS_REPO = 'https://github.com/your-org/your-gitops-repo.git'
ARGOCD_SERVER = 'your-argocd-server'
```

## Architecture

### Pipeline Components

1. **[Jenkinsfile](Jenkinsfile)** - Main CI/CD Pipeline
   - Tooling validation
   - Build, test, and deploy stages
   - Security scanning (SAST/SCA/container)
   - GitOps-based deployment via ArgoCD
   - Post-deployment verification
   - Logging and audit setup

2. **[Jenkinsfile.rollback](Jenkinsfile.rollback)** - Rollback Pipeline
   - Automated rollback capability
   - State backup before rollback
   - Selective service rollback
   - Verification and smoke tests
   - Audit logging

3. **GitOps Configuration** ([gitops/](gitops/))
   - Kustomize-based Kubernetes manifests
   - Production overlays
   - ArgoCD application definitions
   - Network policies
   - Database migration jobs

4. **Observability Stack** ([monitoring/](monitoring/))
   - Prometheus ServiceMonitors
   - Grafana dashboards
   - Fluent Bit log aggregation
   - Alert rules

5. **Security Policies** ([policies/](policies/))
   - OPA policy enforcement
   - Security best practices validation

## Pipeline Stages

### Stage 1: Checkout & Initialize
- Clone source repository
- Extract Git metadata (commit hash, author, message)
- Set dynamic variables (IMAGE_TAG, GIT_COMMIT_SHORT)
- Send Slack notification

### Stage 2: Validate Tooling ⚙️
**New: Production Readiness Check**
- Validates all required tools are installed
- Checks: az, kubectl, docker, kustomize, trivy, sonar-scanner, conftest, polaris, argocd, python3, pytest, npm
- **Fails fast** if tooling missing

### Stage 3: Pre-Build Tests 🧪
**Parallel Execution:**
- **Backend Unit Tests**
  - Creates isolated venv
  - Installs dependencies quietly
  - Runs pytest with coverage (XML + HTML)
  - Publishes JUnit results
- **Frontend Unit Tests**
  - npm ci for clean install
  - Runs Jest with coverage
  - Publishes HTML coverage report
- **Linting**
  - Backend: flake8, black, pylint
  - Frontend: ESLint

### Stage 4: SAST Security Scanning 🔒
**Parallel Execution:**
- **SonarQube Analysis**
  - Code quality metrics
  - Security hotspots
  - Technical debt
- **Dependency Check** (Strict Enforcement)
  - Python: Safety (fails on vulnerabilities)
  - Node.js: npm audit --audit-level=critical
- **Secret Scanning**
  - Gitleaks (fails on exposed secrets)

### Stage 5: Quality Gate ✋
- Wait for SonarQube quality gate (5min timeout)
- **Pipeline fails** if quality standards not met

### Stage 6: Build Container Images 🐳
**Parallel Execution:**
- Backend API image (with build args)
- Frontend web image
- Ollama GPU-enabled image
- All tagged with: `{BUILD_NUMBER}-{GIT_COMMIT_SHORT}` + `latest`

### Stage 7: Container Security Scanning 🛡️
**Parallel Execution with Strict Enforcement:**
- Trivy scans all images
- **Severity: CRITICAL only** (fails on critical findings)
- Generates JSON reports
- Archives scan results

### Stage 8: Integration Tests 🔗
- Starts docker-compose test environment
- Waits for service readiness (30s)
- Runs integration tests in backend container
- Extracts results from container
- Cleanup with `docker-compose down -v`

### Stage 9: Push to Registry 📦
- Authenticates to Azure Container Registry
- Pushes all images with version tags
- Pushes latest tags
- Secure logout

### Stage 10: Update GitOps Repository 📝
- Clones GitOps repository
- Updates Kustomize image references
- Commits changes with version info
- Pushes to GitOps repo (triggers ArgoCD)

### Stage 11: Deploy to AKS (GitOps) 🚀
**Updated: True GitOps Flow**
- Triggers ArgoCD sync (not direct kubectl)
- Waits for ArgoCD health check
- Timeout: 10 minutes

### Stage 12: Configure Cluster Access 🔑
- Authenticates to Azure
- Gets AKS credentials
- Enables kubectl for verification stages

### Stage 13: Post-Deployment Tests ✅
**Parallel Execution:**
- **Health Checks**
  - In-cluster curl checks
  - Uses ClusterIP service DNS
  - Validates /health and /ready endpoints
- **Smoke Tests** (Enhanced)
  - Creates dedicated test-venv
  - Installs test dependencies
  - Sets BASE_URL dynamically
  - Runs 9 smoke test cases
  - Verbose output for debugging
- **Performance Tests**
  - k6 load testing via Docker
  - Basic performance validation

### Stage 14: Policy Enforcement 📋
**Strict Validation:**
- Builds manifests with Kustomize
- OPA policy checks (fails on violations)
- Polaris security audit (fails on errors)
- Archives policy reports

### Stage 15: Monitoring Setup 📊
- Deploys Prometheus ServiceMonitors
- Creates Grafana dashboards
- Archives monitoring configs

### Stage 16: Logging & Audit Setup 📝
**New: Complete Observability**
- Deploys Fluent Bit DaemonSet
- Configures AKS diagnostics to Log Analytics (optional)
- Sets up audit logging
- Archives audit trails

### 14. Monitoring Setup
- Deploy ServiceMonitors
- Create Grafana dashboards
- Set up Prometheus alerts

## GitOps Workflow

### Declarative Configuration

The pipeline follows a GitOps approach using Kustomize and ArgoCD:

```
gitops/
├── base/                       # Base Kubernetes manifests
│   ├── kustomization.yaml
│   ├── backend-deployment.yaml
│   ├── frontend-deployment.yaml
│   └── ollama-statefulset.yaml
├── overlays/
│   └── production/             # Production-specific configs
│       ├── kustomization.yaml
│       └── patches/
└── argocd/
    └── application.yaml        # ArgoCD application definition
```

### Deployment Flow

1. CI pipeline builds and tests code
2. Images pushed to Azure Container Registry
3. GitOps repo updated with new image tags
4. ArgoCD detects changes and syncs to cluster
5. Kubernetes performs rolling update
6. Pipeline verifies deployment health

## Testing Strategy

Comprehensive testing at all stages - see [TEST-INTEGRATION-VALIDATION.md](TEST-INTEGRATION-VALIDATION.md) for details.

### Test Suites

1. **Unit Tests**
   - Backend: pytest with 80%+ coverage target
   - Frontend: Jest/Vitest
   - Location: `backend/tests/unit/`, `frontend/tests/`
   - Execution: Pre-build stage (parallel)

2. **Integration Tests**
   - Location: [tests/integration/](tests/integration/)
   - Environment: docker-compose test stack
   - Tests: Backend ↔ Database, Backend ↔ Ollama
   - Execution: Dedicated integration stage

3. **Smoke Tests** ✨
   - Location: [tests/smoke/test_smoke.py](tests/smoke/test_smoke.py)
   - 9 test cases:
     - Health/Ready endpoints
     - API version
     - Metrics endpoint
     - LLM interaction
     - Database connectivity
     - Response time (<200ms)
     - Concurrent requests
     - SSL validation (production)
   - Execution: Post-deployment
   - BASE_URL: Set dynamically per deployment

4. **Performance Tests**
   - Location: [tests/performance/basic-load-test.js](tests/performance/basic-load-test.js)
   - Tool: k6
   - Metrics: Request rate, latency percentiles, error rate
   - Execution: Post-deployment

### Test Setup

```bash
# Quick setup
./setup-tests.sh    # Linux/Mac
setup-tests.bat     # Windows

# Manual setup
python3 -m venv test-venv
source test-venv/bin/activate  # or test-venv\Scripts\activate.bat
pip install -r tests/requirements.txt

# Run tests
pytest tests/smoke/ -v
```

See [tests/README.md](tests/README.md) for complete testing guide.

## Security Scanning

### SAST (Static Application Security Testing)
- **SonarQube**: Code quality, security hotspots, technical debt
- **Gitleaks**: Exposed secrets detection (fails on findings)
- **Linting**: Code style and common errors

### SCA (Software Composition Analysis)
- **Safety**: Python vulnerabilities (strict enforcement)
- **npm audit**: Node.js vulnerabilities (--audit-level=critical)
- **Dependency tracking**: SBOM generation ready

### Container Security
- **Trivy**: Image vulnerability scanning
  - **Enforcement**: Fails on CRITICAL findings only
  - Scans: OS packages + application dependencies
- **Base images**: Distroless/Alpine recommended
- **Image signing**: Ready for Cosign/Notary integration

### Policy Enforcement
- **OPA**: Kubernetes policy validation
  - Image registry restrictions
  - Security context requirements
  - Resource limit enforcement
  - Network policy validation
- **Polaris**: Security audit (fails on errors)
- See [policies/kubernetes-policies.rego](policies/kubernetes-policies.rego)
 & Testing

### Prerequisites
```bash
# Required tools (auto-validated by pipeline)
✓ Docker & Docker Compose
✓ kubectl & kustomize
✓ Python 3.11+ & pip
✓ Node.js 18+ & npm
✓ Azure CLI
✓ Git

# Optional (for local scanning)
✓ Trivy
✓ SonarQube Scanner
```

### Quick Start

1. **Setup Test Environment**
   ```bash
   ./setup-tests.sh    # Creates venv, installs deps
   ```

2. **Run Tests Locally**
   ```bash
   # Activate test environment
   source test-venv/bin/activate  # Linux/Mac
   test-venv\Scripts\activate.bat # Windows
   
   # Smoke tests
   pytest tests/smoke/ -v
   
   # Integration tests
   docker-compose -f docker-compose.test.yml up -d
   sleep 30
   docker-compose -f docker-compose.test.yml exec backend pytest tests/integration/
   docker-compose -f docker-compose.test.yml down -v
   ```

3. **Validate Kubernetes Manifests**
   ```bash
   # Build with Kustomize
   kustomize build gitops/overlays/production
   
   # Run OPA policies
   kustomize build gitops/overlays/production > manifests.yaml
   conftest test manifests.yaml --policy policies/
   
   # Security audit
   polaris audit --audit-path gitops/overlays/production/
   ```

4. **Local Image Builds** (when application code exists)
   ```bash
   # Backend
   docker build -t circle-backend:local ./backend
   
   # Frontend
   docker build -t circle-frontend:local ./frontend
   
   # Ollama
   docker build -t circle-ollama:local ./ollama
   
   # Security scan
   trivy image circle-backend:local
   ```

### Manual Deployment to AKS

```bash
# Login to Azure
az login
az aks get-credentials --resource-group circle-rg --name circle-aks-cluster

# Deploy namespace and secrets first
kubectl create namespace circle-prod
kubectl create secret generic circle-secrets --from-env-file=gitops/base/secrets/.env -n circle-prod

# Deploy via Kustomize
kubectl apply -k gitops/overlays/production

# Verify deployment
kubectl get all -n circle-prod
kubectl rollout status deployment/circle-backend -n circle-prodlesystem required
- No privileged containers
- Resource limits required
- LoadBalancers must be internal
- Ingress must have TLS

**Warning Rules:**
- Pod anti-affinity recommended
- Minimum 2 replicas for HA

## Local Development

### Prerequisites
```bash
# Required tools
- Docker
- kubectl
- kustomize
- trivy
- sonar-scanner
- python 3.11+
- node.js 18+
```
Monitoring & Observability

### Metrics Collection
- **Prometheus**: Scrapes metrics from all services
- **ServiceMonitors**: Auto-discovery of endpoints
- **Metrics exposed**:
  - HTTP request rates and latencies
  - Error rates by service
  - Pod CPU/Memory utilization
  - GPU metrics (Ollama)

### Logging
- **Fluent Bit**: DaemonSet for log collection
- **Log aggregation**: Configured for circle-prod namespace
- **Optional**: Azure Log Analytics integration

### Dashboards
- **Grafana**: Pre-configured dashboards
  - Request rate and error trends
  - Response time percentiles (p50, p95, p99)
  - Resource utilization
  - GPU utilization
  - Database connections

### Alerts
Configured in [monitoring/service-monitor.yaml](monitoring/service-monitor.yaml):
- High error rate (>5% for 5min)
- Pod crash looping
- High memory usage (>90%)
- High CPU usage (>80%)
- Deployment replica mismatches
- PV usage high (>85%)

## Troubleshooting

### Pipeline Failures

**Tooling Validation Failure:**
```bash
# Install missing tools
# See Prerequisites section
# Verify: az --version, kubectl version, etc.
```

**Quality Gate Failure:**
```bash
# Check SonarQube dashboard at http://sonarqube-url
# Review code quality issues
# Fix security hotspots and code smells
# Push fixes and re-run pipeline
```

**Container Scan Failure (CRITICAL findings):**
```bash
# Review Trivy reports in Jenkins artifacts
# Update base image versions
docker build --pull ...  # Force pull latest base
# Patch application dependencies
pip install --upgrade <package>
npm update <package>
```

**Smoke Test Failures:**
```bash
# Check if services are healthy
kubectl get pods -n circle-prod
kubectl logs -n circle-prod deployment/circle-backend

# Verify BASE_URL is correct
echo $BASE_URL

# Run smoke tests manually
BASE_URL=http://your-service pytest tests/smoke/ -v
```

**Deployment Failure:**
```bash
# Check ArgoCD sync status
argocd app get circle-of-trust-prod

# Check pod status
kubectl get pods -n circle-prod
kubectl describe pod <pod-name> -n circle-prod

# Check events
kubectl get events -n circle-prod --sort-by='.lastTimestamp'

# Check rollout
kubectl rollout status deployment/circle-backend -n circle-prod

# View logs
kubectl logs -n circle-prod deployment/circle-backend --tail=100
```

**Policy Enforcement Failure:**
```bash
# Review policy reports in Jenkins artifacts
# Check OPA violations
conftest test <manifest> --policy policies/ --output json

# Fix manifest issues
# Common: missing resource limits, security contexts, labels
```

### Rollback Procedures

**Automatic Rollback:**
Pipeline auto-triggers rollback on deployment/test failures.

**Manual Rollback via Pipeline:**
```bash
# Trigger Jenkinsfile.rollback with parameters:
- NAMESPACE: circle-prod
- SERVICE: all|backend|frontend|ollama
- ROLLBACK_REVISION: (leave empty for previous)
- CONFIRM_ROLLBACK: true
```

**Manual Rollback via kubectl:**
```bash
# Rollback to previous version
kubectl rollout undo deployment/circle-backend -n circle-prod
kubectl rollout undo deployment/circle-frontend -n circle-prod
kubectl rollout undo statefulset/circle-ollama -n circle-prod

# Check revision history
kubectl rollout history deployment/circle-backend -n circle-prod

# Rollback to specific revision
kubectl rollout undo deployment/circle-backend --to-revision=2 -n circle-prod
```

## Configuration Reference

### Environment Variables (Jenkinsfile)

| Variable | Default | Description |
|----------|---------|-------------|
| `ACR_NAME` | circlerecristry | Azure Container Registry name |
| `AKS_CLUSTER_NAME` | circle-aks-cluster | AKS cluster name |
| `AKS_RESOURCE_GROUP` | circle-rg | Azure resource group |
| `ARGOCD_SERVER` | argocd.circle.internal | ArgoCD server endpoint |
| `ARGOCD_APP` | circle-of-trust-prod | ArgoCD application name |
| `GITOPS_REPO` | (update required) | GitOps repository URL |
| `NAMESPACE` | circle-prod | Kubernetes namespace |
| `BACKEND_SERVICE_PORT` | 8001 | Backend service port |
| `SLACK_CHANNEL` | #deployments | Slack notification channel |
| `LOG_ANALYTICS_RESOURCE_ID` | (optional) | Azure Log Analytics workspace |

### Jenkins Credentials Required

| ID | Type | Usage |
|----|------|-------|
| `azure-subscription-id` | Secret text | Azure subscription |
| `azure-acr-credentials` | Username/Password | ACR login |
| `azure-service-principal` | Service Principal | AKS access |
| `github-credentials` | Username/Password | GitOps repo |
| `argocd-auth-token` | Secret text | ArgoCD API |
| `SonarQube` | Server | SonarQube connection |

## Documentation

### Architecture & Design
- **[AKS-DEPLOYMENT-STRATEGY.md](docs/AKS-DEPLOYMENT-STRATEGY.md)** - 🏗️ **Complete architecture design and deployment strategy**

### Implementation Documentation
- **[Jenkinsfile](Jenkinsfile)** - Main CI/CD pipeline implementation
- **[Jenkinsfile.rollback](Jenkinsfile.rollback)** - Automated rollback pipeline
- **[tests/README.md](tests/README.md)** - Testing guide and test suite documentation
- **[gitops/README.md](gitops/README.md)** - GitOps setup and Kubernetes manifests

### Additional Resources
- **[tests/TEST-INTEGRATION-VALIDATION.md](tests/TEST-INTEGRATION-VALIDATION.md)** - Test integration validation checklist
- **[docs/MESSAGING-PLATFORM-INTEGRATION.md](docs/MESSAGING-PLATFORM-INTEGRATION.md)** - Messaging platform integration details

## Solution Features

This implementation delivers a production-ready CI/CD solution with the following capabilities:

### Build, Test, and Deploy Stages ✅
**Delivered:** 16-stage Jenkins pipeline with parallel execution for efficiency
- Build stages for backend, frontend, and Ollama containers
- Multiple test stages (unit, integration, smoke, performance)
- GitOps-based deployment via ArgoCD sync
- **Location:** [Jenkinsfile](Jenkinsfile) - Stages 1-16

### Pre-Deployment Tests ✅
**Delivered:** Comprehensive testing at multiple levels with strict quality gates
- Unit tests for backend (pytest) and frontend (Jest)
- SonarQube quality gate enforcement (pipeline fails if not met)
- Code linting and style checks
- Integration tests with isolated Docker environment
- **Location:** [Jenkinsfile](Jenkinsfile) - Stages 3, 5, 8 | [tests/](tests/)

### Monitoring, Logging & Audit ✅
**Delivered:** Full observability stack with metrics, logs, and audit trails
- Prometheus ServiceMonitors for metric collection
- Grafana dashboards for visualization
- Fluent Bit DaemonSet for log aggregation
- Audit logging for all pipeline executions
- Alert rules for critical conditions
- **Location:** [Jenkinsfile](Jenkinsfile) - Stages 15-16 | [monitoring/](monitoring/)

### Vulnerability Scanning (SAST/SCA) ✅
**Delivered:** Multi-layer security scanning with strict enforcement
- **SAST:** SonarQube code analysis with security hotspot detection
- **SCA:** Safety (Python) and npm audit (Node.js) for dependency vulnerabilities
- **Container Security:** Trivy scanning with CRITICAL severity enforcement
- **Secret Detection:** Gitleaks for exposed credentials
- **Policy Enforcement:** OPA and Polaris for Kubernetes best practices
- **Location:** [Jenkinsfile](Jenkinsfile) - Stages 4, 7, 14 | [policies/](policies/)

### Automated Deployment & Rollback ✅
**Delivered:** GitOps-based deployment with automated rollback capabilities
- ArgoCD for declarative, drift-free deployments
- Automated rollback pipeline triggered on failures
- Health checks and smoke tests validate deployments
- Pod Disruption Budgets ensure zero-downtime updates
- **Location:** [Jenkinsfile](Jenkinsfile) - Stage 11 | [Jenkinsfile.rollback](Jenkinsfile.rollback)

### GitOps Approach ✅
**Delivered:** Full GitOps implementation with version-controlled infrastructure
- Kustomize-based Kubernetes manifests
- ArgoCD for automated synchronization
- Separate GitOps repository pattern (configurable)
- Environment-specific overlays (production, staging)
- **Location:** [gitops/](gitops/) - Complete manifest suite with 13+ resource files

### Additional Features 🎁

This solution also includes:

1. **Production-Grade Kubernetes Manifests** - Complete resource definitions with security hardening
2. **Network Security** - Network policies with deny-all baseline
3. **High Availability** - HPA, PDB, multi-zone deployment patterns
4. **GPU Workload Support** - StatefulSet pattern for Ollama LLM service
5. **Database Migration Pattern** - Kubernetes Job for schema updates
6. **Comprehensive Documentation** - Architecture decisions with rationale
7. **Local Development Support** - Scripts and guides for testing locally
8. **Troubleshooting Guides** - Common failure scenarios with solutions

## Project Status

**✅ Complete Implementation**

This repository contains a complete enterprise-grade CI/CD pipeline with all components implemented and production-ready.

### What's Included

**Pipeline Configuration Files (Primary Deliverable):**
- [x] [Jenkinsfile](Jenkinsfile) - Complete 16-stage CI/CD pipeline
- [x] [Jenkinsfile.rollback](Jenkinsfile.rollback) - Automated rollback pipeline
- [x] [docker-compose.test.yml](docker-compose.test.yml) - Integration test environment
- [x] [sonar-project.properties](sonar-project.properties) - Code quality configuration
- [x] [pytest.ini](pytest.ini) - Test framework configuration

**GitOps & Kubernetes Manifests:**
- [x] Complete Kubernetes resource definitions (13+ manifest files)
- [x] Kustomize base and production overlays
- [x] ArgoCD application configuration
- [x] Network policies for zero-trust security
- [x] HPA, PDB, and ServiceMonitors

**Security & Policy:**
- [x] SAST/SCA integration (SonarQube, Safety, npm audit)
- [x] Container vulnerability scanning (Trivy)
- [x] Secret detection (Gitleaks)
- [x] OPA policy enforcement
- [x] Polaris security auditing

**Testing Infrastructure:**
- [x] Unit test framework (pytest, Jest)
- [x] Integration test suite
- [x] Smoke test suite
- [x] Performance test suite (k6)
- [x] Test environment setup scripts

**Monitoring & Observability:**
- [x] Prometheus ServiceMonitors
- [x] Grafana dashboards
- [x] Fluent Bit log aggregation
- [x] Alert rules and audit logging

**Documentation:**
- [x] Architecture design document ([AKS-DEPLOYMENT-STRATEGY.md](docs/AKS-DEPLOYMENT-STRATEGY.md))
- [x] Complete README with usage instructions
- [x] Test documentation and guides
- [x] Troubleshooting procedures

### Implementation Notes

This repository provides the **complete CI/CD pipeline and infrastructure configuration** for deploying the "Circle of Trust" multi-LLM application to Azure Kubernetes Service.

**Included in This Repository:**
- Production-ready CI/CD pipeline configuration
- Complete Kubernetes manifest suite
- Security scanning and policy enforcement
- Monitoring and logging infrastructure
- GitOps deployment workflow
- Automated testing framework

**Application Components (Not Included):**
To deploy an actual application, you would need to add:
1. Backend application code in `backend/` directory
2. Frontend application code in `frontend/` directory
3. Dockerfiles for each component
4. Application-specific unit tests
5. A separate GitOps repository for ArgoCD
6. Provisioned AKS cluster and Azure resources

The infrastructure and pipeline code is **ready for immediate use** with any compatible application following the expected structure.

## Contributing

### Making Changes

1. **Test Locally First**
   ```bash
   # Validate manifests
   kustomize build gitops/overlays/production
   
   # Run policy checks
   conftest test manifests.yaml --policy policies/
   
   # Test smoke tests
   pytest tests/smoke/ -v
   ```

2. **Update Documentation**
   - Update relevant README files
   - Add troubleshooting tips if needed
   - Update version history

3. **Submit Changes**
   - Create feature branch
   - Make changes
   - Test in staging
   - Create pull request
   - Deploy to production after approval

## Support & Resources

- **Jenkins Build Logs**: Check detailed execution logs
- **ArgoCD UI**: Monitor GitOps sync status
- **Kubernetes Events**: `kubectl get events -n circle-prod`
- **Pod Logs**: `kubectl logs -n circle-prod <pod-name>`
- **Metrics**: Grafana dashboards
- **Logs**: Fluent Bit aggregation

## License

MIT License - See LICENSE file for details

## Version History

### v1.0.0 - Production Release (2026-01-30)
- ✅ Complete Jenkins pipeline with 16 stages
- ✅ GitOps deployment via ArgoCD
- ✅ Comprehensive security scanning
- ✅ Full Kubernetes manifest suite
- ✅ Automated rollback capability
- ✅ Test infrastructure with 4 test suites
- ✅ Monitoring and logging stack
- ✅ Policy enforcement framework
- ✅ Network security with policies
- ✅ Complete documentation suite

---

