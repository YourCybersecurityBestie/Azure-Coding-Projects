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

@description('WAF mode')
@allowed(['Detection', 'Prevention'])
param wafMode string = 'Prevention'

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
// Route
// ============================================================================
module route 'modules/frontdoor/route.bicep' = {
  name: 'deploy-route'
  dependsOn: [
    origin
  ]
  params: {
    routeName: routeName
    profileName: frontDoorProfile.outputs.profileName
    endpointName: frontDoorEndpoint.outputs.endpointName
    originGroupId: originGroup.outputs.originGroupId
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
// Outputs
// ============================================================================
output frontDoorId string = frontDoorProfile.outputs.frontDoorId
output frontDoorEndpointHostName string = frontDoorEndpoint.outputs.endpointHostName
output frontDoorEndpointUrl string = 'https://${frontDoorEndpoint.outputs.endpointHostName}'
output wafPolicyName string = wafPolicy.outputs.wafPolicyName
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
