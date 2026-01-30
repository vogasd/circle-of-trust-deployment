# Circle of Trust - Azure Kubernetes Service (AKS) Deployment Strategy

**Project**: Circle of Trust (LLM Council)  
**Target Platform**: Azure Kubernetes Service (AKS)  
**Date**: January 27, 2026  
**Status**: Planning Phase

---

## Executive Summary

Deploy the Circle of Trust multi-LLM application on Azure Kubernetes Service (AKS) with enterprise-grade security, compliance, monitoring, and high availability. The solution will leverage Azure-native services for managed Kubernetes, GPU compute, observability, and security compliance.

---

## 1. Architecture Design

### 1.1 Core Infrastructure Components

**Azure Kubernetes Service (AKS) Cluster Configuration:**
- **Multi-Zone Deployment**: 3 availability zones in single region (e.g., East US 2)
  - **Rationale**: Provides 99.99% SLA for cluster availability, protects against datacenter failures, enables zero-downtime maintenance. Three zones is the Azure standard for production workloads, balancing cost with resilience.

- **Node Pools Architecture**:
  - **System Node Pool**: Standard_D4s_v3 (3 nodes, auto-scale 3-5)
    - Runs system pods (CoreDNS, metrics-server, etc.)
    - Non-GPU workloads
    - **Rationale**: Dedicated system pool prevents resource contention from application workloads affecting cluster control plane components. Standard_D4s_v3 provides sufficient resources (4 vCPU, 16GB RAM) for system pods without over-provisioning. Minimum 3 nodes ensures one node per zone for HA.
  
  - **Application Node Pool**: Standard_D8s_v3 (2-6 nodes, auto-scale)
    - Runs FastAPI backend pods
    - Horizontal pod autoscaling enabled
    - **Rationale**: Separation from GPU nodes allows independent scaling of API workloads. D8s_v3 (8 vCPU, 32GB RAM) sized for compute-intensive API operations and LLM coordination logic. Autoscaling 2-6 balances cost during low traffic while handling peak loads.
  
  - **GPU Node Pool**: Standard_NC6s_v3 or Standard_NC4as_T4_v3 (1-3 nodes)
    - Dedicated for Ollama inference workloads
    - NVIDIA T4 GPUs (16GB VRAM each)
    - Spot instances with regular fallback for cost optimization
    - **Rationale**: GPU isolation prevents expensive GPU resources being wasted on non-ML workloads. T4 GPUs chosen for cost-effectiveness ($0.90/hr vs. $3/hr for A100) while providing adequate performance for LLaMA-2 7B/13B models. Spot instances save 70-90% on GPU costs, acceptable for stateless inference with proper failover.
  
  - **Frontend Node Pool**: Standard_B4ms (2-4 nodes)
    - Runs Nginx ingress and static frontend serving
    - Lower cost instances sufficient for web serving
    - **Rationale**: Burstable B-series VMs ideal for web serving workloads with variable CPU usage patterns. Significantly cheaper than general-purpose VMs ($0.166/hr vs. $0.40/hr) while providing burst capacity for traffic spikes. Separate pool prevents frontend from consuming backend/GPU resources.

**Cluster Features:**
- **Kubernetes Version**: 1.28+ (with N-1 version support)
  - **Rationale**: N-1 support ensures access to latest security patches while maintaining stability for production. Quarterly upgrades align with Kubernetes release cycle.

- **Network Plugin**: Azure CNI (for advanced networking)
  - **Rationale**: Azure CNI assigns Azure VNet IPs directly to pods, enabling direct pod-to-pod communication without NAT. Required for Azure Network Policies, private endpoints, and service mesh. Kubenet alternative would require UDRs and limit scale. Trade-off: consumes more IP addresses but provides superior performance and Azure integration.

- **Network Policy**: Calico or Azure Network Policy
  - **Rationale**: Calico offers richer policy features (egress rules, DNS policies, global network sets) vs. Azure Network Policy. Both provide zero-trust networking. Calico preferred for complex microservices; Azure Network Policy sufficient for simpler deployments and lower overhead.

- **Container Runtime**: containerd
  - **Rationale**: AKS default, lighter than Docker, CRI-compliant, better security posture (no daemon with root privileges). Required for Kubernetes 1.24+.

- **Cluster Autoscaler**: Enabled on all node pools
  - **Rationale**: Automatically adjusts node count based on pod resource requests, optimizing costs during low-traffic periods while ensuring capacity during peaks. Essential for unpredictable LLM workload patterns.

- **Azure AD Integration**: For RBAC and identity management
  - **Rationale**: Centralized identity management, eliminates need for Kubernetes service account tokens for human access. Enables conditional access policies, MFA enforcement, and audit trails through Azure AD logs.

- **Managed Identity**: For Azure resource access (no service principals)
  - **Rationale**: No credential rotation burden, automatic credential management by Azure, reduced security risk from leaked secrets. Integrates seamlessly with Azure RBAC for ACR, Key Vault, and storage access.

### 1.2 Data Layer Architecture

**Azure Database for PostgreSQL - Flexible Server:**
- **Tier**: General Purpose or Memory Optimized
  - **Rationale**: Flexible Server chosen over Single Server for better performance (up to 2x faster), more deployment options (zone redundancy, private networking), and cost optimization features. General Purpose sufficient for most workloads; Memory Optimized for high-concurrency scenarios with >1000 concurrent connections.

- **Configuration**: 
  - 4-8 vCores, 16-32GB RAM
    - **Rationale**: Sized for moderate concurrent user base (100-500 active users). 4 vCores = ~200 connections with connection pooling. 16GB RAM supports working set + connection overhead. Can scale up without downtime as usage grows.
  - Zone-redundant high availability (synchronous replication)
    - **Rationale**: Provides 99.99% SLA (vs. 99.9% for single-zone), automatic failover in <120 seconds, protects against zone failures. Synchronous replication ensures zero data loss (RPO=0). Worth 100% cost premium for production data integrity.
  - Automated backups with 35-day retention
    - **Rationale**: Azure default is 7 days; extended to 35 days for compliance requirements and extended point-in-time recovery window. Balances storage costs with recovery needs.
  - Point-in-time restore capability
    - **Rationale**: Critical for recovery from accidental data deletion, corruption, or bad migrations. Can restore to any second within retention window. Alternative to application-level soft deletes.
  - Geo-redundant backup for disaster recovery
    - **Rationale**: Protects against regional disasters. Geo-backup stored in paired Azure region, enables restoration if primary region unavailable. Adds minimal cost (~10% of storage) for significant risk mitigation.

- **Security**:
  - Private endpoint (no public access)
    - **Rationale**: Database never exposed to internet, accessible only from AKS VNet. Eliminates surface area for brute-force attacks, DDoS, or unauthorized access attempts. Industry best practice for PaaS database security.
  - VNet integration with AKS subnet
    - **Rationale**: Direct private connectivity between AKS and PostgreSQL without leaving Azure backbone. Lower latency, higher throughput, no internet-based routing.
  - SSL/TLS enforced connections
    - **Rationale**: Encrypts data in transit, prevents man-in-the-middle attacks. Required for compliance frameworks (PCI-DSS, HIPAA). Enforced at server level to prevent accidental non-encrypted connections.
  - Data encryption at rest (Azure Storage Service Encryption)
    - **Rationale**: Protects against physical disk theft, decommissioned hardware exposure. Transparent encryption with no performance penalty. Uses Azure-managed keys by default, supports customer-managed keys for regulatory requirements.
  - Azure AD authentication enabled
    - **Rationale**: Eliminates need to manage PostgreSQL passwords, centralized access management, MFA support, automated credential rotation. Users authenticate with Azure AD tokens instead of static passwords.

