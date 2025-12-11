using '../main.bicep'

param environment = 'prod'
param location = 'eastus2'
param baseName = 'myapp'
param appServiceHostName = 'myapp-prod.azurewebsites.net'

// Set to your App Service name to enable origin restrictions
// This ensures only Front Door can reach your App Service
param appServiceName = 'myapp-prod'

// WAF Settings - Prevention mode for production
param wafMode = 'Prevention'
param rateLimitThreshold = 500  // Stricter rate limit for production

// Geo-blocking - Enable and configure if needed
// Example: Block traffic from specific countries
param enableGeoBlocking = false
param blockedCountryCodes = [
  // Uncomment and add country codes as needed (ISO 3166-1 alpha-2)
  // 'XX'
  // 'YY'
]

// Cache settings - UseQueryString for correctness
param queryStringCachingBehavior = 'UseQueryString'

// Security headers - SAMEORIGIN if your app uses iframes, DENY for maximum security
param xFrameOptions = 'SAMEORIGIN'

// Alerting - enabled for production monitoring
param enableAlertRules = true
// Set your Action Group ID to receive notifications
// Example: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/microsoft.insights/actionGroups/{ag-name}'
param alertActionGroupId = ''

// Logging - longer retention for production
param logRetentionDays = 365
param healthProbePath = '/health'

param tags = {
  project: 'MyApplication'
  costCenter: 'Production'
  securityContact: 'security@example.com'
}
