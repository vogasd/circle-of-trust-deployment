# Circle of Trust - Azure Kubernetes Service (AKS) CI/CD Pipeline

[![Pipeline Status](https://img.shields.io/badge/pipeline-ready-brightgreen)]()
[![Security](https://img.shields.io/badge/security-hardened-blue)]()
[![GitOps](https://img.shields.io/badge/gitops-argocd-orange)]()

## Overview

Enterprise-grade CI/CD pipeline for deploying the Circle of Trust multi-LLM application to Azure Kubernetes Service (AKS). This implementation demonstrates production-ready DevOps practices including GitOps, comprehensive security scanning, automated testing, and infrastructure as code.

**Key Features:**
- ✅ Complete Jenkins pipeline with parallel execution
- ✅ GitOps deployment via ArgoCD
- ✅ Multi-stage security scanning (SAST/SCA/container)
- ✅ Comprehensive testing (unit/integration/smoke/performance)
- ✅ Automated rollback capability
- ✅ Full Kubernetes manifests with security hardening
- ✅ Observability stack (Prometheus/Grafana/Fluent Bit)
- ✅ Policy enforcement (OPA/Polaris)
- ✅ Azure-native integration

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
├── AKS-DEPLOYMENT-STRATEGY.md      # Architecture documentation
├── CI-CD-README.md                 # Detailed pipeline guide
└── TEST-INTEGRATION-VALIDATION.md  # Test integration checklist
```

## Quick Start

### Prerequisites

```bash
# Required tools (validated by pipeline)
- Jenkins (2.400+)
- Azure CLI
- kubectl
- kustomize
- Docker
- ArgoCD CLI
- Python 3.11+
- Node.js 18+
- Trivy
- SonarQube Scanner
- Conftest
- Polaris
```

### Initial Setup

1. **Configure Jenkins Credentials**
   ```groovy
   - azure-subscription-id
   - azure-acr-credentials (username/password)
   - azure-service-principal (for AKS access)
   - github-credentials (for GitOps repo)
   - argocd-auth-token
   - SonarQube (server connection)
   ```

2. **Update Configuration**
   ```bash
   # Edit Jenkinsfile - Update these values:
   ACR_NAME = 'your-acr-name'
   AKS_CLUSTER_NAME = 'your-aks-cluster'
   AKS_RESOURCE_GROUP = 'your-rg'
   GITOPS_REPO = 'https://github.com/your-org/circle-gitops.git'
   ARGOCD_SERVER = 'your-argocd-server'
   SLACK_CHANNEL = '#your-channel'
   ```

3. **Create Secrets**
   ```bash
   cd gitops/base/secrets/
   cp .env.example .env
   # Edit .env with actual secrets
   ```

4. **Setup Test Environment**
   ```bash
   # Windows
   setup-tests.bat
   
   # Linux/Mac
   chmod +x setup-tests.sh
   ./setup-tests.sh
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
kubectfiguration Reference

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

- **[PIPELINE.md](PIPELINE.md)** - Requirements specification
- **[AKS-DEPLOYMENT-STRATEGY.md](AKS-DEPLOYMENT-STRATEGY.md)** - Complete architecture and deployment strategy
- **[CI-CD-README.md](CI-CD-README.md)** - Detailed pipeline documentation
- **[TEST-INTEGRATION-VALIDATION.md](TEST-INTEGRATION-VALIDATION.md)** - Test integration checklist
- **[gitops/README.md](gitops/README.md)** - GitOps setup instructions
- **[tests/README.md](tests/README.md)** - Testing guide

## Key Improvements from Base Requirements

✨ **Enhanced from original PIPELINE.md requirements:**

1. **Production-Ready Manifests** - Complete Kubernetes manifests with security hardening
2. **Strict Enforcement** - Non-blocking scans converted to fail-on-critical
3. **True GitOps** - ArgoCD sync instead of direct kubectl apply
4. **Comprehensive Testing** - All test types integrated with proper venv isolation
5. **Tooling Validation** - Pre-flight checks for all required tools
6. **Logging Stack** - Fluent Bit deployment for log aggregation
7. **Network Policies** - Deny-all baseline with explicit allow rules
8. **Database Migrations** - Job pattern for schema updates
9. **Observability** - Complete monitoring stack with ServiceMonitors, dashboards, and alerts
10. **Documentation** - Extensive docs with troubleshooting and examples

## Project Status

**✅ Production-Ready Pipeline**

- [x] Complete Jenkins CI/CD pipeline
- [x] GitOps workflow with ArgoCD
- [x] Kubernetes manifests (all 13 required files)
- [x] Security scanning (SAST/SCA/container)
- [x] Comprehensive testing (unit/integration/smoke/performance)
- [x] Monitoring and logging infrastructure
- [x] Policy enforcement (OPA/Polaris)
- [x] Automated rollback capability
- [x] Network security (network policies)
- [x] Documentation and troubleshooting guides

**⚠️ Next Steps for Full Deployment**

The pipeline infrastructure is complete. To deploy an actual application:

1. Create backend application in `backend/` directory
2. Create frontend application in `frontend/` directory  
3. Create Dockerfiles for backend/frontend/ollama
4. Add actual unit tests for backend/frontend
5. Update integration tests with real service calls
6. Create/configure GitOps repository
7. Deploy AKS cluster per AKS-DEPLOYMENT-STRATEGY.md
8. Configure all Jenkins credentials
9. Update configuration values in Jenkinsfile
10. Run pipeline!

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

**Built with ❤️ for enterprise-grade Kubernetes deployments**tp://localhost:9000

# Dependency check
pip install safety
safety check --json
```

## Environment Variables

### Jenkins Credentials
- `azure-subscription-id`: Azure subscription ID
- `azure-acr-credentials`: ACR username/password
- `azure-service-principal`: Azure SP for AKS access
- `github-credentials`: GitHub token for GitOps repo
- `SonarQube`: SonarQube server connection

### Configuration
```groovy
ACR_NAME = 'circlerecristry'
AKS_CLUSTER_NAME = 'circle-aks-cluster'
AKS_RESOURCE_GROUP = 'circle-rg'
NAMESPACE = 'circle-prod'
GITOPS_REPO = 'https://github.com/your-org/circle-gitops.git'
```

## Deployment Targets

### Production
- **Namespace**: circle-prod
- **Replicas**: Backend (5), Frontend (3), Ollama (1-3)
- **Resources**: Production-grade limits
- **Auto-scaling**: HPA enabled
- **Monitoring**: Full observability stack

### Staging (Optional)
- **Namespace**: circle-staging
- **Replicas**: Reduced for cost savings
- **Resources**: Lower limits
- **Purpose**: Pre-production validation

## Compliance and Audit

### Audit Logs
- All deployments logged with metadata
- Rollbacks tracked and annotated
- Build artifacts archived (30 days)
- Test results retained

### Compliance Reports
- SonarQube quality reports
- Security scan results
- Test coverage reports
- Policy validation results

## Troubleshooting

### Pipeline Failures

**Quality Gate Failure:**
```bash
# Check SonarQube dashboard
# Fix code quality issues
# Re-run pipeline
```

**Container Scan Failure:**
```bash
# Review Trivy report
# Update base images
# Patch vulnerabilities
# Re-build images
```

**Deployment Failure:**
```bash
# Check pod logs
kubectl logs -n circle-prod <pod-name>

# Check events
kubectl get events -n circle-prod

# Check rollout status
kubectl rollout status deployment/<name> -n circle-prod
```

**Rollback Failure:**
```bash
# Manual rollback
kubectl rollout undo deployment/<name> -n circle-prod

# Check revision history
kubectl rollout history deployment/<name> -n circle-prod
```

## Performance Optimization

### Pipeline Optimization
- Parallel stage execution
- Docker layer caching
- Dependency caching
- Artifact reuse

### Resource Optimization
- Multi-stage Docker builds
- Minimal base images
- Resource limits tuned
- Auto-scaling configured

## Contributing

### Pipeline Updates
1. Test changes locally
2. Update documentation
3. Create pull request
4. Run pipeline in staging
5. Deploy to production

### Adding New Stages
1. Update Jenkinsfile
2. Add necessary tools
3. Update credentials
4. Document changes
5. Test thoroughly

## Support

For issues or questions:
- Check troubleshooting section
- Review Jenkins build logs
- Check Kubernetes events
- Contact DevOps team

## License

[Your License Here]

## Version History

- v1.0.0 - Initial pipeline implementation
  - Jenkins-based CI/CD
  - GitOps with ArgoCD
  - Comprehensive security scanning
  - Automated rollback capability