**Azure Storage Accounts:**
- **Persistent Volume Storage**: Azure Disk (Premium SSD)
  - For Ollama model persistence (100-500GB per GPU node)
  - ZRS (Zone-Redundant Storage) for HA
  - **Rationale**: Premium SSD required for fast model loading (LLaMA-2 13B = ~26GB, load time <30s vs. 2+ minutes on Standard). ZRS replicates across zones for resilience if GPU pod reschedules. Azure Disk chosen over Blob/Files for single-pod read/write access pattern and IOPS requirements (>5000 IOPS for model inference). 100-500GB sized for multiple models + cache.

- **Blob Storage**: For application artifacts, logs, backups
  - Hot tier for active logs (30 days)
    - **Rationale**: Hot tier optimized for frequent access, ~$0.018/GB/month. Logs accessed daily for debugging, analysis.
  - Cool tier for archived logs (90 days)
    - **Rationale**: Cool tier ($0.01/GB/month) for infrequent access, higher retrieval cost acceptable for older logs. 30-90 day window for compliance and historical analysis.
  - Archive tier for compliance retention (7 years)
    - **Rationale**: Archive tier ($0.00099/GB/month, 180x cheaper than hot) for regulatory retention. Rehydration takes hours, acceptable for audit scenarios. Lifecycle policies automate transitions, eliminating manual intervention.

- **Azure Files**: For shared configuration and prompt templates
  - SMB protocol with Azure AD Kerberos authentication
  - **Rationale**: Azure Files supports ReadWriteMany for shared access across pods (prompt templates used by multiple backend pods). SMB with AD Kerberos provides identity-based access control vs. shared storage keys. Alternative to maintaining ConfigMaps for large files (>1MB limit). NFSv4.1 alternative but SMB better Windows compatibility for dev workflows.

### 1.3 Networking Architecture

**Virtual Network Design:**
- **VNet Address Space**: 10.240.0.0/16
- **Subnets**:
  - AKS System Subnet: 10.240.0.0/20 (4096 IPs)
  - AKS Application Subnet: 10.240.16.0/20
  - AKS GPU Subnet: 10.240.32.0/22
  - PostgreSQL Private Endpoint Subnet: 10.240.48.0/24
  - Azure Bastion Subnet: 10.240.49.0/27
  - Application Gateway Subnet: 10.240.50.0/24

**Ingress and Load Balancing:**
- **Azure Application Gateway v2** (WAF-enabled)
  - Layer 7 load balancer with SSL termination
  - Web Application Firewall (WAF) with OWASP Top 10 protection
  - Autoscaling capability (2-10 instances)
  - Public IP with DDoS Standard protection
  - **Rationale**: Application Gateway provides Azure-native WAF protecting against SQL injection, XSS, and OWASP Top 10 threats before traffic reaches AKS. SSL termination at edge reduces CPU load on ingress pods. v2 autoscaling eliminates fixed capacity costs. Integration with Azure Monitor and DDoS Protection creates comprehensive perimeter defense. Alternative Azure Load Balancer lacks Layer 7 features. Cost: ~$300/month justified by security and performance benefits.

- **NGINX Ingress Controller** (inside AKS)
  - Internal load balancer
  - Handles routing to backend/frontend services
  - Rate limiting and request buffering
  - **Rationale**: Dual-layer architecture - App Gateway handles perimeter, NGINX handles internal routing. NGINX provides advanced routing (path-based, header-based), rate limiting per endpoint (critical for expensive LLM calls), and request buffering for large payloads. Community-driven, extensive ecosystem, battle-tested at scale. Alternative Traefik/Istio considered but NGINX has better maturity and team familiarity.

- **Azure Front Door** (optional, for multi-region)
  - Global load balancing
  - CDN for frontend static assets
  - Geo-filtering and custom WAF rules
  - **Rationale**: Optional for Phase 2 multi-region deployment. Provides global edge network (edge POP latency <50ms for 95% of users), intelligent routing to closest healthy region, unified WAF policies. CDN caching reduces backend load by 80%+ for static assets. Cost (~$300/month base) justified only when serving global user base or requiring 99.99%+ availability across regions.

**Service Mesh Consideration:**
- **Istio or Linkerd**: For advanced traffic management
  - mTLS between all services
  - Circuit breaking and retry logic
  - Canary deployments
  - Distributed tracing integration
  - **Rationale**: Service mesh optional for Phase 1, recommended for Phase 2. Istio provides automatic mTLS encryption between all pods (zero-trust networking), sophisticated traffic shaping for canary rollouts (5% → 50% → 100%), and built-in observability (distributed tracing without code changes). Trade-offs: adds complexity (learning curve, debugging), resource overhead (~100-200MB per node for sidecar proxies), and operational burden. Linkerd alternative is lighter (Rust-based, ~20MB overhead) but fewer features. Decision: Start without service mesh, add when scaling beyond 10 microservices or requiring zero-trust compliance. Network policies sufficient for initial security requirements.

**DNS and Certificates:**
- **Azure DNS**: For domain management
- **Azure Key Vault**: Certificate storage
- **cert-manager**: Automated Let's Encrypt or Azure-issued certificates
- **External DNS**: Automatic DNS record management

---

## 2. Application Deployment Strategy

### 2.1 Containerization & Registry

**Azure Container Registry (ACR):**
- **Premium Tier**: For geo-replication and advanced features
  - **Rationale**: Premium tier ($0.834/day vs. $0.167 Basic, $0.333 Standard) required for geo-replication to DR region (RPO for container images), private endpoints for secure VNet integration, and content trust for image signing. 500GB included storage sufficient for 100-200 application images with history. Zone redundancy protects against datacenter failures. Alternative: Standard tier lacks geo-replication and private endpoints, unacceptable for production security posture. Cost justified by DR capabilities and security compliance requirements.

- **Features**:
  - Private endpoints (no public access)
    - **Rationale**: Eliminates attack surface from internet exposure. AKS pulls images over Azure backbone, never traversing public internet. Required for regulatory compliance (PCI-DSS, HIPAA). Prevents unauthorized image pulls even if credentials leaked.
  - Geo-replication to DR region
    - **Rationale**: Enables fast recovery if primary region fails - no need to rebuild images. Synchronous replication ensures DR region has latest images (RPO near-zero). Reduces latency for multi-region deployments. Alternative DR approach (re-build from source) adds 15-30 minute RTO.
  - Image signing with Docker Content Trust
    - **Rationale**: Cryptographically verifies image integrity and publisher identity. Prevents supply chain attacks from compromised registries or man-in-the-middle image substitution. Admission controller enforces only signed images run in production.
  - Vulnerability scanning with Microsoft Defender for Containers
    - **Rationale**: Continuous scanning for CVEs in OS packages and application dependencies. Automatically scans on push and re-scans daily for new vulnerabilities. Defender integration surfaces findings in Azure Security Center with remediation guidance.
  - Quarantine pattern (scan before pull)
    - **Rationale**: Prevents vulnerable images from ever running in cluster. Images quarantined until scan passes security threshold (no CRITICAL CVEs). Webhook notifies teams of quarantined images for remediation.
  - Retention policies for old images
    - **Rationale**: Automatically purge images older than 180 days with no tags, reduces storage costs. Retains last N versions per tag for rollback capability. Frees 30-50% storage in mature repositories.

- **Integration**: AKS pulls via managed identity (no credentials)
  - **Rationale**: Eliminates ImagePullSecrets management, no credential rotation required, automatic Azure AD authentication. Managed identity has ACR Pull RBAC role, scoped to specific ACR. Simpler, more secure than traditional service principal approach.

**Container Images:**
- **Backend Image**: Python FastAPI application
  - Multi-stage build for minimal size
  - Non-root user execution
  - Distroless or Alpine base for security
- **Frontend Image**: Nginx serving React build
  - Static asset caching headers
  - Security headers (CSP, HSTS, etc.)
- **Ollama Image**: Custom image with pre-pulled models
  - GPU-enabled base image (CUDA toolkit)
  - Lazy loading for large models
  - Health check endpoints

