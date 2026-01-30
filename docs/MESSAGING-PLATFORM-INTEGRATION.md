# Circle of Trust - Messaging Platform Integration Architecture

**Project**: Circle of Trust (LLM Council) - Bot Deployment  
**Target Platforms**: Microsoft Teams, Slack, Telegram  
**Environment**: Private Cloud (AKS) → Public Communication Services  
**Date**: January 30, 2026  
**Status**: Architecture Design

---

## Executive Summary

Deploy the Circle of Trust agentic LLM solution as an intelligent bot on Microsoft Teams, Slack, and Telegram while maintaining security compliance for a private cloud environment. This architecture addresses the challenge of connecting isolated AKS infrastructure to public SaaS platforms using Azure-native hybrid connectivity patterns, secure API gateways, and event-driven messaging.

**Key Challenges:**
- ✅ Private AKS cluster with no direct internet access
- ✅ Secure outbound communication to external APIs
- ✅ Webhook ingress from public services
- ✅ Compliance with network policies and security controls
- ✅ Multi-platform support (Teams/Slack/Telegram)
- ✅ High availability and fault tolerance

---

## 1. Architecture Overview

### 1.1 Connectivity Patterns

**Challenge**: Private AKS cluster needs bidirectional communication with public SaaS platforms:
- **Outbound**: Bot sends messages to Teams/Slack/Telegram APIs
- **Inbound**: Platforms send user messages/events via webhooks

**Solution**: Hybrid architecture combining multiple Azure services

```
┌─────────────────────────────────────────────────────────────────┐
│                    Public Internet                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                      │
│  │ MS Teams │  │  Slack   │  │ Telegram │                      │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘                      │
│        │             │             │                            │
│        └─────────────┴─────────────┘                            │
│                      │                                           │
└──────────────────────┼───────────────────────────────────────────┘
                       │
                       │ Webhooks (HTTPS)
                       │
            ┌──────────▼──────────┐
            │  Azure Front Door   │ ◄─── WAF, DDoS Protection
            │   + API Management  │      SSL Termination
            └──────────┬──────────┘      Rate Limiting
                       │
                       │ Internal
                       │
            ┌──────────▼──────────────────────────────────┐
            │   Application Gateway (Internal)            │
            └──────────┬──────────────────────────────────┘
                       │
            ┌──────────▼──────────────────────────────────┐
            │   Private AKS Cluster (VNet)                │
            │  ┌────────────────────────────────────┐     │
            │  │  Bot Adapter Service (Pod)         │     │
            │  │  - Webhook receiver                │     │
            │  │  - Message normalization           │     │
            │  │  - Platform abstraction            │     │
            │  └────────┬───────────────────────────┘     │
            │           │                                  │
            │  ┌────────▼───────────────────────────┐     │
            │  │  Circle Backend (Existing)         │     │
            │  │  - LLM orchestration               │     │
            │  │  - Council voting logic            │     │
            │  └────────┬───────────────────────────┘     │
            │           │                                  │
            │  ┌────────▼───────────────────────────┐     │
            │  │  Ollama StatefulSet (GPU)          │     │
            │  │  - LLaMA-2 models                  │     │
            │  └────────────────────────────────────┘     │
            │                                              │
            └──────────────┬───────────────────────────────┘
                           │
                           │ Outbound via Firewall
                           │
            ┌──────────────▼───────────────┐
            │   Azure Firewall             │
            │   - FQDN filtering           │
            │   - Allowlist external APIs: │
            │     • *.teams.microsoft.com  │
            │     • slack.com/api/*        │
            │     • api.telegram.org       │
            └──────────────┬───────────────┘
                           │
                           │ HTTPS
                           │
            ┌──────────────▼───────────────┐
            │  External API Endpoints      │
            │  - Send messages             │
            │  - Update bot status         │
            │  - File uploads              │
            └──────────────────────────────┘
```

### 1.2 Component Responsibilities

**Bot Adapter Service** (New Component)
- Receives webhooks from messaging platforms
- Normalizes events into common format
- Authenticates/validates webhook signatures
- Routes to Circle backend
- Formats responses per platform API spec
- Handles retries and rate limiting
- **Rationale**: Decouples Circle backend from platform-specific protocols, enables multi-platform support with single orchestration layer, simplifies testing with mock adapters

**Azure Front Door + API Management**
- Public endpoint for webhooks (HTTPS)
- WAF protection against malicious payloads
- DDoS protection
- API key validation
- Rate limiting per platform
- Request logging and analytics
- **Rationale**: Front Door provides global edge network (low latency for international webhook delivery), API Management adds policy enforcement, request transformation, and developer portal for bot API documentation

**Azure Firewall**
- Whitelists outbound FQDN for each platform
- Blocks all other egress
- Logs all API calls for audit
- **Rationale**: Allows private AKS to call external APIs while maintaining strict egress control, prevents data exfiltration, compliance requirement for regulated industries

---

## 2. Platform-Specific Integration

### 2.1 Microsoft Teams Bot

**Integration Pattern**: Azure Bot Service with Bot Framework SDK

**Architecture:**
```
MS Teams Client
    ↓ User message
MS Teams Service (Graph API)
    ↓ Webhook POST
Azure Front Door (*.azurefd.net)
    ↓
API Management (/api/teams/webhook)
    ↓ Validate JWT token
Bot Adapter Service (Pod)
    ↓ Extract message, user context
Circle Backend
    ↓ LLM inference
Ollama (GPU)
    ↓ Response
Bot Adapter
    ↓ Format as Adaptive Card
Microsoft Graph API (https://graph.microsoft.com)
    ↓ POST /messages
MS Teams Client
```

