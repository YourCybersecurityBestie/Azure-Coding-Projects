using '../main.bicep'

param environment = 'dev'
param location = 'eastus2'
param baseName = 'myapp'
param appServiceHostName = 'myapp-dev.azurewebsites.net'

// Leave empty to skip App Service restriction (useful for local testing)
// Set to your App Service name to enable origin restrictions
param appServiceName = ''

// WAF Settings - Detection mode for dev to monitor without blocking
param wafMode = 'Detection'
param rateLimitThreshold = 1000  // Higher threshold for dev

// Geo-blocking disabled by default
param enableGeoBlocking = false
param blockedCountryCodes = []

// Cache settings
param queryStringCachingBehavior = 'UseQueryString'

// Security headers - SAMEORIGIN allows iframes from same domain (useful for dev tools)
param xFrameOptions = 'SAMEORIGIN'

// Alerting - disabled for dev to reduce noise
param enableAlertRules = false
param alertActionGroupId = ''

// Logging
param logRetentionDays = 30
param healthProbePath = '/health'

param tags = {
  project: 'MyApplication'
  costCenter: 'Development'
}