### 2.2 Kubernetes Resources Architecture

**Namespace Strategy:**
- `circle-system`: System components (monitoring, logging agents)
- `circle-prod`: Production workloads
- `circle-staging`: Staging environment (optional)
- `circle-monitoring`: Observability stack

**Deployment Patterns:**

**Backend API Deployment:**
- **Replicas**: 3-10 pods (HPA based on CPU/memory/custom metrics)
- **Resource Limits**: 2 CPU, 4GB RAM per pod
- **Resource Requests**: 500m CPU, 1GB RAM per pod
- **Health Checks**:
  - Liveness probe: `/health` endpoint
  - Readiness probe: `/ready` endpoint (checks DB connection)
  - Startup probe: For slow initialization
- **Anti-affinity**: Spread across availability zones
- **Pod Disruption Budget**: Minimum 2 available during updates

**Ollama GPU Deployment:**
- **StatefulSet** (for persistent model storage)
  - **Rationale**: StatefulSet chosen over Deployment for stable network identity and persistent storage binding. Each Ollama pod needs dedicated PVC for model cache (LLaMA-2 models = 5-50GB each). StatefulSet ensures pod "ollama-0" always reattaches to same PVC after restart, avoiding model re-download (saves 5-15 minutes startup time). Deployment pattern would create new PVC on reschedule, wasting storage and time. Alternative: Shared storage (Azure Files) considered but Ollama requires local disk for performance (NFS adds 50-100ms latency per inference).

- **Replicas**: 1-3 (based on load, expensive GPU nodes)
  - **Rationale**: Starting with 1 replica for cost control ($900-2700/month for GPU nodes). Each T4 handles ~10-15 concurrent inference requests (1-2 requests/sec throughput). Scale to 3 replicas when request queue >30s latency. Higher replica count limited by GPU cost, not technical constraint. Alternative async pattern (queue + workers) considered for future cost optimization.

- **GPU Resource Requests**: 1 NVIDIA GPU per pod
  - **Rationale**: Ollama requires dedicated GPU, does not support GPU sharing (vs. MIG on A100). Requesting exactly 1 GPU ensures Kubernetes scheduler places pod only on GPU nodes and prevents oversubscription. Each T4 = 16GB VRAM, sufficient for LLaMA-2 13B (requires ~12GB). Larger models (70B) would require multi-GPU or A100 instances.

- **Node Affinity**: GPU node pool only
  - **Rationale**: Prevents Ollama pods from being scheduled on non-GPU nodes where they cannot function. Node selector "agentpool=gpunodepool" ensures placement on dedicated GPU pool. Taints on GPU nodes prevent non-GPU workloads from consuming expensive resources.

- **Persistent Volume**: 200GB Premium SSD per pod
  - **Rationale**: Sized for 3-5 models (LLaMA-2 7B/13B, Mistral 7B, CodeLlama) + quantized variants + working cache. Premium SSD required for fast model loading (<30s cold start vs. 3-5 minutes on Standard). ZRS for zone redundancy ensures model data survives zone failure. Alternative: Model embedded in container image rejected due to image size (>30GB) and inflexibility to change models without rebuild.

- **Init Container**: Download/verify models on startup
  - **Rationale**: Init container downloads models from Azure Blob or Hugging Face Hub before main container starts. Ensures models ready before accepting traffic (prevents 404 errors). Checksum verification prevents corrupted downloads. Alternative: Prebaked images rejected as noted above. Trade-off: longer initial pod startup (10-15 min) but greater flexibility.

- **Topology Spread**: Across zones if multiple replicas
  - **Rationale**: Distributes Ollama pods across availability zones for resilience. If zone fails, at least one GPU pod remains available. Reduces blast radius of zone outages. topologySpreadConstraints with maxSkew=1 ensures even distribution.

- **Pod Disruption Budget**: Minimum 1 available (critical service)
  - **Rationale**: Ensures at least one GPU pod always running during voluntary disruptions (node drains, rolling updates). Critical service - frontend depends on Ollama for all LLM features. Without PDB, cluster autoscaler could drain all GPU nodes simultaneously, causing total outage.

**Frontend Deployment:**
- **Replicas**: 2-4 pods
- **Resource Requests**: 100m CPU, 128MB RAM
- **CDN Integration**: Azure Front Door or CDN profile
- **ConfigMap**: For runtime environment variables

**Database Migration Job:**
- **Kubernetes Job**: Run database migrations pre-deployment
- **Init Container Pattern**: Ensure DB schema is ready before app starts

### 2.3 Configuration Management

**Secrets Management:**
- **Azure Key Vault**: Primary secret store
  - Database credentials
  - API keys
  - SSL certificates
  - Encryption keys
- **CSI Driver**: Azure Key Vault Provider for Secrets Store CSI Driver
  - Mount secrets as volumes in pods
  - Auto-rotation support
  - No secrets in environment variables or ConfigMaps
- **Managed Identity**: Pods use Azure AD pod identity to access Key Vault

**Configuration Strategy:**
- **ConfigMaps**: Non-sensitive configuration
  - Ollama API URLs
  - Feature flags
  - Model configurations
- **Environment-specific**: Kustomize overlays or Helm values per environment
- **GitOps**: Configuration stored in Git, deployed via Flux/ArgoCD

### 2.4 Service Communication

**Internal Services:**
- **Backend Service**: ClusterIP type
  - Exposed internally at `backend-api.circle-prod.svc.cluster.local:8001`
- **Ollama Service**: ClusterIP or Headless
  - `ollama.circle-prod.svc.cluster.local:11434`
  - Direct pod-to-pod communication for low latency
- **Frontend Service**: ClusterIP
  - Backend for NGINX ingress

**External Access:**
- **Ingress Resource**: Routes traffic from Application Gateway
  - Path-based routing: `/api/*` → backend, `/*` → frontend
  - SSL/TLS termination at Application Gateway
  - Re-encryption to NGINX ingress (end-to-end TLS)

---

## 3. High Availability & Resilience Strategy

### 3.1 Multi-Zone Architecture

**AKS Configuration:**
- Deploy control plane across 3 availability zones (Azure-managed)
- Distribute node pools across zones using zone spreading
- Ensure at least 1 replica in each zone for critical services

**Database HA:**
- Zone-redundant PostgreSQL with automatic failover
- Standby replica in different zone (synchronous replication)
- 99.99% SLA with zone-redundant configuration

**Storage HA:**
- ZRS (Zone-Redundant Storage) for persistent disks
- Replicated across 3 zones within region
- Automatic failover without data loss

### 3.2 Disaster Recovery (DR)

**Multi-Region Strategy:**
- **Primary Region**: East US 2 (active)
  - **Rationale**: East US 2 chosen for primary due to full Azure service availability (all VM SKUs including GPUs), low latency to US-based users (avg <50ms east coast, <100ms west coast), and paired with Central US for geo-backup. Alternative: West Europe considered for global users but US-centric user base justified US region.

- **DR Region**: West US 2 (passive standby)
  - **Rationale**: West US 2 paired with West Central US, provides geographic separation (~2000 miles from East US 2, different seismic zones, power grids). Passive standby minimizes costs (no running compute, only storage replication ~$200/month vs. $4000/month for active-active). Full AKS infrastructure defined in Terraform, can deploy in <30 min if disaster declared.

- **Recovery Objectives**:
  - RTO (Recovery Time Objective): 1 hour
    - **Rationale**: 1 hour RTO balances recovery speed with cost. Regional Azure outages rare (<1/year), 1 hour downtime acceptable vs. cost of active-active multi-region ($8000+/month). Breakdown: 15 min disaster declaration, 30 min AKS cluster spin-up, 15 min DNS/traffic failover. Alternative: Active-active for <5 min RTO considered but not cost-justified without 99.99% SLA requirement.
  - RPO (Recovery Point Objective): 15 minutes
    - **Rationale**: 15 min RPO acceptable data loss window (typical conversation = 5-10 messages). Achieved through PostgreSQL geo-backup (asynchronous replication, max 15 min lag) and ACR geo-replication (near real-time). Alternative: Synchronous cross-region DB replication achieves RPO=0 but adds 100-150ms latency to every write, unacceptable for user experience. For critical data scenarios, application-level dual-write pattern could achieve RPO <1 min.

