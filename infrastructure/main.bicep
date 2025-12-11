targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================
@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Location for regional resources')
param location string = resourceGroup().location

@description('Base name for resources')
param baseName string

@description('App Service hostname (backend origin)')
param appServiceHostName string

@description('App Service name (for access restrictions). Leave empty to skip restriction configuration.')
param appServiceName string = ''

@description('WAF mode')
@allowed(['Detection', 'Prevention'])
param wafMode string = 'Prevention'

@description('Rate limit threshold (requests per minute per IP)')
@minValue(100)
@maxValue(5000)
param rateLimitThreshold int = 500

@description('Enable geo-blocking')
param enableGeoBlocking bool = false

@description('Country codes to block (ISO 3166-1 alpha-2)')
param blockedCountryCodes array = []

@description('Query string caching behavior')
@allowed([
  'UseQueryString'
  'IgnoreQueryString'
  'IgnoreSpecifiedQueryStrings'
  'IncludeSpecifiedQueryStrings'
])
param queryStringCachingBehavior string = 'UseQueryString'

@description('X-Frame-Options header value')
@allowed([
  'DENY'
  'SAMEORIGIN'
])
param xFrameOptions string = 'SAMEORIGIN'

@description('Enable security alert rules')
param enableAlertRules bool = true

@description('Action Group ID for alert notifications (optional)')
param alertActionGroupId string = ''

@description('Log retention in days')
param logRetentionDays int = 90

@description('Health probe path')
param healthProbePath string = '/health'

@description('Tags to apply to all resources')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================
var resourceTags = union(tags, {
  environment: environment
  deployedBy: 'Bicep'
})

var frontDoorProfileName = 'afd-${baseName}-${environment}'
var frontDoorEndpointName = 'fde-${baseName}-${environment}'
var originGroupName = 'og-${baseName}'
var originName = 'origin-appservice'
var routeName = 'route-default'
var wafPolicyName = 'waf${baseName}${environment}'
var securityPolicyName = 'sp-waf-${baseName}'
var logAnalyticsName = 'law-${baseName}-${environment}'
var securityHeadersRuleSetName = 'SecurityHeaders'

// ============================================================================
// Log Analytics Workspace
// ============================================================================
module logAnalytics 'modules/monitoring/logAnalytics.bicep' = {
  name: 'deploy-logAnalytics'
  params: {
    workspaceName: logAnalyticsName
    location: location
    retentionInDays: logRetentionDays
    tags: resourceTags
  }
}

// ============================================================================
// WAF Policy
// ============================================================================
module wafPolicy 'modules/waf/wafPolicy.bicep' = {
  name: 'deploy-wafPolicy'
  params: {
    wafPolicyName: wafPolicyName
    wafMode: wafMode
    rateLimitThreshold: rateLimitThreshold
    enableGeoBlocking: enableGeoBlocking
    blockedCountryCodes: blockedCountryCodes
    tags: resourceTags
  }
}

// ============================================================================
// Front Door Profile
// ============================================================================
module frontDoorProfile 'modules/frontdoor/profile.bicep' = {
  name: 'deploy-frontDoorProfile'
  params: {
    profileName: frontDoorProfileName
    tags: resourceTags
  }
}

// ============================================================================
// Front Door Endpoint
// ============================================================================
module frontDoorEndpoint 'modules/frontdoor/endpoint.bicep' = {
  name: 'deploy-frontDoorEndpoint'
  params: {
    endpointName: frontDoorEndpointName
    profileName: frontDoorProfile.outputs.profileName
  }
}

// ============================================================================
// Origin Group
// ============================================================================
module originGroup 'modules/frontdoor/originGroup.bicep' = {
  name: 'deploy-originGroup'
  params: {
    originGroupName: originGroupName
    profileName: frontDoorProfile.outputs.profileName
    probePath: healthProbePath
    probeIntervalSeconds: 30
  }
}

// ============================================================================
// Origin (App Service)
// ============================================================================
module origin 'modules/frontdoor/origin.bicep' = {
  name: 'deploy-origin'
  params: {
    originName: originName
    profileName: frontDoorProfile.outputs.profileName
    originGroupName: originGroup.outputs.originGroupName
    hostName: appServiceHostName
  }
}

// ============================================================================
// Security Headers Rule Set
// ============================================================================
module securityHeaders 'modules/frontdoor/securityHeaders.bicep' = {
  name: 'deploy-securityHeaders'
  params: {
    ruleSetName: securityHeadersRuleSetName
    profileName: frontDoorProfile.outputs.profileName
    xFrameOptions: xFrameOptions
  }
}

// ============================================================================
// Route
// ============================================================================
module route 'modules/frontdoor/route.bicep' = {
  name: 'deploy-route'
  dependsOn: [
    origin
    securityHeaders
  ]
  params: {
    routeName: routeName
    profileName: frontDoorProfile.outputs.profileName
    endpointName: frontDoorEndpoint.outputs.endpointName
    originGroupId: originGroup.outputs.originGroupId
    queryStringCachingBehavior: queryStringCachingBehavior
    ruleSetId: securityHeaders.outputs.ruleSetId
  }
}

// ============================================================================
// Security Policy (WAF Association)
// ============================================================================
module securityPolicy 'modules/frontdoor/securityPolicy.bicep' = {
  name: 'deploy-securityPolicy'
  params: {
    securityPolicyName: securityPolicyName
    profileName: frontDoorProfile.outputs.profileName
    wafPolicyId: wafPolicy.outputs.wafPolicyId
    endpointId: frontDoorEndpoint.outputs.endpointId
  }
}

// ============================================================================
// Diagnostic Settings
// ============================================================================
module diagnosticSettings 'modules/monitoring/diagnosticSettings.bicep' = {
  name: 'deploy-diagnosticSettings'
  params: {
    diagnosticSettingName: 'diag-${frontDoorProfileName}'
    frontDoorProfileName: frontDoorProfile.outputs.profileName
    workspaceId: logAnalytics.outputs.workspaceId
  }
}

// ============================================================================
// Alert Rules (Optional)
// ============================================================================
module alertRules 'modules/monitoring/alertRules.bicep' = if (enableAlertRules) {
  name: 'deploy-alertRules'
  params: {
    alertNamePrefix: 'alert-${baseName}-${environment}'
    frontDoorProfileId: frontDoorProfile.outputs.profileId
    workspaceId: logAnalytics.outputs.workspaceId
    actionGroupId: alertActionGroupId
    location: location
    tags: resourceTags
  }
}

// ============================================================================
// App Service Access Restrictions (Optional)
// ============================================================================
module appServiceRestrictions 'modules/backend/appServiceRestriction.bicep' = if (!empty(appServiceName)) {
  name: 'deploy-appServiceRestrictions'
  params: {
    appServiceName: appServiceName
    frontDoorId: frontDoorProfile.outputs.frontDoorId
  }
}

// ============================================================================
// Outputs
// ============================================================================
output frontDoorId string = frontDoorProfile.outputs.frontDoorId
output frontDoorProfileId string = frontDoorProfile.outputs.profileId
output frontDoorEndpointHostName string = frontDoorEndpoint.outputs.endpointHostName
output frontDoorEndpointUrl string = 'https://${frontDoorEndpoint.outputs.endpointHostName}'
output wafPolicyName string = wafPolicy.outputs.wafPolicyName
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output securityHeadersRuleSetId string = securityHeaders.outputs.ruleSetId

// Output for App Service restriction configuration (for manual setup if needed)
output frontDoorIdForAppServiceRestriction string = frontDoorProfile.outputs.frontDoorId