**Implementation Details:**

**Azure Bot Service Setup:**
- Register bot in Azure Portal
- Bot Type: Multi-tenant (if serving multiple orgs) or Single-tenant
- Messaging endpoint: `https://your-frontdoor.azurefd.net/api/teams/webhook`
- OAuth connection for Graph API permissions
- **Rationale**: Azure Bot Service provides Microsoft-supported authentication, automatic token refresh, and compliance certifications (SOC 2, HIPAA). Alternative: Direct Graph API integration more complex, lacks built-in features.

**Required Scopes:**
```yaml
permissions:
  - ChannelMessage.Read.All      # Read channel messages
  - ChannelMessage.Send         # Send messages to channels
  - ChatMessage.Read            # Read 1:1 chat messages
  - ChatMessage.Send            # Send 1:1 messages
  - Files.Read.All              # Read uploaded files
  - User.Read.All               # Get user profiles
```

**Webhook Security:**
- Validate JWT token in Authorization header
- Verify signature using Bot Framework secret
- Check originating tenant ID (if single-tenant)
- **Rationale**: Prevents unauthorized webhook submissions, replay attacks. Bot Framework validates Microsoft's signature, eliminates manual token verification complexity.

**Bot Adapter Deployment Configuration:**

**Key Settings:**
- **Replicas**: 3 for HA (auto-scaled 2-5 based on load)
- **Resources**: 200m CPU, 256Mi RAM (limits: 1 CPU, 512Mi)
- **Security**: Non-root user (UID 1000), read-only filesystem
- **Secrets**: Mounted from Key Vault via CSI driver
- **Health Checks**: Liveness/readiness probes on /health and /ready endpoints
- **Service**: ClusterIP type, port 80 → 8080

**Environment Variables:**
- `PLATFORM`: teams/slack/telegram
- `BOT_APP_ID` / `BOT_TOKEN`: Platform credentials (from secrets)
- `BACKEND_URL`: Circle backend service DNS
- `ENABLE_ADAPTIVE_CARDS`: Platform-specific features

> Full Kubernetes manifests available in `gitops/base/bots/` directory

**Message Flow:**

1. **Receive Webhook** (POST /api/teams/webhook)
   - Validate Bot Framework signature
   - Deserialize incoming activity
   - Extract message, user ID, conversation context

2. **Process Message**
   - Normalize to common format
   - Call Circle backend API
   - Await LLM response

3. **Send Response**
   - Format as Adaptive Card
   - Post via Graph API
   - Handle errors with retry logic

**Adaptive Card Response Format:**
- Header: "Circle of Trust Response"
- Metadata: Model name, confidence score, consensus
- Body: LLM response text
- Actions: Feedback buttons (👍/👎)

> Adaptive Cards provide rich interactive UI within Teams conversations

**Firewall Rules (Teams):**

| Rule | Source | Allowed FQDNs | Port | Purpose |
|------|--------|---------------|------|----------|
| teams-api | AKS VNet | graph.microsoft.com | 443 | Graph API calls |
| | | *.teams.microsoft.com | 443 | Teams services |
| | | login.microsoftonline.com | 443 | OAuth tokens |
| | | api.botframework.com | 443 | Bot Framework |

---

### 2.2 Slack Bot

**Integration Pattern**: Slack Events API + Web API

**Architecture:**
```
Slack Client
    ↓ User @mention
Slack Events API
    ↓ HTTP POST (event_callback)
Azure Front Door
    ↓
API Management (/api/slack/events)
    ↓ Verify request signature
Bot Adapter Service
    ↓ Parse event, extract message
Circle Backend
    ↓ LLM inference
Bot Adapter
    ↓ Format as Slack Block Kit
Slack Web API (https://slack.com/api/chat.postMessage)
    ↓ Bearer token auth
Slack Channel
```

**Implementation Details:**

**Slack App Configuration:**
- Create Slack App at api.slack.com
- Enable Events API with Request URL: `https://your-frontdoor.azurefd.net/api/slack/events`
- Subscribe to events:
  - `message.channels` (channel messages with @bot)
  - `message.im` (direct messages)
  - `app_mention` (explicit mentions)
- OAuth scopes:
  - `chat:write` (send messages)
  - `channels:history` (read channel history)
  - `im:history` (read DMs)
  - `files:read` (access uploaded files)
- **Rationale**: Events API provides real-time message delivery (vs. polling RTM API), supports granular scopes, and handles message deduplication. OAuth eliminates manual token management.

**Webhook Signature Validation:**
- Verify `X-Slack-Signature` header using HMAC-SHA256
- Check timestamp to prevent replay attacks (reject >5 min old)
- Compare signatures using constant-time comparison
- Return 403 if validation fails

**Bot Adapter Deployment (Slack):**
- Configuration identical to Teams adapter
- Platform-specific secrets: `SLACK_BOT_TOKEN`, `SLACK_SIGNING_SECRET`
- Same resource limits and scaling policy

**Event Handler Flow:**
1. Verify webhook signature
2. Handle URL verification challenge (initial setup)
3. Process `app_mention` events
4. Extract message (strip bot mention)
5. Call Circle backend
6. Send formatted response using Block Kit
7. Reply in thread to maintain context

**Block Kit Response:**
- Header block with bot name/icon
- Section with model metadata (side-by-side fields)
- Response text in markdown format
- Action buttons for feedback