**DR Components:**
- **ACR Geo-Replication**: Images replicated to DR region
- **Database Geo-Backup**: Asynchronous replication to DR region
- **Blob Storage GRS**: Geo-redundant storage for artifacts
- **Traffic Manager**: DNS-based failover between regions
- **Runbooks**: Automated failover procedures in Azure Automation

**Backup Strategy:**
- **AKS ETCD Backup**: Daily snapshots via Velero
- **Database Backups**: Continuous + daily snapshots (35-day retention)
- **Persistent Volumes**: Disk snapshots daily
- **Configuration Backup**: Git repository (GitOps source of truth)

### 3.3 Autoscaling Architecture

**Horizontal Pod Autoscaling (HPA):**
- **Backend API**: Scale 3-10 pods based on:
  - CPU utilization (target 70%)
    - **Rationale**: 70% target leaves 30% headroom for traffic spikes before triggering scale-up. Lower threshold (50%) would over-provision; higher (85%) risks performance degradation during scale-up delay (60-90s). CPU metric available without custom metrics server, reliable signal for compute-bound workloads.
  - Memory utilization (target 80%)
    - **Rationale**: Memory usage more stable than CPU (less spiky), 80% threshold prevents OOMKilled errors. FastAPI keeps request context in memory, higher concurrent requests = higher memory. Dual metrics (CPU + memory) ensures scaling for different bottleneck patterns.
  - Custom metrics: Request latency (via Prometheus)
    - **Rationale**: Most user-centric metric - scale when p95 latency >500ms regardless of CPU/memory. Requires Prometheus adapter for metrics server. Prevents resource-efficient but slow responses from causing poor UX. Custom metric weights user experience over infrastructure utilization.

- **Frontend**: Scale 2-6 pods based on CPU
  - **Rationale**: Frontend is stateless Nginx serving static React build, CPU-bound (compression, TLS). Simple CPU-based scaling sufficient, no need for custom metrics. Min 2 for HA, max 6 prevents over-provisioning (diminishing returns beyond 6 due to load balancer as bottleneck). Memory not useful (Nginx uses <100MB per pod).

- **Ollama**: Manual scaling (GPU cost considerations)
  - **Rationale**: GPU nodes expensive ($900/month each), autoscaling would risk cost overruns. Manual approval required for scale-up decisions. Monitor queue depth and latency metrics, trigger manual scale when sustained >30s wait time for 15+ minutes. Alternative: KEDA for queue-based autoscaling would enable automation but requires queue architecture implementation first.
  - Consider KEDA for queue-based autoscaling if async pattern
    - **Rationale**: Future state - implement request queue (Redis/RabbitMQ), Ollama workers pull from queue. KEDA scales based on queue depth (e.g., scale up if >20 messages in queue). Enables burst handling without keeping GPUs idle. Trade-off: adds latency (queue overhead) and complexity (message broker), justified only at scale (>100 concurrent LLM requests).

**Cluster Autoscaling:**
- **Application Node Pool**: 2-10 nodes
  - Scale up when pending pods > 30 seconds
  - Scale down when utilization < 50% for 10 minutes
- **GPU Node Pool**: 1-3 nodes
  - Aggressive scale-down (5 minutes idle)
  - Spot instance integration with regular fallback

**Vertical Pod Autoscaling (VPA):**
- Recommendation mode for right-sizing resource requests
- Avoid auto-mode due to pod restarts

### 3.4 Fault Tolerance Mechanisms

**Circuit Breaker Pattern:**
- Implement in service mesh (Istio) or application code
- Fail fast when Ollama service is unavailable
- Fallback to cached responses or error messages

**Retry Logic:**
- Exponential backoff for transient failures
- Maximum retry attempts: 3
- Timeout configurations per service call

**Rate Limiting:**
- NGINX Ingress rate limiting (per IP, per user)
- Application-level rate limiting for expensive LLM calls
- Azure API Management (optional) for advanced quota management

**Pod Disruption Budgets (PDB):**
- Backend: MinAvailable 2 during rolling updates/node drains
- Ollama: MinAvailable 1 (ensure service continuity)
- Frontend: MinAvailable 1

---

## 4. Security & Compliance Strategy

### 4.1 Identity & Access Management

**Azure AD Integration:**
- **AKS Cluster**: Azure AD-integrated RBAC
- **Users/Groups**: Mapped to Kubernetes roles
- **Service Accounts**: Azure AD pod-managed identities
- **Admin Access**: Just-In-Time (JIT) access via Privileged Identity Management

**Kubernetes RBAC:**
- **Namespace-level roles**: Developers limited to specific namespaces
- **Cluster-admin**: Restricted to platform team only
- **Service Accounts**: Principle of least privilege
- **Role Bindings**: Explicit, auditable permissions

**Network Security:**
- **Network Policies**: Deny all by default, explicit allow rules
  - **Rationale**: Zero-trust network model - assume breach, minimize blast radius. Default deny prevents lateral movement if pod compromised. Explicit allow rules create audit trail of intended communication paths. Industry best practice for compliance frameworks (PCI-DSS, NIST). Alternative: Default allow with explicit deny is reactive security (must know all bad patterns). Cost: None. Trade-off: Requires explicit policy for every new service, prevents "just deploy" approach.
  
  - Backend can only talk to Ollama and PostgreSQL
    - **Rationale**: Backend has no legitimate need for other services or internet access (except API calls, controlled at app layer). Compromised backend pod cannot exfiltrate data to external IPs, cannot pivot to frontend or monitoring namespaces. Policy enforced at kernel level (iptables), cannot be bypassed by application code.
  
  - Ollama isolated from internet (no egress)
    - **Rationale**: Ollama contains LLM models potentially including user data in context. No egress prevents data exfiltration if model or inference code compromised. Models pre-downloaded via init container, no runtime need for internet. Exception: Model updates handled through controlled pipeline with temporary egress policy.
  
  - Frontend can only receive ingress traffic
    - **Rationale**: Frontend is static React app with no legitimate outbound needs (all API calls are browser-initiated, not server-side). Egress block prevents frontend pods from being pivot point in attack chain.

- **Private Cluster**: AKS API server on private endpoint (no public access)
  - **Rationale**: Eliminates entire attack surface of exposed Kubernetes API. No brute force attempts on API, no unauthorized kubectl access from internet. Access only from VNet (via VPN or Azure Bastion for operators). Required for high-security environments. Trade-off: Requires VPN or Bastion for kubectl access, adds operational friction. Cost: None. Alternative: Public API with IP whitelist still vulnerable to VPN-based attacks.

- **Azure Firewall**: Control egress traffic from AKS
  - **Rationale**: Centralized egress control, visibility into all outbound connections, DPI for threat detection. Whitelist approach prevents data exfiltration to unauthorized endpoints. Application rules by FQDN (e.g., allow *.docker.io, *.azurecr.io). Network rules by IP for Azure services. Logs all blocked attempts (security audit). Cost: ~$1200/month for firewall + $0.016/GB processed. Alternative: NSG rules cheaper but no FQDN filtering or DPI.
  - Whitelist necessary endpoints (Docker Hub, ACR, Azure services)
    - **Rationale**: Principle of least privilege applied to egress. Explicit allow for: ACR pull images, Azure AD auth, NTP time sync, Azure DNS, Ubuntu/apt updates. Blocks cryptocurrency miners, C2 channels, data exfiltration. Weekly review of blocked traffic logs identifies legitimate needs vs. threats.
  - Block all other outbound traffic
    - **Rationale**: Default deny egress. Forces teams to justify every external dependency, creates visibility into supply chain. Prevents "shadow" external services, license compliance issues. In practice, 95% of applications need <10 external FQDNs - manageable whitelist.

