# Azure Front Door Premium Deployment Reference Guide

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Component Deep Dive](#component-deep-dive)
4. [Security Implementation](#security-implementation)
5. [Design Decisions & Considerations](#design-decisions--considerations)
6. [File Structure & Module Reference](#file-structure--module-reference)
7. [Parameter Reference](#parameter-reference)
8. [Pre-Deployment Requirements](#pre-deployment-requirements)
9. [Deployment Guide](#deployment-guide)
10. [Post-Deployment Validation](#post-deployment-validation)
11. [Operational Guidance](#operational-guidance)
12. [Troubleshooting](#troubleshooting)
13. [Cost Considerations](#cost-considerations)
14. [References](#references)

---

## Executive Summary

This project deploys a secure, production-ready Azure Front Door Premium instance using Infrastructure as Code (Bicep). The deployment includes:

- **Azure Front Door Premium** - Global load balancer and CDN with advanced security features
- **Web Application Firewall (WAF)** - Layer 7 protection with managed rules
- **Security Headers** - Response header hardening via Rules Engine
- **Origin Protection** - App Service access restrictions
- **Monitoring & Alerting** - Log Analytics integration with security alerts

### Key Features

| Feature | Implementation |
|---------|----------------|
| Global Load Balancing | Azure Front Door Premium |
| DDoS Protection | Built-in Layer 3/4 + WAF Layer 7 |
| TLS/SSL | Automatic HTTPS, TLS 1.2 minimum |
| WAF Rules | Microsoft DRS 2.1 + Bot Manager 1.1 |
| Rate Limiting | Configurable per-IP throttling |
| Caching | Edge caching with compression |
| Monitoring | Log Analytics + Alert Rules |

---

## Architecture Overview

### High-Level Architecture

```
                                    ┌─────────────────────────────────────────────────────────────┐
                                    │                     AZURE CLOUD                              │
                                    │                                                              │
┌──────────┐                        │  ┌─────────────────────────────────────────────────────┐   │
│          │                        │  │              AZURE FRONT DOOR PREMIUM               │   │
│  Users   │────HTTPS───────────────┼─▶│                                                     │   │
│(Global)  │                        │  │  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  │   │
│          │                        │  │  │   WAF       │  │  Rules      │  │  Caching   │  │   │
└──────────┘                        │  │  │   Policy    │  │  Engine     │  │  Layer     │  │   │
                                    │  │  │  (DRS 2.1)  │  │  (Headers)  │  │            │  │   │
                                    │  │  └─────────────┘  └─────────────┘  └────────────┘  │   │
                                    │  │                                                     │   │
                                    │  │  ┌─────────────────────────────────────────────┐   │   │
                                    │  │  │              ENDPOINT                        │   │   │
                                    │  │  │         *.azurefd.net                        │   │   │
                                    │  │  └─────────────────────────────────────────────┘   │   │
                                    │  │                         │                          │   │
                                    │  │  ┌─────────────────────────────────────────────┐   │   │
                                    │  │  │           ORIGIN GROUP                       │   │   │
                                    │  │  │      (Health Probes / Load Balancing)        │   │   │
                                    │  │  └─────────────────────────────────────────────┘   │   │
                                    │  │                         │                          │   │
                                    │  └─────────────────────────┼──────────────────────────┘   │
                                    │                            │                              │
                                    │                     HTTPS Only                            │
                                    │                            │                              │
                                    │                            ▼                              │
                                    │  ┌─────────────────────────────────────────────────────┐   │
                                    │  │                  APP SERVICE                        │   │
                                    │  │           (Access Restricted to AFD)               │   │
                                    │  │                                                     │   │
                                    │  │  ┌─────────────────────────────────────────────┐   │   │
                                    │  │  │  IP Restrictions:                           │   │   │
                                    │  │  │  ✓ AzureFrontDoor.Backend service tag       │   │   │
                                    │  │  │  ✓ X-Azure-FDID header validation           │   │   │
                                    │  │  └─────────────────────────────────────────────┘   │   │
                                    │  └─────────────────────────────────────────────────────┘   │
                                    │                                                              │
                                    │  ┌─────────────────────────────────────────────────────┐   │
                                    │  │              MONITORING                             │   │
                                    │  │                                                     │   │
                                    │  │  ┌──────────────┐  ┌──────────────────────────┐   │   │
                                    │  │  │ Log Analytics│  │     Alert Rules          │   │   │
                                    │  │  │  Workspace   │  │  • WAF Blocks            │   │   │
                                    │  │  │              │  │  • Origin Health         │   │   │
                                    │  │  │  • Access    │  │  • Error Rates           │   │   │
                                    │  │  │  • WAF       │  │  • Latency               │   │   │
                                    │  │  │  • Health    │  │  • Traffic Anomalies     │   │   │
                                    │  │  └──────────────┘  └──────────────────────────┘   │   │
                                    │  └─────────────────────────────────────────────────────┘   │
                                    │                                                              │
                                    └─────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **User Request** → User makes HTTPS request to `*.azurefd.net` endpoint
2. **Edge POP** → Request arrives at nearest Azure Front Door Point of Presence
3. **WAF Inspection** → Request evaluated against WAF rules (DRS 2.1, Bot Manager)
4. **Rate Limiting** → Per-IP rate limit check
5. **Cache Check** → If cached, return immediately from edge
6. **Origin Forwarding** → Forward to App Service via HTTPS only
7. **Response Processing** → Apply security headers via Rules Engine
8. **Cache Storage** → Cache eligible responses at edge
9. **Response Delivery** → Return response to user with security headers

### Network Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           REQUEST FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Client ──► DNS ──► Front Door POP ──► WAF ──► Route ──► Origin ──► App    │
│    │                     │               │        │          │               │
│    │                     │               │        │          │               │
│    ▼                     ▼               ▼        ▼          ▼               │
│  HTTPS              Anycast IP      Inspect   Forward   Validate            │
│  TLS 1.2+           (nearest)       Block/    HTTPS     X-Azure-FDID        │
│                                     Allow     Only                           │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                           RESPONSE FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Client ◄── Front Door POP ◄── Rules Engine ◄── Cache/Origin                │
│    │              │                  │                                       │
│    ▼              ▼                  ▼                                       │
│  Receive     Compress           Add Security                                 │
│  Response    (gzip)             Headers                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Deep Dive

### 1. Azure Front Door Premium Profile

**Resource Type**: `Microsoft.Cdn/profiles`

**Purpose**: The core Front Door resource that provides global load balancing, CDN capabilities, and serves as the parent resource for all other Front Door components.

**Key Configuration**:
```bicep
resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: profileName
  location: 'global'
  sku: {
    name: 'Premium_AzureFrontDoor'  // Required for WAF managed rules
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}
```

**Why Premium Tier?**
| Feature | Standard | Premium |
|---------|----------|---------|
| WAF Custom Rules | ✓ | ✓ |
| WAF Managed Rules (DRS 2.1) | ✗ | ✓ |
| Bot Manager Rules | ✗ | ✓ |
| Private Link Origins | ✗ | ✓ |
| Enhanced Analytics | ✗ | ✓ |

### 2. AFD Endpoint

**Resource Type**: `Microsoft.Cdn/profiles/afdEndpoints`

**Purpose**: The public-facing endpoint that receives incoming traffic. Each endpoint gets a unique hostname (`*.azurefd.net`).

**Key Configuration**:
```bicep
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  name: endpointName
  parent: profile
  location: 'global'
  properties: {
    enabledState: 'Enabled'
    autoGeneratedDomainNameLabelScope: 'TenantReuse'
  }
}
```

**Output**: `fde-myapp-prod.azurefd.net`

### 3. Origin Group

**Resource Type**: `Microsoft.Cdn/profiles/originGroups`

**Purpose**: Logical grouping of origins with load balancing and health probe configuration.

**Key Configuration**:
```bicep
properties: {
  loadBalancingSettings: {
    sampleSize: 4                        // Number of samples for health decisions
    successfulSamplesRequired: 3         // Minimum healthy samples
    additionalLatencyInMilliseconds: 50  // Latency tolerance for failover
  }
  healthProbeSettings: {
    probePath: '/health'
    probeRequestType: 'HEAD'             // Lightweight probes
    probeProtocol: 'Https'               // Secure health checks
    probeIntervalInSeconds: 30
  }
  sessionAffinityState: 'Disabled'       // Stateless for better distribution
}
```

**Health Probe Behavior**:
- Probes sent every 30 seconds from multiple Front Door POPs
- Origin marked unhealthy after 3 consecutive failures
- Traffic automatically routed away from unhealthy origins

### 4. Origin

**Resource Type**: `Microsoft.Cdn/profiles/originGroups/origins`

**Purpose**: Represents the backend App Service that serves the actual content.

**Key Configuration**:
```bicep
properties: {
  hostName: hostName                     // e.g., myapp.azurewebsites.net
  httpPort: 80                           // Required by API (not used)
  httpsPort: 443
  originHostHeader: hostName             // Host header sent to origin
  priority: 1                            // Lower = higher priority
  weight: 1000                           // Load balancing weight
  enabledState: 'Enabled'
  enforceCertificateNameCheck: true      // Validate origin SSL certificate
}
```

**Security Note**: `enforceCertificateNameCheck: true` ensures Front Door validates the origin's SSL certificate matches the hostname, preventing MITM attacks.

### 5. Route

**Resource Type**: `Microsoft.Cdn/profiles/afdEndpoints/routes`

**Purpose**: Defines how incoming requests are matched and forwarded to origin groups.

**Key Configuration**:
```bicep
properties: {
  originGroup: { id: originGroupId }
  supportedProtocols: ['Http', 'Https']  // Accept both
  patternsToMatch: ['/*']                // Match all paths
  forwardingProtocol: 'HttpsOnly'        // HTTPS to origin
  httpsRedirect: 'Enabled'               // HTTP → HTTPS redirect
  cacheConfiguration: {
    queryStringCachingBehavior: 'UseQueryString'
    compressionSettings: {
      isCompressionEnabled: true
      contentTypesToCompress: [...]
    }
  }
}
```

**HTTPS Enforcement**:
1. User requests `http://...` → Front Door returns `301 Redirect` to `https://...`
2. Front Door only connects to origin via HTTPS (port 443)

### 6. WAF Policy

**Resource Type**: `Microsoft.Network/FrontDoorWebApplicationFirewallPolicies`

**Purpose**: Provides Layer 7 protection against web attacks.

**Managed Rule Sets**:

| Rule Set | Version | Purpose |
|----------|---------|---------|
| Microsoft_DefaultRuleSet | 2.1 | OWASP CRS 3.3.2 + Microsoft Threat Intelligence |
| Microsoft_BotManagerRuleSet | 1.1 | Bot detection and mitigation |

**DRS 2.1 Rule Groups** (17 total):

| Group | Protection Against |
|-------|-------------------|
| SQLI | SQL Injection attacks |
| XSS | Cross-Site Scripting |
| LFI | Local File Inclusion |
| RFI | Remote File Inclusion |
| RCE | Remote Code Execution |
| PHP | PHP-specific attacks |
| NODEJS | Node.js injection |
| JAVA | Java-specific attacks |
| MS-ThreatIntel-WebShells | Web shell detection |
| MS-ThreatIntel-CVEs | Known CVE exploits |

**Custom Rules**:
```bicep
// Rate Limiting
{
  name: 'RateLimitRule'
  ruleType: 'RateLimitRule'
  rateLimitDurationInMinutes: 1
  rateLimitThreshold: 500              // Configurable
  action: 'Block'
}

// Geo-Blocking (Optional)
{
  name: 'GeoBlockRule'
  ruleType: 'MatchRule'
  matchConditions: [{
    matchVariable: 'SocketAddr'
    operator: 'GeoMatch'
    matchValue: ['XX', 'YY']           // Country codes
  }]
  action: 'Block'
}
```

### 7. Security Policy

**Resource Type**: `Microsoft.Cdn/profiles/securityPolicies`

**Purpose**: Associates WAF policy with Front Door endpoints.

```bicep
properties: {
  parameters: {
    type: 'WebApplicationFirewall'
    wafPolicy: { id: wafPolicyId }
    associations: [{
      domains: [{ id: endpointId }]
      patternsToMatch: ['/*']
    }]
  }
}
```

### 8. Security Headers Rule Set

**Resource Type**: `Microsoft.Cdn/profiles/ruleSets` + `Microsoft.Cdn/profiles/ruleSets/rules`

**Purpose**: Adds security headers to all responses and removes identifying headers.

**Headers Added**:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevent MIME type sniffing |
| `X-Frame-Options` | `SAMEORIGIN` | Prevent clickjacking |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Enforce HTTPS |
| `X-XSS-Protection` | `1; mode=block` | Legacy XSS filter |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Control referrer information |
| `Permissions-Policy` | `geolocation=(), microphone=(), camera=()` | Restrict browser features |

**Headers Removed**:

| Header | Reason |
|--------|--------|
| `Server` | Hides server technology |
| `X-Powered-By` | Hides application framework |

### 9. App Service Restrictions

**Resource Type**: `Microsoft.Web/sites/config`

**Purpose**: Restricts App Service to only accept traffic from Front Door.

**Configuration**:
```bicep
ipSecurityRestrictions: [
  {
    name: 'AllowFrontDoor'
    tag: 'ServiceTag'
    ipAddress: 'AzureFrontDoor.Backend'
    headers: {
      'x-azure-fdid': [frontDoorId]    // Your specific Front Door instance
    }
    action: 'Allow'
  },
  {
    name: 'DenyAll'
    ipAddress: 'Any'
    action: 'Deny'
  }
]
```

**Why Both Service Tag AND Header?**
- Service tag alone allows ANY Front Door instance
- `X-Azure-FDID` header validation ensures only YOUR Front Door can access the origin
- Defense in depth approach

### 10. Alert Rules

**Resource Types**: `Microsoft.Insights/metricAlerts`, `Microsoft.Insights/scheduledQueryRules`

**Alerts Configured**:

| Alert | Type | Trigger | Severity |
|-------|------|---------|----------|
| WAF Blocks | Log Query | >100 blocks/5min | 2 (Warning) |
| Origin Health | Metric | <80% healthy | 1 (Error) |
| 4xx Errors | Metric | >10% rate | 3 (Info) |
| 5xx Errors | Metric | >5% rate | 1 (Error) |
| High Latency | Metric | >3000ms | 2 (Warning) |
| Traffic Anomaly | Log Query | >200% deviation | 3 (Info) |

---

## Security Implementation

### Security Review Findings & Remediation

#### Initial Assessment

| Category | Initial Score | Final Score |
|----------|---------------|-------------|
| WAF Protection | 9/10 | 10/10 |
| TLS/Encryption | 9/10 | 9/10 |
| Logging | 8/10 | 9/10 |
| Network Security | 7/10 | 9/10 |
| Access Control | 7/10 | 9/10 |
| **Overall** | **8/10** | **9.2/10** |

#### Findings & Remediation

##### Finding 1: Rate Limit Threshold Too High
- **Initial**: Hardcoded 1000 req/min
- **Risk**: May not protect against slower attacks
- **Remediation**: Parameterized with environment-specific defaults
  - Production: 500 req/min
  - Development: 1000 req/min
- **Status**: ✅ Resolved

##### Finding 2: No Response Header Hardening
- **Initial**: No security headers configured
- **Risk**: Vulnerable to clickjacking, MIME sniffing, etc.
- **Remediation**: Added Rules Engine with 6 security headers
- **Status**: ✅ Resolved

##### Finding 3: Origin Accessible Directly
- **Initial**: App Service publicly accessible
- **Risk**: WAF bypass by accessing origin directly
- **Remediation**: Added App Service IP restrictions with Front Door ID validation
- **Status**: ✅ Resolved

##### Finding 4: No Security Alerting
- **Initial**: Logs collected but no alerts
- **Risk**: Security incidents go unnoticed
- **Remediation**: Added 6 alert rules for security monitoring
- **Status**: ✅ Resolved

##### Finding 5: Cache Query String Handling
- **Initial**: `IgnoreQueryString` - may serve incorrect cached content
- **Risk**: Data leakage or incorrect responses
- **Remediation**: Changed default to `UseQueryString`
- **Status**: ✅ Resolved

##### Finding 6: Geo-Blocking Not Available
- **Initial**: No geo-blocking capability
- **Risk**: Cannot restrict traffic by geography
- **Remediation**: Added optional geo-blocking with configurable countries
- **Status**: ✅ Resolved

### Security Controls Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SECURITY LAYERS                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Layer 1: Network Edge                                                       │
│  ├── Azure DDoS Protection (built-in)                                       │
│  ├── Anycast distribution                                                   │
│  └── TLS 1.2+ termination                                                   │
│                                                                              │
│  Layer 2: Web Application Firewall                                          │
│  ├── Microsoft Default Rule Set 2.1                                         │
│  │   ├── SQL Injection protection                                           │
│  │   ├── Cross-Site Scripting protection                                    │
│  │   ├── Remote Code Execution protection                                   │
│  │   └── 17 rule groups total                                               │
│  ├── Bot Manager Rule Set 1.1                                               │
│  │   ├── Bad bot blocking                                                   │
│  │   └── Good bot allowlisting                                              │
│  └── Custom Rules                                                           │
│      ├── Rate limiting (500 req/min/IP)                                     │
│      └── Geo-blocking (optional)                                            │
│                                                                              │
│  Layer 3: Transport Security                                                 │
│  ├── HTTPS redirect (HTTP → HTTPS)                                          │
│  ├── HTTPS-only origin forwarding                                           │
│  └── Certificate validation                                                 │
│                                                                              │
│  Layer 4: Response Hardening                                                │
│  ├── X-Content-Type-Options: nosniff                                        │
│  ├── X-Frame-Options: SAMEORIGIN                                            │
│  ├── Strict-Transport-Security                                              │
│  ├── X-XSS-Protection                                                       │
│  ├── Referrer-Policy                                                        │
│  ├── Permissions-Policy                                                     │
│  └── Server header removal                                                  │
│                                                                              │
│  Layer 5: Origin Protection                                                 │
│  ├── Service tag restriction (AzureFrontDoor.Backend)                       │
│  ├── X-Azure-FDID header validation                                         │
│  └── Deny all other traffic                                                 │
│                                                                              │
│  Layer 6: Monitoring & Detection                                            │
│  ├── Access logging                                                         │
│  ├── WAF logging                                                            │
│  ├── Health probe logging                                                   │
│  └── Security alerts                                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Design Decisions & Considerations

### Why Azure Front Door Premium?

| Consideration | Decision | Rationale |
|---------------|----------|-----------|
| WAF Managed Rules | Premium required | DRS 2.1 and Bot Manager only available in Premium |
| Cost vs Security | Prioritize security | Premium cost justified for production workloads |
| Private Link | Not used | App Service restriction sufficient; Private Link adds complexity |

### Why Modular Bicep Structure?

1. **Reusability**: Modules can be used in other projects
2. **Maintainability**: Changes isolated to specific modules
3. **Testability**: Modules can be validated independently
4. **Team Collaboration**: Different team members can own different modules

### Why Detection Mode for Development?

| Environment | WAF Mode | Rationale |
|-------------|----------|-----------|
| Development | Detection | Monitor without blocking; tune rules |
| Staging | Detection/Prevention | Test prevention before production |
| Production | Prevention | Active protection |

### Why UseQueryString for Caching?

| Option | Behavior | Use Case |
|--------|----------|----------|
| IgnoreQueryString | Same cache for `?a=1` and `?a=2` | Static content only |
| UseQueryString | Different cache per query | Dynamic content, APIs |
| **Chosen**: UseQueryString | Correctness over cache efficiency | Prevents serving wrong data |

### Why SAMEORIGIN Instead of DENY?

| Option | Behavior | Trade-off |
|--------|----------|-----------|
| DENY | Cannot be framed at all | Maximum security but may break features |
| SAMEORIGIN | Can be framed by same origin | Allows legitimate iframe use |
| **Chosen**: SAMEORIGIN (configurable) | Balance security and functionality |

---

## File Structure & Module Reference

```
infrastructure/
├── main.bicep                                    # Main orchestration (257 lines)
├── parameters/
│   ├── parameters.dev.bicepparam                # Development parameters (37 lines)
│   └── parameters.prod.bicepparam               # Production parameters (45 lines)
└── modules/
    ├── frontdoor/
    │   ├── profile.bicep                        # AFD Premium profile (21 lines)
    │   ├── endpoint.bicep                       # AFD endpoint (23 lines)
    │   ├── originGroup.bicep                    # Origin group + health probes (37 lines)
    │   ├── origin.bicep                         # App Service origin (41 lines)
    │   ├── route.bicep                          # Route with caching (80 lines)
    │   ├── securityPolicy.bicep                 # WAF association (43 lines)
    │   └── securityHeaders.bicep                # Security headers rule set (137 lines)
    ├── waf/
    │   └── wafPolicy.bicep                      # WAF policy with rules (134 lines)
    ├── monitoring/
    │   ├── logAnalytics.bicep                   # Log Analytics workspace (34 lines)
    │   ├── diagnosticSettings.bicep             # Diagnostic settings (51 lines)
    │   └── alertRules.bicep                     # Security alert rules (265 lines)
    └── backend/
        └── appServiceRestriction.bicep          # App Service restrictions (78 lines)

Total: 15 files, ~1,300 lines of Bicep code
```

### Module Dependency Graph

```
                    ┌─────────────────┐
                    │   main.bicep    │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ logAnalytics  │   │   wafPolicy   │   │   profile     │
└───────────────┘   └───────────────┘   └───────┬───────┘
        │                    │                    │
        │                    │      ┌─────────────┼─────────────┐
        │                    │      │             │             │
        │                    │      ▼             ▼             ▼
        │                    │ ┌─────────┐ ┌───────────┐ ┌─────────────┐
        │                    │ │endpoint │ │originGroup│ │securityHdrs │
        │                    │ └────┬────┘ └─────┬─────┘ └──────┬──────┘
        │                    │      │            │              │
        │                    │      │            ▼              │
        │                    │      │      ┌──────────┐         │
        │                    │      │      │  origin  │         │
        │                    │      │      └────┬─────┘         │
        │                    │      │           │               │
        │                    │      └─────┬─────┴───────────────┘
        │                    │            │
        │                    │            ▼
        │                    │      ┌──────────┐
        │                    │      │  route   │
        │                    │      └──────────┘
        │                    │            │
        │                    └──────┬─────┘
        │                           │
        │                           ▼
        │                   ┌──────────────┐
        │                   │securityPolicy│
        │                   └──────────────┘
        │
        ├─────────────────────────┐
        │                         │
        ▼                         ▼
┌───────────────────┐   ┌─────────────────────┐
│diagnosticSettings │   │     alertRules      │
└───────────────────┘   └─────────────────────┘
                                  │
                                  ▼
                        ┌─────────────────────┐
                        │appServiceRestriction│
                        │    (optional)       │
                        └─────────────────────┘
```

---

## Parameter Reference

### Required Parameters

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `environment` | string | Environment name | `'prod'` |
| `baseName` | string | Base name for resources | `'myapp'` |
| `appServiceHostName` | string | Backend App Service hostname | `'myapp.azurewebsites.net'` |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | Resource group location | Regional resources location |
| `appServiceName` | string | `''` | App Service name for restrictions |
| `wafMode` | string | `'Prevention'` | WAF mode: Detection/Prevention |
| `rateLimitThreshold` | int | `500` | Rate limit (100-5000 req/min) |
| `enableGeoBlocking` | bool | `false` | Enable geo-blocking |
| `blockedCountryCodes` | array | `[]` | ISO country codes to block |
| `queryStringCachingBehavior` | string | `'UseQueryString'` | Cache behavior |
| `xFrameOptions` | string | `'SAMEORIGIN'` | X-Frame-Options value |
| `enableAlertRules` | bool | `true` | Enable security alerts |
| `alertActionGroupId` | string | `''` | Action group for notifications |
| `logRetentionDays` | int | `90` | Log retention period |
| `healthProbePath` | string | `'/health'` | Health check endpoint |
| `tags` | object | `{}` | Resource tags |

### Environment Differences

| Parameter | Development | Production |
|-----------|-------------|------------|
| `wafMode` | Detection | Prevention |
| `rateLimitThreshold` | 1000 | 500 |
| `enableAlertRules` | false | true |
| `logRetentionDays` | 30 | 365 |
| `appServiceName` | `''` (skip) | Set (enable restrictions) |

---

## Pre-Deployment Requirements

### 1. Azure Subscription Requirements

- [ ] Active Azure subscription
- [ ] Subscription registered for required providers:
  ```bash
  az provider register --namespace Microsoft.Cdn
  az provider register --namespace Microsoft.Network
  az provider register --namespace Microsoft.OperationalInsights
  az provider register --namespace Microsoft.Insights
  az provider register --namespace Microsoft.Web
  ```

### 2. Required Permissions

| Scope | Role | Purpose |
|-------|------|---------|
| Subscription/Resource Group | Contributor | Create all resources |
| Subscription | User Access Administrator | (Optional) Assign roles |

Minimum custom role permissions:
```json
{
  "actions": [
    "Microsoft.Cdn/*",
    "Microsoft.Network/frontDoorWebApplicationFirewallPolicies/*",
    "Microsoft.OperationalInsights/workspaces/*",
    "Microsoft.Insights/*",
    "Microsoft.Web/sites/config/*",
    "Microsoft.Resources/deployments/*"
  ]
}
```

### 3. Prerequisites Checklist

- [ ] **Azure CLI installed** (version 2.50.0+)
  ```bash
  az --version
  ```

- [ ] **Bicep CLI installed** (version 0.22.0+)
  ```bash
  az bicep version
  # Or install: az bicep install
  ```

- [ ] **Logged into Azure**
  ```bash
  az login
  az account show
  ```

- [ ] **Correct subscription selected**
  ```bash
  az account set --subscription "Your-Subscription-Name"
  ```

- [ ] **App Service exists** (the backend origin)
  ```bash
  az webapp show --name myapp-prod --resource-group rg-myapp-prod
  ```

- [ ] **Health endpoint available**
  - Your App Service should have a `/health` endpoint (or update `healthProbePath`)
  - Endpoint should return HTTP 200 when healthy

### 4. Update Parameter Files

Before deploying, update the parameter files with your actual values:

**parameters.prod.bicepparam**:
```bicep
param baseName = 'yourappname'                           // Your app name
param appServiceHostName = 'yourapp.azurewebsites.net'   // Your App Service
param appServiceName = 'yourapp-prod'                    // For access restrictions
param alertActionGroupId = '/subscriptions/.../actionGroups/...'  // Your action group
```

### 5. Create Action Group (Optional but Recommended)

For alert notifications, create an Action Group:

```bash
# Create action group for email notifications
az monitor action-group create \
  --resource-group rg-myapp-prod \
  --name ag-myapp-alerts \
  --short-name myappalert \
  --action email admin admin@example.com
```

Get the resource ID for `alertActionGroupId`:
```bash
az monitor action-group show \
  --resource-group rg-myapp-prod \
  --name ag-myapp-alerts \
  --query id -o tsv
```

---

## Deployment Guide

### Step 1: Create Resource Group

```bash
# Production
az group create \
  --name rg-frontdoor-prod \
  --location eastus2 \
  --tags environment=prod project=MyApplication

# Development
az group create \
  --name rg-frontdoor-dev \
  --location eastus2 \
  --tags environment=dev project=MyApplication
```

### Step 2: Validate Deployment

Validate the Bicep template before deploying:

```bash
# Change to infrastructure directory
cd infrastructure

# Validate production deployment
az deployment group validate \
  --resource-group rg-frontdoor-prod \
  --template-file main.bicep \
  --parameters parameters/parameters.prod.bicepparam
```

Expected output:
```json
{
  "properties": {
    "provisioningState": "Succeeded"
  }
}
```

### Step 3: Preview Changes (What-If)

Preview what will be created:

```bash
az deployment group what-if \
  --resource-group rg-frontdoor-prod \
  --template-file main.bicep \
  --parameters parameters/parameters.prod.bicepparam
```

Review the output carefully. You should see:
- **Create**: ~15-20 resources (Front Door, WAF, Log Analytics, etc.)
- **Modify**: 0 (for new deployment)
- **Delete**: 0

### Step 4: Deploy

```bash
# Deploy to production
az deployment group create \
  --resource-group rg-frontdoor-prod \
  --template-file main.bicep \
  --parameters parameters/parameters.prod.bicepparam \
  --name "frontdoor-$(date +%Y%m%d-%H%M%S)"

# Deploy to development
az deployment group create \
  --resource-group rg-frontdoor-dev \
  --template-file main.bicep \
  --parameters parameters/parameters.dev.bicepparam \
  --name "frontdoor-$(date +%Y%m%d-%H%M%S)"
```

### Step 5: Monitor Deployment

Deployment typically takes 5-10 minutes. Monitor progress:

```bash
# Watch deployment status
az deployment group show \
  --resource-group rg-frontdoor-prod \
  --name "frontdoor-YYYYMMDD-HHMMSS" \
  --query properties.provisioningState

# List deployment operations
az deployment operation group list \
  --resource-group rg-frontdoor-prod \
  --name "frontdoor-YYYYMMDD-HHMMSS" \
  --query "[].{Resource:targetResource.resourceName, Status:provisioningState}"
```

### Step 6: Get Deployment Outputs

```bash
az deployment group show \
  --resource-group rg-frontdoor-prod \
  --name "frontdoor-YYYYMMDD-HHMMSS" \
  --query properties.outputs
```

Key outputs:
- `frontDoorEndpointUrl` - Your Front Door URL (e.g., `https://fde-myapp-prod.azurefd.net`)
- `frontDoorId` - Front Door ID for App Service restrictions
- `wafPolicyName` - WAF policy name for monitoring

---

## Post-Deployment Validation

### 1. Verify Front Door Endpoint

```bash
# Get endpoint URL
ENDPOINT=$(az deployment group show \
  --resource-group rg-frontdoor-prod \
  --name "frontdoor-YYYYMMDD-HHMMSS" \
  --query properties.outputs.frontDoorEndpointUrl.value -o tsv)

echo "Front Door URL: $ENDPOINT"

# Test endpoint (may take 5-10 minutes to propagate)
curl -I $ENDPOINT
```

Expected response:
```
HTTP/2 200
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
strict-transport-security: max-age=31536000; includeSubDomains
x-xss-protection: 1; mode=block
referrer-policy: strict-origin-when-cross-origin
```

### 2. Verify HTTPS Redirect

```bash
# Test HTTP redirect
curl -I http://fde-myapp-prod.azurefd.net

# Expected: 301 redirect to HTTPS
HTTP/1.1 301 Moved Permanently
Location: https://fde-myapp-prod.azurefd.net/
```

### 3. Verify WAF is Active

```bash
# Test WAF with SQL injection attempt (should be blocked)
curl -I "https://fde-myapp-prod.azurefd.net/?id=1'%20OR%20'1'='1"

# Expected in Prevention mode: 403 Forbidden
# Expected in Detection mode: 200 OK (but logged)
```

### 4. Verify Security Headers

```bash
curl -I https://fde-myapp-prod.azurefd.net 2>&1 | grep -E "^(x-|strict-|referrer-|permissions-)"
```

Expected headers:
```
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
strict-transport-security: max-age=31536000; includeSubDomains
x-xss-protection: 1; mode=block
referrer-policy: strict-origin-when-cross-origin
permissions-policy: geolocation=(), microphone=(), camera=()
```

### 5. Verify Origin Protection (If Enabled)

```bash
# Direct access to App Service should fail
curl -I https://myapp-prod.azurewebsites.net

# Expected: 403 Forbidden (if restrictions enabled)
```

### 6. Check Azure Portal

1. **Front Door** → Overview → Verify endpoint is healthy
2. **Front Door** → Security policies → Verify WAF attached
3. **WAF Policy** → Overview → Verify mode (Detection/Prevention)
4. **Log Analytics** → Logs → Run test query:
   ```kusto
   AzureDiagnostics
   | where Category == "FrontDoorAccessLog"
   | take 10
   ```

---

## Operational Guidance

### WAF Tuning Process

1. **Deploy in Detection Mode**
   ```bicep
   param wafMode = 'Detection'
   ```

2. **Monitor for 1-2 weeks**
   ```kusto
   // Find blocked requests
   AzureDiagnostics
   | where Category == "FrontDoorWebApplicationFirewallLog"
   | where action_s == "Block"
   | summarize count() by ruleName_s
   | order by count_ desc
   ```

3. **Identify False Positives**
   - Review blocked requests
   - Verify if legitimate traffic was blocked

4. **Add Exclusions (if needed)**
   ```bicep
   // In wafPolicy.bicep, add rule group overrides
   ruleGroupOverrides: [
     {
       ruleGroupName: 'SQLI'
       rules: [
         {
           ruleId: '942100'
           enabledState: 'Disabled'  // Disable specific rule
         }
       ]
     }
   ]
   ```

5. **Switch to Prevention Mode**
   ```bicep
   param wafMode = 'Prevention'
   ```

### Useful KQL Queries

**Top Blocked IPs**:
```kusto
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| summarize BlockCount = count() by clientIp_s
| top 10 by BlockCount
```

**Request Latency Percentiles**:
```kusto
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize
    p50 = percentile(timeTaken_d, 50),
    p95 = percentile(timeTaken_d, 95),
    p99 = percentile(timeTaken_d, 99)
  by bin(TimeGenerated, 1h)
| render timechart
```

**Error Rate Over Time**:
```kusto
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize
    Total = count(),
    Errors = countif(httpStatusCode_d >= 400)
  by bin(TimeGenerated, 5m)
| extend ErrorRate = Errors * 100.0 / Total
| render timechart
```

**Cache Hit Ratio**:
```kusto
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize
    Total = count(),
    CacheHits = countif(cacheStatus_s == "HIT")
  by bin(TimeGenerated, 1h)
| extend HitRatio = CacheHits * 100.0 / Total
| render timechart
```

### Scaling Considerations

| Scenario | Action |
|----------|--------|
| Add more origins | Add origin resources to existing origin group |
| Multiple apps | Create additional endpoints and routes |
| Custom domains | Add custom domain resources with managed certificates |
| Geographic routing | Use Front Door routing rules with geo-filtering |

---

## Troubleshooting

### Common Issues

#### 1. Deployment Fails - WAF Policy Already Exists

**Error**: `A resource with the same name already exists`

**Solution**:
```bash
# Check if WAF policy exists
az network front-door waf-policy list \
  --resource-group rg-frontdoor-prod \
  --query "[].name"

# Delete if necessary
az network front-door waf-policy delete \
  --name wafmyappprod \
  --resource-group rg-frontdoor-prod
```

#### 2. 503 Service Unavailable

**Cause**: Origin health check failing

**Solution**:
1. Verify health endpoint exists and returns 200
2. Check origin group health in portal
3. Verify App Service is running

```bash
# Test health endpoint directly
curl -I https://myapp-prod.azurewebsites.net/health
```

#### 3. WAF Blocking Legitimate Traffic

**Solution**:
1. Check WAF logs for rule details
2. Add exclusion for specific rule
3. Or switch to Detection mode temporarily

```kusto
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| where clientIp_s == "x.x.x.x"  // Your IP
| project TimeGenerated, ruleName_s, details_msg_s
```

#### 4. Security Headers Not Appearing

**Cause**: Rules Engine not attached to route

**Solution**: Verify route has `ruleSetId` parameter set

```bash
az afd route show \
  --resource-group rg-frontdoor-prod \
  --profile-name afd-myapp-prod \
  --endpoint-name fde-myapp-prod \
  --route-name route-default \
  --query "ruleSets"
```

#### 5. Alerts Not Firing

**Causes**:
- Action group not configured
- Alert threshold too high
- Diagnostic settings not enabled

**Solution**:
1. Verify `alertActionGroupId` is set
2. Check alert rule in portal
3. Verify diagnostic settings are sending logs

---

## Cost Considerations

### Estimated Monthly Costs

| Resource | SKU | Estimated Cost |
|----------|-----|----------------|
| Front Door Premium | Per request + data transfer | $35 base + usage |
| WAF Policy | Per policy + requests | ~$5-20 |
| Log Analytics | Per GB ingested | ~$2.76/GB |
| Alert Rules | Per rule | ~$0.10/rule |
| **Total Base** | | **~$50-100/month** |

### Cost Optimization Tips

1. **Right-size Log Retention**
   - Dev: 30 days
   - Prod: 90-365 days based on compliance

2. **Disable Alerts in Dev**
   ```bicep
   param enableAlertRules = false
   ```

3. **Use Standard Tier for Non-Critical**
   - If managed WAF rules not needed
   - Saves ~40% on Front Door costs

4. **Monitor Data Transfer**
   - Enable compression
   - Optimize cache settings

---

## References

### Official Documentation

- [Azure Front Door Documentation](https://learn.microsoft.com/en-us/azure/frontdoor/)
- [Azure WAF on Front Door](https://learn.microsoft.com/en-us/azure/web-application-firewall/afds/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Front Door Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.cdn/profiles)

### WAF Rule Sets

- [DRS 2.1 Rule Groups](https://learn.microsoft.com/en-us/azure/web-application-firewall/afds/waf-front-door-drs)
- [Bot Manager Rules](https://learn.microsoft.com/en-us/azure/web-application-firewall/afds/waf-front-door-policy-configure-bot-protection)
- [WAF Best Practices](https://learn.microsoft.com/en-us/azure/web-application-firewall/afds/waf-front-door-best-practices)

### Security References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Security Headers](https://securityheaders.com/)
- [Mozilla Observatory](https://observatory.mozilla.org/)

---

## Document Information

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Created | December 2025 |
| Author | Claude Code |
| Last Updated | December 2025 |

---

*This document was generated as part of an Azure Front Door deployment project using Infrastructure as Code (Bicep).*