> Block Kit allows rich formatting similar to Adaptive Cards in Teams

**Firewall Rules (Slack):**

| Rule | Allowed FQDNs | Purpose |
|------|---------------|----------|
| slack-api | slack.com, *.slack.com | Slack Web API |
| | files.slack.com | File uploads/downloads |

---

### 2.3 Telegram Bot

**Integration Pattern**: Telegram Bot API with Long Polling or Webhooks

**Architecture Options:**

**Option A: Webhook (Recommended for Production)**
```
Telegram Client
    ↓ User message
Telegram Bot API Servers
    ↓ HTTPS POST /bot<token>/webhook
Azure Front Door
    ↓
Bot Adapter Service
    ↓
Circle Backend
    ↓
Telegram Bot API (sendMessage)
```

**Option B: Long Polling (Development/Testing)**
```
Bot Adapter (Polling loop every 1s)
    ↓ GET /getUpdates
Telegram Bot API
    ↓ Return new messages
Bot Adapter
    ↓ Process locally
Circle Backend
```

**Rationale**: Webhook pattern preferred for production (lower latency, no polling overhead, scales better), but long polling useful for development (no public endpoint needed, simpler debugging). Long polling acceptable for low-traffic scenarios (<100 messages/hour).

**Implementation Details:**

**Bot Registration:**
- Talk to @BotFather on Telegram
- Create new bot, receive API token
- Set webhook: `https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://your-frontdoor.azurefd.net/api/telegram/webhook`
- **Rationale**: Telegram bots free, no approval process (vs. Teams/Slack), instant provisioning. Webhook URL must be HTTPS with valid certificate (Let's Encrypt acceptable).

**Webhook Secret Token:**
```bash
# Set secret token for webhook validation (Telegram Bot API 6.0+)
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=https://your-frontdoor.azurefd.net/api/telegram/webhook" \
  -d "secret_token=YOUR_RANDOM_SECRET_32CHARS"
```

**Bot Adapter Deployment (Telegram):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: telegram-bot-adapter
  namespace: circle-prod
spec:
  replicas: 2  # Lower than Teams/Slack (less traffic typically)
  selector:
    matchLabels:
      app: telegram-bot-adapter
  template:
    metadata:
      labels:
        app: telegram-bot-adapter
        platform: telegram
    spec:
      containers:
      - name: adapter
        image: circlerecristry.azurecr.io/telegram-bot-adapter:latest
        ports:
        - containerPort: 8080
        env:
        - name: PLATFORM
          value: "telegram"
        - name: TELEGRAM_BOT_TOKEN
          valueFrom:
            secretKeyRef:
              name: telegram-bot-credentials
              key: bot-token
        - name: TELEGRAM_WEBHOOK_SECRET
          valueFrom:
            secretKeyRef:
              name: telegram-bot-credentials
              key: webhook-secret
        - name: BACKEND_URL
          value: "http://circle-backend.circle-prod.svc.cluster.local:8001"
        resources:
          requests:
            cpu: 100m    # Lower than Teams/Slack
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

**Webhook Handler:**
```python
from telegram import Update, Bot
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, filters

class TelegramWebhookHandler:
    def __init__(self, bot_token: str, webhook_secret: str):
        self.bot = Bot(token=bot_token)
        self.webhook_secret = webhook_secret
    
    async def handle_webhook(self, request):
        # Validate secret token (X-Telegram-Bot-Api-Secret-Token header)
        if request.headers.get("X-Telegram-Bot-Api-Secret-Token") != self.webhook_secret:
            return {"error": "Unauthorized"}, 403
        
        # Parse update
        update_data = await request.json()
        update = Update.de_json(update_data, self.bot)
        
        # Process message
        if update.message:
            await self.handle_message(update.message)
        
        return {"ok": True}
    
    async def handle_message(self, message):
        # Extract text
        text = message.text
        user_id = message.from_user.id
        chat_id = message.chat_id
        
        # Call Circle backend
        response = await self.call_circle_backend(
            message=text,
            user_id=str(user_id),
            conversation_id=str(chat_id)
        )
        
        # Send response with formatting
        await self.bot.send_message(
            chat_id=chat_id,
            text=self.format_response(response),
            parse_mode="MarkdownV2",
            reply_to_message_id=message.message_id
        )
    
    def format_response(self, response: dict) -> str:
        return f"""
*🤖 Circle of Trust Response*

*Model:* LLaMA\\-2 13B
*Confidence:* {response['confidence']}%
*Consensus:* {response['consensus']}

{response['text']}

_Was this helpful? /feedback\\_positive or /feedback\\_negative_
"""
```

**Firewall Rules (Telegram):**

| Rule | Allowed FQDNs | Purpose |
|------|---------------|----------|
| telegram-api | api.telegram.org | Telegram Bot API |

---

## 3. Unified Bot Adapter Architecture

### 3.1 Multi-Platform Abstraction Layer

**Design Pattern**: Strategy pattern with platform-specific adapters

**BotAdapter Interface:**
- `validate_webhook()` - Verify signature/token
- `parse_message()` - Convert to normalized format
- `send_response()` - Format and send to platform

**Normalized Message Format:**
- `user_id` - Platform-agnostic identifier
- `conversation_id` - Channel/chat ID
- `text` - Message content
- `platform` - teams/slack/telegram
- `metadata` - Platform-specific data
- `attachments` - Files, images

**Factory Pattern:**
- Single factory creates correct adapter based on platform parameter
- Enables testing with mock adapters
- Simplifies adding new platforms

**Rationale**: Abstraction layer enables single Circle backend interface regardless of platform, simplifies testing with mock adapters, allows adding new platforms (Discord, WhatsApp) without backend changes. Alternative: Platform-specific backends would duplicate orchestration logic, harder to maintain consistency.

### 3.2 Shared Infrastructure Components

**API Management Policies:**

**Inbound:**
- Rate limiting: 100 calls/min per platform
- API key validation
- Request logging to Event Hub
- Route to internal backend

**Outbound:**
- Add correlation ID for tracing
- Response transformation if needed

**Error Handling:**
- Generic error messages (prevent information leakage)
- Log errors for debugging
- Return 500 for internal failures

**Secrets Management (Azure Key Vault):**

**CSI Secret Provider Configuration:**
- Provider: Azure Key Vault
- Authentication: Managed Identity (no credentials)
- Secrets mounted as Kubernetes Secrets

**Bot Secrets Stored in Key Vault:**
- **Teams**: `teams-bot-app-id`, `teams-bot-app-password`
- **Slack**: `slack-bot-token`, `slack-signing-secret`
- **Telegram**: `telegram-bot-token`, `telegram-webhook-secret`

**Benefits:**
- Centralized secret management
- Automatic rotation support
- Audit logging of secret access
- No secrets in environment variables or Git

---

## 4. CI/CD Integration

### 4.1 Jenkins Pipeline Extension

**Jenkinsfile.bot Pipeline Stages:**

1. **Build Bot Adapters** (Parallel)
   - Build Docker images for Teams, Slack, Telegram adapters
   - Tag with build number + git commit hash

2. **Security Scan** (Parallel)
   - Run Trivy scan on all bot images
   - Fail on CRITICAL vulnerabilities

3. **Push to ACR**
   - Push versioned and latest tags
   - Authenticate with managed identity

4. **Update GitOps Manifests**
   - Clone GitOps repository
   - Update Kustomize image references
   - Commit and push changes

5. **Deploy via ArgoCD**
   - Trigger ArgoCD sync
   - Wait for healthy status (10min timeout)

6. **Smoke Tests** (Parallel)
   - Send test messages to each platform
   - Verify responses received
   - Check latency < 5s

> Complete pipeline code available in `Jenkinsfile.bot`

### 4.2 GitOps Manifest Structure

**New Directory Structure:**
```
gitops/
├── base/
│   ├── bots/                        # NEW
│   │   ├── teams-deployment.yaml
│   │   ├── slack-deployment.yaml
│   │   ├── telegram-deployment.yaml
│   │   ├── bot-services.yaml
│   │   ├── bot-network-policy.yaml
│   │   └── kustomization.yaml
│   ├── backend-deployment.yaml       # EXISTING
│   └── ...
├── overlays/
│   └── production/
│       ├── bots/                    # NEW
│       │   ├── kustomization.yaml
│       │   └── patches/
│       │       ├── replicas.yaml    # Scale per platform
│       │       └── resources.yaml   # Adjust resource limits
│       └── ...
└── argocd/
    ├── application.yaml              # EXISTING
    └── bots-application.yaml         # NEW ArgoCD app for bots
```

**bots-application.yaml:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: circle-bots
  namespace: argocd
spec:
  project: circle-of-trust
  source:
    repoURL: https://github.com/your-org/circle-gitops.git
    targetRevision: main
    path: gitops/overlays/production/bots
  destination:
    server: https://kubernetes.default.svc
    namespace: circle-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=false  # Namespace created by main app
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

---

## 5. Networking & Security

### 5.1 Network Flow Diagram

```
┌────────────────────────────────────────────────────────────────┐
│                     Internet (Public)                           │
│                                                                 │
│  External Bot APIs:                                            │
│  • graph.microsoft.com (Teams)                                 │
│  • slack.com/api (Slack)                                       │
│  • api.telegram.org (Telegram)                                 │
└──────────────────┬─────────────────────────────────────────────┘
                   │
                   │ ▲ Outbound (HTTPS)
                   │ │
                   │ │
     ┌─────────────▼─┴────────────────────────────────────┐
     │  Azure Firewall (10.240.60.0/24)                   │
     │  • FQDN filtering                                   │
     │  • Application rules per platform                   │
     │  • Network rules for HTTPS (443)                    │
     │  • Logging all egress attempts                      │
     └─────────────┬───────────────▲────────────────────────┘
                   │ ▼ Route        │ ▲ Return
                   │ via UDR        │ │
                   │                │ │
     ┌─────────────▼────────────────┴─┐
     │  AKS Subnet (10.240.16.0/20)   │
     │  ┌───────────────────────────┐ │
     │  │ Bot Adapter Pods          │ │
     │  │ • Egress via Firewall     │ │
     │  │ • No direct internet      │ │
     │  └───────────────────────────┘ │
     └─────────────┬──────────────────┘
                   │ ▲ Internal
                   │ │
                   │ │
     ┌─────────────▼──┴─────────────────────────────────┐
     │  Application Gateway (Internal, 10.240.50.0/24)  │
     │  • Receives from Front Door only                  │
     │  • WAF policies                                    │
     │  • Routes to bot adapters                          │
     └─────────────┬──▲─────────────────────────────────┘
                   │  │
                   │  │
     ┌─────────────▼──┴─────────────────────────────────┐
     │  Azure Front Door (Microsoft Global Network)      │
     │  • Public endpoint for webhooks                    │
     │  • DDoS Protection                                 │
     │  • WAF (OWASP 3.2)                                │
     │  • SSL termination                                 │
     └─────────────┬──▲─────────────────────────────────┘
                   │  │ HTTPS
                   │  │
                   │  │
     ┌─────────────▼──┴─────────────────────────────────┐
     │  External Webhook Sources:                        │
     │  • Microsoft Teams (*.teams.microsoft.com)        │
     │  • Slack (*.slack.com)                            │
     │  • Telegram (149.154.160.0/20)                    │
     └───────────────────────────────────────────────────┘
```

### 5.2 Network Policies

**Bot Adapter Network Policy:**

**Ingress Rules:**
- Allow from: NGINX Ingress Controller (port 8080)
- Deny all other inbound traffic

**Egress Rules:**
- Allow to: Circle backend (port 8001)
- Allow to: CoreDNS for name resolution (port 53)
- Allow to: Azure Firewall subnet (port 443 for platform APIs)
- Deny all other outbound traffic

**Security Benefits:**
- Defense-in-depth: Pod can only receive from ingress, not arbitrary pods
- Limits blast radius if adapter compromised
- Prevents lateral movement in cluster
- Forces all external API calls through firewall

**Rationale**: Strict network policies implement defense-in-depth. Bot adapters can only receive from ingress controller (not arbitrary pods), can only call backend + DNS, all external API calls forced through firewall. Prevents lateral movement if adapter compromised, limits blast radius.

### 5.3 User-Defined Routes (UDR)

**Force egress through Azure Firewall:**

**Route Table Configuration:**
- Route: Internet traffic (0.0.0.0/0) → Azure Firewall private IP
- Route: Local VNet traffic (10.240.0.0/16) → VNet Local
- Association: Applied to AKS application subnet

**Result:**
- All egress from bot pods routes through firewall
- Enables centralized policy enforcement
- All external API calls logged
- Required for compliance audit trails

**Rationale**: UDR ensures all AKS egress traffic (except intra-VNet) routes through Azure Firewall, enabling centralized policy enforcement, logging, and threat detection. Without UDR, pods could bypass firewall using service endpoints or direct routes. Required for compliance audit trails.

---

## 6. Monitoring & Observability

### 6.1 Bot-Specific Metrics

**Prometheus ServiceMonitor:**
- Selector: Pods with label `component=bot-adapter`
- Scrape interval: 30 seconds
- Metrics endpoint: `/metrics`
- Labels: `platform`, `pod`

**Custom Metrics to Expose:**

**Webhook Metrics:**
- `bot_webhook_requests_total` - Total webhook requests (by platform, status)
- `bot_webhook_processing_seconds` - Processing duration histogram

**Message Metrics:**
- `bot_messages_sent_total` - Messages sent to platforms (by platform, status)
- `bot_messages_received_total` - Messages received from users

**Backend Communication:**
- `bot_backend_requests_total` - Requests to Circle backend (by status)
- `bot_backend_request_seconds` - Backend request duration (buckets: 0.1, 0.5, 1.0, 2.0, 5.0, 10.0s)

**Health & Activity:**
- `bot_platform_api_health` - Platform API health gauge (1=healthy, 0=down)
- `bot_active_conversations` - Number of active conversations

### 6.2 Grafana Dashboard

**Bot Performance Dashboard Panels:**

1. **Messages Received** (Graph) - Rate per platform over time
2. **Webhook Processing Time** (Graph) - p95 latency by platform
3. **Backend Request Success Rate** (Graph) - Success vs total requests
4. **Platform API Health** (Stat) - Current health status per platform
5. **Active Conversations** (Graph) - Concurrent conversations over time
6. **Error Rate** (Graph) - Failed requests percentage
7. **Response Latency Distribution** (Heatmap) - End-to-end latency

### 6.3 Alerting Rules

**Alerting Rules:**

**BotWebhookFailureRateHigh** (Warning)
- Trigger: >5% webhook failures for 5 minutes
- Action: Notify team, investigate platform connectivity

**BotPlatformAPIDown** (Critical)
- Trigger: Platform API unreachable for 2 minutes
- Action: Page on-call, check firewall rules and platform status

**BotBackendLatencyHigh** (Warning)
- Trigger: p95 backend latency >5 seconds for 10 minutes
- Action: Investigate Circle backend performance, check Ollama GPU

**BotAdapterPodDown** (Critical)
- Trigger: Adapter pod not responding for 1 minute
- Action: Check pod status, review recent deployments

### 6.4 Logging Strategy

**Structured Logging Format:**

**Log Events:**
- `webhook_received` - User message received
- `backend_request` - Call to Circle backend
- `platform_api_error` - External API failure
- `message_sent` - Response delivered

**Standard Fields:**
- `platform` - teams/slack/telegram
- `user_id`, `conversation_id` - Context
- `correlation_id` - Request tracing
- `timestamp` - ISO 8601 format
- `duration_ms` - Execution time
- `status` - success/error

**Output:** JSON format for machine parsing

**Fluent Bit Configuration (Bot Logs):**

**Input:**
- Tail all bot-adapter container logs
- Parse Docker JSON format
- Tag: `kube.bot.<namespace>.<pod>.<container>`

**Filter:**
- Add Kubernetes metadata (pod, namespace, labels)
- Merge JSON log field
- Grep for bot platform logs only

**Output:**
- Send to Azure Log Analytics
- Custom table: `BotAdapterLogs`
- Include all structured fields

---

## 7. Cost Optimization

### 7.1 Estimated Monthly Costs

**Bot Infrastructure Costs:**

| Component | Configuration | Monthly Cost |
|-----------|---------------|--------------|
| **Bot Adapter Pods** | 3 Teams + 3 Slack + 2 Telegram (200m CPU, 256Mi RAM each) | Included in AKS |
| **Azure Front Door** | Standard tier, 100GB data processed | ~$35 + $0.60/GB = $95 |
| **API Management** | Developer tier (for testing) / Standard tier (prod) | $50 / $680 |
| **Azure Firewall** | Standard tier with 50GB egress/month | $1,236 + $0.016/GB = $1,237 |
| **Application Gateway** | Standard v2 (existing, shared) | ~$0 (allocated to main app) |
| **Log Analytics** | Additional 5GB ingestion/month for bot logs | $12.50 |
| **Bandwidth** | Egress to platforms (50GB/month) | $4 |
| **Blob Storage** | Bot conversation history (100GB) | $2 |
| **Key Vault** | 3 additional secrets (bot tokens) | ~$0 |

**Total Additional Cost (Development):** ~$1,400/month  
**Total Additional Cost (Production with Standard APIM):** ~$2,030/month

**Cost Optimization Strategies:**

1. **Start with Developer Tier API Management** ($50/month)
   - Sufficient for <1M API calls/month
   - Upgrade to Standard ($680) only when traffic exceeds limits
   - **Savings**: $630/month in early stages

2. **Azure Firewall Alternatives**
   - Consider Azure Firewall Basic tier (Preview): ~$400/month vs. $1,236
   - Alternative: Network Security Groups + NAT Gateway ($4.50/month + $0.045/GB = ~$6.75/month)
   - **Trade-off**: NSG lacks FQDN filtering, requires IP whitelisting (brittle for SaaS APIs with changing IPs)
   - **Recommendation**: Start with Firewall Standard for compliance, evaluate Basic tier when GA

3. **Front Door vs. Application Gateway**
   - Front Door required for global edge (webhook latency)
   - If serving single-region users, Application Gateway Public IP ($3.65/month) + DDoS Standard ($3,000/month) alternative
   - **Recommendation**: Keep Front Door for multi-region webhook delivery

4. **Bot Adapter Resource Optimization**
   - Right-size: Start with 100m CPU, 128Mi RAM per pod
   - HPA min=2, max=5 (vs. fixed 3 replicas)
   - **Savings**: 30-40% compute during low-traffic hours

5. **Egress Optimization**
   - Cache LLM responses for common questions (reduce backend calls)
   - Implement response debouncing (merge rapid-fire messages)
   - Use Telegram long polling in dev (avoid webhook egress)
   - **Estimated savings**: 20-30% bandwidth costs

**Revised Cost Estimate with Optimizations:**
- Development: ~$95 (Front Door) + $50 (APIM Dev) + $7 (NAT Gateway) + $15 (misc) = **$167/month**
- Production: ~$95 (Front Door) + $680 (APIM Std) + $1,237 (Firewall) + $15 (misc) = **$2,027/month**

---

## 8. Deployment Roadmap

### Phase 1: Foundation (Week 1-2)

**Week 1: Infrastructure Setup**
- [ ] Provision Azure Front Door with custom domain
- [ ] Deploy API Management (Developer tier)
- [ ] Configure Azure Firewall application rules for bot platforms
- [ ] Create UDR to route bot subnet egress through firewall
- [ ] Setup Key Vault secrets for bot credentials
- [ ] Deploy CSI Secret Provider for bot credentials

**Week 2: Bot Registration & Network Testing**
- [ ] Register Teams bot in Azure Portal, configure OAuth
- [ ] Create Slack app, configure Events API webhook
- [ ] Create Telegram bot via @BotFather
- [ ] Test webhook delivery: Front Door → App Gateway → AKS
- [ ] Verify egress: AKS → Firewall → Platform APIs
- [ ] Validate network policies (block unauthorized egress)

### Phase 2: Bot Adapter Development (Week 3-4)

**Week 3: Core Adapter Logic**
- [ ] Implement base `BotAdapter` abstract class
- [ ] Build Teams adapter with Bot Framework SDK
- [ ] Build Slack adapter with Events API
- [ ] Build Telegram adapter with Bot API
- [ ] Implement message normalization layer
- [ ] Add webhook signature validation for all platforms

**Week 4: Integration & Testing**
- [ ] Integrate adapters with Circle backend
- [ ] Implement response formatting (Adaptive Cards, Block Kit, Markdown)
- [ ] Add retry logic and error handling
- [ ] Build Dockerfiles for each adapter
- [ ] Write unit tests (mock webhooks, platform APIs)
- [ ] Create integration tests with docker-compose

### Phase 3: CI/CD Integration (Week 5)

**Week 5: Pipeline & GitOps**
- [ ] Create `Jenkinsfile.bot` for adapter builds
- [ ] Add security scanning for bot images (Trivy)
- [ ] Create Kubernetes manifests for bot deployments
- [ ] Setup GitOps repository structure (`gitops/base/bots/`)
- [ ] Create ArgoCD application for bots
- [ ] Implement automated deployment via ArgoCD sync
- [ ] Add smoke tests (send test message, verify response)

### Phase 4: Observability (Week 6)

**Week 6: Monitoring & Logging**
- [ ] Expose Prometheus metrics from adapters
- [ ] Create ServiceMonitor for bot pods
- [ ] Build Grafana dashboard for bot performance
- [ ] Configure PrometheusRules for alerting
- [ ] Setup Fluent Bit filtering for bot logs
- [ ] Create Log Analytics queries for bot analytics
- [ ] Configure PagerDuty/Opsgenie integration

### Phase 5: Pilot Testing (Week 7-8)

**Week 7: Internal Testing**
- [ ] Deploy to staging environment
- [ ] Create test Teams channel, Slack workspace, Telegram chat
- [ ] Invite beta testers (5-10 users per platform)
- [ ] Collect feedback on response quality
- [ ] Monitor performance metrics (latency, error rates)
- [ ] Tune HPA settings based on load

**Week 8: Bug Fixes & Optimization**
- [ ] Fix issues identified in testing
- [ ] Optimize message formatting
- [ ] Improve error messages and user guidance
- [ ] Add conversation context persistence
- [ ] Implement rate limiting per user
- [ ] Load test with k6 (simulate 100 concurrent users)

### Phase 6: Production Launch (Week 9-10)

**Week 9: Production Deployment**
- [ ] Promote to production environment
- [ ] Update DNS records for webhook endpoints
- [ ] Configure production secrets in Key Vault
- [ ] Enable monitoring and alerting
- [ ] Create operational runbooks
- [ ] Train support team on bot troubleshooting

**Week 10: Rollout & Stabilization**
- [ ] Gradual rollout: 10% users → 50% → 100%
- [ ] Monitor metrics closely (24/7 on-call)
- [ ] Collect user feedback
- [ ] Document known issues and workarounds
- [ ] Plan for next iteration (features, platforms)

---

## 9. Operational Considerations

### 9.1 Troubleshooting Guide

**Webhook Not Received:**
```bash
# Check Front Door health
az network front-door check-frontend-endpoint \
  --name circle-front-door \
  --resource-group circle-rg

# Check API Management logs
az monitor activity-log list \
  --resource-group circle-rg \
  --namespace Microsoft.ApiManagement \
  --start-time 2026-01-30T10:00:00Z

# Check bot adapter pod logs
kubectl logs -n circle-prod -l app=teams-bot-adapter --tail=100

# Verify ingress configuration
kubectl describe ingress teams-bot-webhook -n circle-prod
```

**Platform API Call Failing:**
```bash
# Check firewall logs
az monitor diagnostic-settings show \
  --resource <firewall-resource-id>

# Query firewall application rule logs
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AzureDiagnostics | where Category == 'AzureFirewallApplicationRule' and msg_s contains 'Deny'"

# Test egress manually (from pod)
kubectl exec -it -n circle-prod <bot-pod> -- curl -v https://graph.microsoft.com

# Check if firewall rule exists
az network firewall application-rule list \
  --collection-name teams-bot-egress \
  --firewall-name circle-firewall \
  --resource-group circle-rg
```

**High Latency:**
```bash
# Check backend response times
kubectl exec -n circle-prod <bot-pod> -- \
  curl -w "@curl-format.txt" -o /dev/null -s http://circle-backend:8001/api/chat

# Check Prometheus metrics
curl -s http://prometheus:9090/api/v1/query \
  --data-urlencode 'query=histogram_quantile(0.95, rate(bot_backend_request_seconds_bucket[5m]))'

# Check Ollama GPU utilization
kubectl exec -n circle-prod <ollama-pod> -- nvidia-smi
```

### 9.2 Runbooks

**Runbook: Bot Not Responding**

1. **Verify adapter pods are running**
   ```bash
   kubectl get pods -n circle-prod -l component=bot-adapter
   ```

2. **Check recent pod restarts**
   ```bash
   kubectl get pods -n circle-prod -l component=bot-adapter -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'
   ```

3. **Review recent logs for errors**
   ```bash
   kubectl logs -n circle-prod -l app=teams-bot-adapter --since=10m | grep ERROR
   ```

4. **Test backend connectivity from adapter pod**
   ```bash
   kubectl exec -it -n circle-prod <bot-pod> -- \
     curl -X POST http://circle-backend:8001/api/chat \
     -H "Content-Type: application/json" \
     -d '{"message": "test"}'
   ```

5. **Check network policies**
   ```bash
   kubectl describe networkpolicy bot-adapter-netpol -n circle-prod
   ```

6. **Verify secrets are mounted**
   ```bash
   kubectl exec -it -n circle-prod <bot-pod> -- ls -la /mnt/secrets/
   ```

7. **Restart adapter pods if necessary**
   ```bash
   kubectl rollout restart deployment/teams-bot-adapter -n circle-prod
   ```

**Runbook: High Error Rate from Platform API**

1. **Check platform status page**
   - Teams: https://status.office.com
   - Slack: https://status.slack.com
   - Telegram: https://t.me/BotNews

2. **Review firewall deny logs**
   ```bash
   # Check if requests are being blocked
   az monitor log-analytics query --workspace <id> \
     --analytics-query "AzureDiagnostics | where msg_s contains 'slack.com' and Action_s == 'Deny'"
   ```

3. **Verify bot credentials are valid**
   ```bash
   # Test Teams token
   curl -H "Authorization: Bearer <token>" https://graph.microsoft.com/v1.0/me
   
   # Test Slack token
   curl -H "Authorization: Bearer <token>" https://slack.com/api/auth.test
   ```

4. **Check rate limit headers in responses**
   ```python
   # Enable debug logging in adapter to see headers
   logger.debug("Platform response headers", headers=response.headers)
   ```

5. **Implement exponential backoff if rate limited**
   ```python
   if response.status_code == 429:
       retry_after = int(response.headers.get('Retry-After', 60))
       await asyncio.sleep(retry_after)
   ```

### 9.3 Disaster Recovery

**Bot-Specific DR Procedures:**

1. **Backup Bot Configurations**
   - Bot credentials stored in Key Vault (geo-replicated)
   - GitOps manifests in Git (inherently backed up)
   - Conversation history in PostgreSQL (geo-backup enabled)

2. **Failover Scenarios**

   **Scenario 1: Primary Region Outage**
   - Front Door automatically routes to secondary Application Gateway (if configured)
   - Webhook delivery paused until DR AKS cluster online
   - Estimated RTO: 1 hour (spin up DR cluster, sync ArgoCD)
   - RPO: 15 minutes (database geo-backup lag)

   **Scenario 2: Bot Adapter Pod Crash**
   - Kubernetes restarts pod automatically (liveness probe)
   - RTO: <1 minute
   - No data loss (stateless adapter)

   **Scenario 3: Platform API Outage**
   - Adapter queues responses in Redis (implement message buffer)
   - Retry sending when API recovers
   - User notified of temporary delay via platform

**Testing DR Procedures:**
```bash
# Simulate pod failure
kubectl delete pod -n circle-prod -l app=teams-bot-adapter

# Verify auto-recovery
kubectl get pods -n circle-prod -l app=teams-bot-adapter -w

# Test webhook delivery during pod restart
python3 tests/bots/test_webhook_delivery.py --platform teams --count 10
```

---

## 10. Security Compliance Checklist

**Pre-Launch Security Review:**

- [ ] **Authentication & Authorization**
  - [ ] Bot tokens stored in Key Vault (not environment variables)
  - [ ] Webhook signatures validated for all platforms
  - [ ] OAuth refresh tokens implemented (Teams)
  - [ ] RBAC configured for bot service accounts

- [ ] **Network Security**
  - [ ] Private AKS cluster (no public API server)
  - [ ] Network policies deny-all baseline
  - [ ] Egress through Azure Firewall only
  - [ ] FQDN allowlisting for platform APIs
  - [ ] DDoS Protection on Front Door

- [ ] **Data Protection**
  - [ ] Conversation data encrypted at rest (PostgreSQL TDE)
  - [ ] TLS 1.2+ enforced for all communication
  - [ ] No sensitive data logged (PII redaction)
  - [ ] Message retention policy defined (GDPR compliance)

- [ ] **Compliance & Audit**
  - [ ] All API calls logged to Log Analytics
  - [ ] Firewall logs retention 2 years
  - [ ] Webhook requests logged with correlation IDs
  - [ ] Security alerts configured (failed auth, suspicious activity)

- [ ] **Vulnerability Management**
  - [ ] Container images scanned (Trivy CRITICAL enforcement)
  - [ ] Dependency scanning (Safety, npm audit)
  - [ ] Regular patch schedule for base images
  - [ ] Security incident response plan documented

- [ ] **Platform-Specific**
  - [ ] Teams: Multi-factor authentication required for bot admin
  - [ ] Slack: App installed only in approved workspaces
  - [ ] Telegram: Bot username follows naming convention

---

## 11. Future Enhancements

### Phase 2 Features (Q2 2026)

1. **Additional Platforms**
   - Discord bot integration
   - WhatsApp Business API (via Twilio)
   - Google Chat connector

2. **Advanced Capabilities**
   - Multi-turn conversation context (thread awareness)
   - Rich media support (image generation, file uploads)
   - Voice message transcription (Azure Speech Services)
   - Proactive notifications (scheduled messages, alerts)

3. **Analytics & Insights**
   - User satisfaction tracking (thumbs up/down)
   - A/B testing for response formats
   - Conversation analytics dashboard
   - Cost attribution per platform/user

4. **Enterprise Features**
   - SSO integration for Teams (Azure AD)
   - Data residency controls (EU/US regions)
   - Audit log exports for compliance
   - Custom model fine-tuning per organization

5. **Performance Optimizations**
   - Response caching layer (Redis)
   - Async message processing (queue-based)
   - Pre-warming LLM models
   - Edge deployment (Front Door Edge Functions)

---

## 12. References & Resources

**Documentation:**
- [Microsoft Teams Bot Framework](https://docs.microsoft.com/en-us/microsoftteams/platform/bots/what-are-bots)
- [Slack Events API](https://api.slack.com/apis/connections/events-api)
- [Telegram Bot API](https://core.telegram.org/bots/api)
- [Azure Firewall FQDN Filtering](https://docs.microsoft.com/en-us/azure/firewall/fqdn-filtering-network-rules)
- [Azure Front Door](https://docs.microsoft.com/en-us/azure/frontdoor/)
- [AKS Private Cluster](https://docs.microsoft.com/en-us/azure/aks/private-clusters)

**Code Repositories:**
- Bot Framework SDK (Python): https://github.com/microsoft/botbuilder-python
- Slack SDK (Python): https://github.com/slackapi/python-slack-sdk
- Python Telegram Bot: https://github.com/python-telegram-bot/python-telegram-bot

**Tools:**
- Ngrok (local webhook testing): https://ngrok.com
- Postman Collections (bot APIs): https://www.postman.com/collections
- Bot Framework Emulator: https://github.com/Microsoft/BotFramework-Emulator

---

**End of Document**