### 4.2 Data Security & Encryption

**Encryption at Rest:**
- **Azure Disk Encryption**: All PVs encrypted with AES-256
- **PostgreSQL**: Transparent Data Encryption (TDE) enabled
- **Blob Storage**: SSE with customer-managed keys in Key Vault
- **ETCD Encryption**: AKS encrypts secrets at rest by default

**Encryption in Transit:**
- **TLS 1.2/1.3**: Enforced on all communication
  - Application Gateway → NGINX Ingress (TLS)
  - NGINX Ingress → Backend pods (TLS with self-signed certs)
  - Backend → PostgreSQL (SSL mode=require)
- **Service Mesh mTLS**: Mutual TLS between all pods (if using Istio)
- **Certificate Rotation**: Automated via cert-manager

**Secrets Encryption:**
- **Key Vault Integration**: All secrets stored in Azure Key Vault
- **Bring Your Own Key (BYOK)**: Customer-managed encryption keys
- **Key Rotation**: Automated 90-day rotation policy
- **Audit Logging**: All secret access logged to Log Analytics

### 4.3 Container Security

**Image Scanning:**
- **Microsoft Defender for Containers**: Continuous vulnerability scanning
- **Admission Controller**: Block images with HIGH/CRITICAL CVEs
- **Quarantine Workflow**: Scan in ACR before allowing pulls
- **SBOM Generation**: Software Bill of Materials for compliance

**Runtime Security:**
- **Azure Policy for AKS**: Enforce security policies
  - Require resource limits on all containers
  - Block privileged containers (except GPU drivers)
  - Enforce read-only root filesystem where possible
  - Block host network/PID/IPC namespace usage
- **Pod Security Standards**: Restricted profile for most workloads
- **Seccomp/AppArmor Profiles**: Default deny syscalls

**Image Best Practices:**
- Non-root user execution (UID > 1000)
- Minimal base images (distroless, Alpine)
- No secrets in image layers
- Signed images with Notary/Cosign

### 4.4 Compliance & Auditing

**Compliance Frameworks:**
- **Azure Policy**: Apply compliance policies
  - CIS Kubernetes Benchmark
  - PCI-DSS (if handling payment data)
  - HIPAA (if handling health data)
  - SOC 2 requirements
- **Microsoft Defender for Cloud**: Continuous compliance assessment
- **Azure Security Center**: Security posture management

**Audit Logging:**
- **AKS Audit Logs**: All Kubernetes API calls logged
  - Sent to Log Analytics Workspace
  - Retention: 2 years for compliance
- **Azure Activity Logs**: All control plane operations
- **Application Logs**: Structured JSON with correlation IDs
- **Database Audit Logs**: All queries and connections logged

**Threat Detection:**
- **Microsoft Defender for Containers**: Runtime threat detection
  - Suspicious process execution
  - Privilege escalation attempts
  - Reverse shell detection
- **Azure Sentinel**: SIEM integration for security analytics
- **Alerts**: Real-time notifications for security events

**Secrets Scanning:**
- **GitHub Secret Scanning**: In source code repositories
- **Pre-commit Hooks**: Prevent secrets from being committed
- **Periodic Scans**: Detect hardcoded credentials in images

### 4.5 Network Security Deep Dive

**Defense in Depth Layers:**

1. **Perimeter Security**:
   - Azure DDoS Protection Standard on public IPs
   - Application Gateway WAF (OWASP Core Rule Set 3.2)
   - Geo-filtering (block high-risk countries if applicable)

2. **Ingress Security**:
   - NGINX Ingress with ModSecurity WAF module
   - Rate limiting (10 req/sec per IP for LLM endpoints)
   - Request size limits (prevent DoS)

3. **Service-to-Service**:
   - Network policies (Calico) with default deny
   - Service mesh mTLS (Istio/Linkerd)
   - Private DNS zones for internal resolution

4. **Egress Security**:
   - Azure Firewall for outbound traffic control
   - User-Defined Routes (UDR) to force traffic through firewall
   - Whitelisting external dependencies only

5. **Data Plane Security**:
   - Private endpoints for PostgreSQL (no public internet)
   - VNet service endpoints for Azure Storage
   - Disable public access on ACR

---

## 5. Observability & Monitoring Strategy

### 5.1 Monitoring Stack

**Azure Monitor & Log Analytics:**
- **Container Insights**: Pre-configured monitoring for AKS
  - Node and pod metrics (CPU, memory, disk, network)
  - Container logs aggregation
  - Live container logs and events
  - Performance charts and workbooks
- **Log Analytics Workspace**: Centralized log storage
  - 90-day retention for hot data
  - Archive to Blob for long-term (2 years)
- **Azure Monitor Metrics**: Time-series metrics database
  - Custom metrics from applications
  - Prometheus metrics scraping

**Prometheus & Grafana Stack (Alternative/Supplement):**
- **Prometheus**: Metrics collection and storage
  - Scrape Kubernetes metrics
  - Application custom metrics (FastAPI, Ollama)
  - GPU metrics from NVIDIA DCGM Exporter
- **Grafana**: Visualization dashboards
  - Pre-built Kubernetes dashboards
  - Custom LLM performance dashboards
  - Alert visualization
- **Thanos/Cortex**: Long-term metrics storage (optional)

### 5.2 Logging Architecture

**Centralized Logging:**
- **Fluent Bit DaemonSet**: Log collection from all nodes
  - Low resource footprint
  - Filters and parsers for structured logs
- **Destination**: Azure Log Analytics or Elasticsearch
- **Log Structure**:
  - JSON format with standard fields (timestamp, level, service, trace_id)
  - Correlation IDs for request tracing
  - No sensitive data in logs (scrubbing patterns)

**Log Categories:**
- **Application Logs**: FastAPI, Ollama, Frontend
- **Infrastructure Logs**: Kubernetes events, node logs
- **Audit Logs**: RBAC actions, resource modifications
- **Security Logs**: Failed auth, policy violations

**Retention & Archival:**
- **Hot Storage**: 30 days in Log Analytics
- **Warm Storage**: 90 days in Azure Blob (Cool tier)
- **Cold Storage**: 2 years in Azure Blob (Archive tier)
- **Automatic Lifecycle Policies**: Transition between tiers

### 5.3 Distributed Tracing

**Azure Application Insights:**
- **Auto-instrumentation**: For Python and JavaScript
- **Distributed Tracing**: End-to-end request tracking
  - Frontend → Backend → Ollama → Database
- **Dependency Tracking**: External calls and latencies
- **Performance Profiling**: Slow query detection

**OpenTelemetry (Alternative):**
- **OTEL Collector**: Collect traces, metrics, logs
- **Jaeger/Tempo**: Trace storage and visualization
- **Instrumentation**: Python SDK in FastAPI

### 5.4 Alerting Strategy

**Critical Alerts (PagerDuty/Opsgenie Integration):**
- **Cluster Health**:
  - Node NotReady > 5 minutes
  - Pod CrashLoopBackOff > 3 restarts
  - PersistentVolume claim pending > 10 minutes
- **Application Health**:
  - Backend API error rate > 5%
  - Average response time > 2 seconds
  - Ollama service unavailable
- **Security**:
  - Unauthorized API access attempts
  - Certificate expiration < 7 days
  - Suspicious container activity

**Warning Alerts (Email/Slack):**
- CPU/Memory utilization > 80%
- Disk usage > 85%
- Database connection pool saturation
- Backup failures

**Alert Routing:**
- **Severity P1**: Immediate page (5-minute acknowledgment SLA)
- **Severity P2**: Email + Slack (30-minute response)
- **Severity P3**: Ticket creation (next business day)

### 5.5 Custom Metrics & KPIs

**Application-Specific Metrics:**
- **LLM Performance**:
  - Request latency percentiles (p50, p95, p99)
  - Tokens per second throughput
  - Model inference time
  - Queue depth for Ollama requests
- **Business Metrics**:
  - Conversations per hour
  - Active users (DAU/MAU)
  - Model usage distribution
  - Error rates by endpoint

**GPU Metrics:**
- **NVIDIA DCGM Exporter**: GPU utilization, temperature, memory
- **Cost Tracking**: GPU hours consumed
- **Efficiency**: GPU utilization vs. idle time

**Dashboard Examples:**
- **Executive Dashboard**: Business metrics, uptime, costs
- **Platform Dashboard**: Cluster health, node status, resource usage
- **Application Dashboard**: Request rates, latencies, error rates
- **GPU Dashboard**: Utilization, queue depth, inference times

---

## 6. DevOps & CI/CD Strategy

### 6.1 GitOps Methodology

**Git as Single Source of Truth:**
- **Infrastructure Repository**: Terraform/Bicep for Azure resources
- **Application Repository**: Application source code
- **Configuration Repository**: Kubernetes manifests, Helm charts
- **Rationale**: Separation of concerns - infrastructure vs. application vs. config enables different review processes and access controls. Infrastructure changes infrequent (quarterly), reviewed by platform team. Application changes daily, reviewed by dev team. Config changes (replicas, env vars) as-needed, reviewed by ops. Alternative: Monorepo considered but multi-repo provides better RBAC granularity and CI/CD performance (smaller clone sizes).

**GitOps Tools:**
- **Flux CD or ArgoCD**: Continuous deployment
  - **Rationale**: GitOps pattern preferred over imperative CI/CD (Jenkins kubectl apply) for declarative state management, automatic drift correction, and audit trail in Git history. Every production change is a Git commit - full traceability, easy rollback (git revert). Self-healing - manual kubectl changes auto-corrected to Git state. ArgoCD chosen for better UI (helpful for less Kubernetes-savvy teams), built-in RBAC, and App-of-Apps pattern for multi-environment. Flux alternative is lighter (YAML-only, no UI) for GitOps purists. Both CNCF projects with strong communities.
  
  - Auto-sync from Git to cluster
    - **Rationale**: Automated reconciliation (every 3 minutes) eliminates manual deployment steps, reduces human error, ensures Git always matches cluster state. Disabled for production initially (manual sync approval), enabled after confidence built. Alternative: Manual sync button preserves control while maintaining GitOps benefits.
  
  - Rollback capabilities
    - **Rationale**: One-click rollback to any previous Git commit (vs. complex kubectl commands, finding old image tags). Full deployment history in ArgoCD UI. Rollback = git revert + sync, simple and auditable. Tested rollback procedures reduce MTTR from 30+ minutes to <5 minutes.
  
  - Drift detection and reconciliation
    - **Rationale**: Detects manual kubectl changes ("hotfixes"), highlights diff between Git and cluster. Auto-correction prevents configuration drift - cluster never deviates from Git source of truth. Critical for compliance (prove production state matches reviewed config). Alternative: Manual drift detection via kubectl diff requires discipline and tooling.
  
  - Multi-environment management (staging, prod)
    - **Rationale**: Single ArgoCD instance manages both staging and prod (different clusters), unified deployment view. Kustomize overlays per environment (staging has lower replicas, different URLs). Promotes same manifests from staging to prod (change only overlay values), reduces environment inconsistency bugs.

**Branch Strategy:**
- `main`: Production deployments
- `staging`: Staging environment
- `feature/*`: Feature branches (ephemeral environments)

### 6.2 CI/CD Pipeline

**Continuous Integration (GitHub Actions/Azure DevOps):**

**Build Stage:**
1. Code checkout
2. Run linters (flake8, ESLint)
3. Run unit tests (pytest, Vitest)
4. Security scanning (Bandit, npm audit)
5. Build Docker images (multi-arch support)
6. Scan images for vulnerabilities
7. Push to ACR (with semantic versioning tags)
8. Sign images (Cosign/Notary)

**Continuous Deployment:**

**Staging Deployment:**
1. Update Kubernetes manifests with new image tags
2. Commit to staging branch
3. GitOps tool (Flux/ArgoCD) detects change
4. Apply manifests to staging cluster
5. Run integration tests
6. Run smoke tests
7. Run security tests (OWASP ZAP)

**Production Deployment:**
1. Manual approval gate (via pull request)
2. Merge to main branch
3. GitOps deploys to production
4. Progressive delivery (canary/blue-green)
5. Automated rollback on failure
6. Post-deployment verification tests

**Deployment Strategies:**
- **Canary Deployment**: 10% → 50% → 100% traffic shift
  - **Rationale**: Phased rollout reduces blast radius of bugs - only 10% of users affected if error rates spike. Automated promotion based on SLO metrics (error rate <1%, latency p95 <500ms) removes human bottleneck. Flagger tool integrates with Istio/NGINX for traffic shifting, Prometheus for metrics analysis. 10% for 10 minutes validates basic functionality, 50% for 30 minutes catches moderate load issues, 100% after passing all checks. Alternative: Blue-green (instant 100% switch) rejected for backend due to higher risk. Trade-off: Canary adds 40+ minutes to deployment time vs. immediate rollout.
  - Automated promotion based on error rates
    - **Rationale**: SLO-based promotion (not time-based) prevents bad deployments from auto-promoting. If error rate >1% or latency >500ms at any phase, automatic rollback. Removes emotion from rollback decision. Alternative: Manual approval at each phase provides human oversight but slows deployment and requires on-call availability.
  - Flagger for progressive delivery
    - **Rationale**: Flagger automates traffic shifting, metrics analysis, and rollback decision. Integrates with service mesh (Istio) or ingress (NGINX) for weighted routing. Kubernetes-native (CRD-based), declarative config. Alternative: Custom scripts fragile and hard to maintain. Spinnaker too heavyweight for our scale.

- **Blue-Green Deployment**: For database migrations
  - **Rationale**: Database migrations require special handling - cannot canary a schema change. Blue-green deploys new version (green) alongside old (blue) using same database (forward-compatible migrations). Validation on green environment before traffic switch. Instant rollback (switch back to blue) if issues detected. Zero downtime for users. Alternative: Maintenance window rejected as 24/7 global service. Trade-off: Requires 2x resources during migration (15-30 minutes).
  - Zero-downtime schema changes
    - **Rationale**: Expand-contract pattern for schema changes - Step 1: Add new column/table (backward compatible), deploy green. Step 2: Dual-write to old and new schema, validate. Step 3: Migrate data, switch reads to new schema. Step 4: Remove old schema (next deployment). Allows instant rollback at any step. Industry best practice for high-availability systems.

- **Rolling Update**: Default for stateless services
  - **Rationale**: Rolling update sufficient for low-risk changes (frontend static assets, config changes). Gradual pod replacement (maxUnavailable=1, maxSurge=1) ensures continuous availability. Fast deployment (2-3 minutes for full rollout). PDB ensures minimum pods available. Simpler than canary, no service mesh required. Use for changes with high confidence (tested in staging, no backend logic changes).

### 6.3 Environment Management

**Environment Separation:**
- **Development**: Local Kubernetes (Kind/Minikube) or shared dev cluster
- **Staging**: Dedicated AKS cluster (smaller node pools)
- **Production**: Full HA AKS cluster

**Environment Parity:**
- Use same container images across environments
- Environment-specific configuration via Kustomize overlays
- Infrastructure as Code for consistency

### 6.4 Testing Strategy

**Test Pyramid:**

**Unit Tests:**
- Python: pytest with coverage > 80%
- JavaScript: Vitest/Jest
- Run in CI pipeline (fast feedback)

**Integration Tests:**
- API contract tests (backend ↔ Ollama)
- Database integration tests (against test DB)
- Run in CI and staging deployment

**End-to-End Tests:**
- Playwright/Cypress for frontend workflows
- API workflow tests (full council process)
- Run in staging environment post-deployment

**Performance Tests:**
- Load testing with k6 or Locust
- Stress testing GPU inference
- Run weekly in staging
- Benchmarks for regression detection

**Security Tests:**
- OWASP ZAP for vulnerability scanning
- Penetration testing quarterly
- Dependency scanning (Dependabot, Snyk)

**Chaos Engineering:**
- Chaos Mesh or Litmus for resilience testing
- Kill pods randomly (test HPA, PDB)
- Network latency injection
- Node failure simulation

---

## 7. Cost Optimization Strategy

### 7.1 Compute Optimization

**GPU Cost Management:**
- **Spot Instances**: Use Azure Spot VMs for GPU nodes (70-90% savings)
  - **Rationale**: T4 Spot VMs cost ~$0.22/hr vs. $0.90/hr regular (75% savings), ~$6000/year saved per GPU node. Eviction risk low for T4 (5-10% monthly vs. 30%+ for high-demand A100). Acceptable for stateless inference - evicted pod reschedules to fallback node in ~2 minutes. Request queue buffers during failover. NOT suitable for training workloads (long-running, checkpointing complexity). Right-sized spot capacity pool (3x AZs) reduces eviction correlation.
  
  - Configure eviction policies
    - **Rationale**: Azure provides 30-second eviction notice. terminationGracePeriodSeconds=30 allows pod to finish in-flight requests, drain connections gracefully. PreStop hook sends SIGTERM to Ollama, waits for active inferences to complete (timeout 25s). Prevents request failures during eviction. Alternative: Immediate termination causes 429 errors for active requests.
  
  - Graceful pod shutdown handlers
    - **Rationale**: PreStop lifecycle hook implements graceful shutdown - stop accepting new requests, complete in-flight requests (or return 503), flush logs, close DB connections. Health check fails during PreStop (removes pod from load balancer within 5s). Reduces user-facing errors from <5% to <0.1% during evictions. Alternative: No handler causes abrupt termination, partial responses, data loss.
  
  - Fallback to regular instances on eviction
    - **Rationale**: Mixed node pool (2 Spot + 1 regular instance) ensures capacity. If both Spot nodes evicted simultaneously (rare), pod reschedules to regular instance automatically. Cluster autoscaler prioritizes Spot (lower cost) but maintains regular instance for reliability. Costs: 2x Spot ($12/day) + 1x regular ($22/day) = $34/day vs. 3x regular ($66/day), saves $960/month.

- **Scheduled Scaling**: Scale down GPU nodes during off-hours
  - **Rationale**: Usage patterns show 80% of traffic 8am-11pm local time, <20% overnight. Scaling to 0 GPU pods midnight-6am saves 25% of GPU costs (~$200/month per node). Implemented via CronJob setting Ollama replicas=0, or KEDA schedule-based scaler. Trade-off: 10-15 min cold start when first morning request arrives (model download). Mitigated by min 1 replica during business hours.
  - Use KEDA or cron-based HPA
    - **Rationale**: KEDA ScaledObject with cron trigger more reliable than CronJob (declarative state vs. imperative scaling commands). Scales based on schedule AND queue depth (weekend traffic spike handled automatically). Alternative: CronJob simpler but less flexible, requires manual intervention for off-schedule demand.
  - Reduce to 0 replicas overnight (if acceptable)
    - **Rationale**: 0 replicas acceptable for US-based users (low overnight traffic). International users experience degraded performance during scale-up (queue requests for 10-15 min). Decision: Acceptable for Phase 1, revisit if >10% users outside US timezone. Alternative: Follow-the-sun approach with multi-region deployment keeps 1 replica always warm.

- **Right-sizing**: Start with smaller GPUs (T4) before A100/H100
  - **Rationale**: T4 sufficient for LLaMA-2 7B/13B models (16GB VRAM). Cost: $0.90/hr vs. $3.20/hr A100 (3.5x cheaper). Throughput: T4 = 15 tokens/sec, A100 = 40 tokens/sec (2.7x faster). Business case: 15 tokens/sec meets latency SLO (<5s for 75-token response) at current scale (<100 concurrent users). A100 justified only when >300 concurrent users or larger models (70B+). Start lean, scale up based on measured need vs. premature optimization.

**Node Pool Optimization:**
- **Cluster Autoscaler**: Aggressive scale-down policies
- **Burstable VMs**: Use B-series for low-traffic services
- **Reserved Instances**: Commit to 1-3 year for predictable workloads (40% savings)

### 7.2 Storage Optimization

**Disk Management:**
- **Standard SSD**: For non-critical workloads (dev/test)
- **Premium SSD**: Production only
- **Disk Snapshots**: Incremental snapshots (reduce storage costs)
- **Orphaned Disk Cleanup**: Automated detection and removal

**Blob Storage:**
- **Lifecycle Policies**: Auto-transition to Cool/Archive tiers
- **Compression**: Enable for logs and backups
- **Deduplication**: For backup storage

### 7.3 Monitoring Costs

**Cost Visibility:**
- **Azure Cost Management**: Tag-based cost allocation
  - Tag by environment, team, application
- **Kubecost**: Kubernetes-native cost monitoring
  - Per-namespace cost breakdown
  - Right-sizing recommendations
- **Budget Alerts**: Notify when costs exceed thresholds

**Optimization Actions:**
- Monthly cost review meetings
- Identify unused resources (orphaned disks, idle load balancers)
- Right-size over-provisioned resources

### 7.4 Estimated Monthly Costs (Azure East US 2)

**Production Environment:**
- **AKS Control Plane**: Free (managed by Azure)
- **System Node Pool** (3x Standard_D4s_v3): ~$500
- **Application Node Pool** (avg 4x Standard_D8s_v3): ~$1,400
- **GPU Node Pool** (1x Standard_NC6s_v3 Spot): ~$250 (vs. ~$900 regular)
- **PostgreSQL Flexible Server** (Zone-redundant, 8 vCores): ~$450
- **Storage** (Disks, Blob, Files): ~$300
- **Application Gateway v2**: ~$300
- **Log Analytics** (100GB ingestion): ~$250
- **Bandwidth** (1TB egress): ~$90
- **ACR Premium**: ~$50
- **Key Vault**: ~$10
- **Backup Storage**: ~$50

**Total Estimated**: ~$3,650/month (with Spot GPU)
**Without Spot**: ~$4,300/month

**Staging Environment** (smaller scale): ~$1,200/month
**Total with Staging**: ~$4,850/month

---

## 8. Implementation Roadmap

### Phase 1: Foundation (Week 1-2)

**Week 1: Azure Environment Setup**
- Create Azure subscription and resource groups
- Setup Azure AD groups and RBAC
- Provision VNet with subnets
- Deploy Azure Bastion for secure access
- Create Key Vault for secrets management
- Setup Log Analytics Workspace
- Deploy ACR with security scanning

**Week 2: AKS Cluster Deployment**
- Deploy AKS cluster with node pools
- Configure Azure AD integration
- Install CSI drivers (Key Vault, Azure Disk)
- Deploy NGINX Ingress Controller
- Setup cert-manager for TLS
- Configure cluster autoscaler
- Deploy monitoring agents (Container Insights)

### Phase 2: Data & Networking (Week 3)

- Provision Azure Database for PostgreSQL
- Configure VNet integration and private endpoints
- Setup database backups and HA
- Run database migrations
- Deploy Application Gateway with WAF
- Configure DNS and SSL certificates
- Implement network policies

### Phase 3: Application Deployment (Week 4-5)

**Week 4: Backend & Ollama**
- Build and push container images to ACR
- Create Kubernetes manifests (Deployments, Services)
- Deploy backend API with HPA
- Deploy Ollama StatefulSet with GPU
- Configure secrets from Key Vault
- Setup service-to-service communication
- Verify health checks and liveness probes

**Week 5: Frontend & Integration**
- Deploy frontend application
- Configure ingress routing
- End-to-end integration testing
- Performance baseline testing
- Load testing with k6

### Phase 4: Observability (Week 6)

- Configure Prometheus and Grafana (if using)
- Create custom dashboards
- Setup distributed tracing (Application Insights)
- Configure alerting rules
- Integrate PagerDuty/Opsgenie
- Create runbooks for common incidents
- Document monitoring procedures

### Phase 5: Security Hardening (Week 7)

- Implement network policies (deny-all baseline)
- Enable Azure Policy for AKS
- Configure pod security standards
- Setup Microsoft Defender for Containers
- Vulnerability scanning automation
- Secrets rotation testing
- Security audit and penetration testing prep

### Phase 6: CI/CD & GitOps (Week 8)

- Setup GitHub Actions or Azure DevOps pipelines
- Implement GitOps with Flux/ArgoCD
- Configure staging environment
- Automate testing in pipeline
- Setup approval gates for production
- Implement canary deployment strategy
- Document deployment procedures

### Phase 7: Testing & Validation (Week 9-10)

**Week 9: Testing**
- Run comprehensive integration tests
- Execute load tests (target 1000 concurrent users)
- Chaos engineering experiments
- Failover testing (database, node failures)
- Security testing (OWASP ZAP, penetration tests)

**Week 10: Optimization & Tuning**
- Performance optimization based on test results
- Right-size resource requests/limits
- Tune autoscaling parameters
- Database query optimization
- Cost optimization review

### Phase 8: Production Readiness (Week 11-12)

**Week 11: Documentation & Training**
- Operational runbooks
- Disaster recovery procedures
- Incident response playbooks
- Developer onboarding guides
- Architecture diagrams (C4 model)

**Week 12: Go-Live Preparation**
- Final security review
- Compliance checklist verification
- Backup and restore validation
- DR failover drill
- Go-live checklist completion
- Production cutover plan

### Phase 9: Production Launch (Week 13)

- Blue-green cutover to production
- Monitor metrics closely (24/7 for first week)
- Hypercare period (dedicated team)
- Quick response to issues
- Post-launch review meeting

### Phase 10: Post-Launch (Week 14+)

- Continuous monitoring and optimization
- Implement feedback from production usage
- Plan for multi-region expansion (if needed)
- Regular security patching schedule
- Quarterly DR drills
- Monthly cost reviews

---

## 9. Risk Management & Mitigation

### 9.1 Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| GPU node eviction (Spot) | High | Medium | Fallback to regular instances, queue system |
| Ollama model loading time | Medium | High | Pre-warm pods, readiness probe delays |
| Database connection exhaustion | High | Low | Connection pooling, PgBouncer |
| TLS certificate expiration | High | Low | Automated renewal via cert-manager, monitoring |
| AKS version end-of-life | Medium | High | Quarterly upgrade schedule, testing |
| Container image vulnerabilities | Medium | Medium | Automated scanning, admission controller |
| Network policy misconfiguration | High | Medium | IaC testing, peer reviews |

### 9.2 Operational Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Insufficient monitoring coverage | High | Medium | Comprehensive dashboard reviews |
| Lack of runbooks | Medium | High | Document incidents as runbooks |
| Team knowledge gaps | Medium | Medium | Training programs, documentation |
| Deployment failures | High | Low | Canary deployments, automated rollback |
| Cost overruns | Medium | Medium | Budget alerts, weekly reviews |

### 9.3 Security Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Unauthorized cluster access | Critical | Low | Azure AD, RBAC, audit logging |
| Data breach | Critical | Low | Encryption, network policies, WAF |
| DDoS attack | High | Medium | Azure DDoS Protection, rate limiting |
| Supply chain attacks | High | Low | Image signing, SBOM, vulnerability scanning |
| Insider threats | High | Low | Audit logging, least privilege, JIT access |

---

## 10. Success Criteria & KPIs

### 10.1 Availability Metrics

- **System Uptime**: 99.9% (43 minutes downtime/month)
- **API Availability**: 99.95%
- **Database Availability**: 99.99% (zone-redundant)

### 10.2 Performance Metrics

- **API Response Time**: p95 < 500ms (excluding LLM inference)
- **LLM Inference Latency**: p95 < 5 seconds
- **Frontend Load Time**: p95 < 2 seconds
- **Database Query Time**: p95 < 100ms

### 10.3 Security Metrics

- **Mean Time to Patch (MTTP)**: Critical CVEs patched within 48 hours
- **Security Incidents**: Zero unauthorized access events
- **Failed Login Attempts**: < 1% of total attempts
- **TLS Coverage**: 100% of inter-service communication

### 10.4 Operational Metrics

- **Mean Time to Detect (MTTD)**: < 5 minutes for critical issues
- **Mean Time to Resolve (MTTR)**: < 30 minutes for P1 incidents
- **Deployment Frequency**: Daily to staging, weekly to production
- **Change Failure Rate**: < 5%
- **Rollback Success Rate**: 100%

### 10.5 Cost Metrics

- **Cost per Request**: Track and optimize over time
- **GPU Utilization**: > 60% average
- **Reserved Instance Coverage**: > 70% for predictable workloads
- **Cost Variance**: Stay within ±10% of budget

---

## 11. Governance & Compliance

### 11.1 Change Management

- **Change Advisory Board (CAB)**: Weekly reviews for production changes
- **Change Windows**: Scheduled maintenance windows (e.g., Saturday 2-4 AM)
- **Emergency Changes**: Documented process with post-mortem
- **Rollback Plan**: Required for all production changes

### 11.2 Compliance Requirements

**Data Residency:**
- All data stored in specified Azure region
- No cross-border data transfers without encryption
- Geo-fencing via Azure Policy

**Audit Trail:**
- All changes logged with user identity
- 2-year retention for audit logs
- Immutable audit logs in Azure Blob

**Access Reviews:**
- Quarterly access certification
- Annual role recertification
- Automated removal of inactive accounts

### 11.3 Documentation Standards

- Architecture Decision Records (ADRs) for major decisions
- API documentation (OpenAPI/Swagger)
- Runbooks for all operational procedures
- Incident post-mortems (blameless culture)

---

## 12. Next Steps & Decision Points

### Critical Decisions Required:

1. **Budget Approval**: Confirm $4,850/month budget (prod + staging)
2. **Region Selection**: East US 2 (primary) + West US 2 (DR)?
3. **GPU Instance Type**: T4 (cost-effective) vs. A100 (high performance)?
4. **Monitoring Tool**: Azure Monitor only or hybrid with Prometheus/Grafana?
5. **Service Mesh**: Deploy Istio/Linkerd or rely on AKS native features?
6. **Multi-Region**: Phase 1 single-region or immediate multi-region?
7. **Compliance Requirements**: Any specific frameworks (HIPAA, PCI-DSS)?

### Recommended First Actions:

1. **Stakeholder Alignment**: Present strategy to leadership for approval
2. **Team Formation**: Assign platform team (2-3 engineers)
3. **Azure Subscription**: Provision with appropriate quotas
4. **Pilot Phase**: Deploy to staging environment first (Week 1-8)
5. **Security Review**: Engage security team early for requirements
6. **Training Plan**: Kubernetes and Azure training for team

---

## References

- **Source Repository**: https://github.com/vanisa01/circle-of-trust
- **AKS Documentation**: https://docs.microsoft.com/azure/aks/
- **Azure Architecture Center**: https://docs.microsoft.com/azure/architecture/
- **Kubernetes Best Practices**: https://kubernetes.io/docs/concepts/
