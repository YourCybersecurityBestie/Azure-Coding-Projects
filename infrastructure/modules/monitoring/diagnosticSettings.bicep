@description('The name of the diagnostic setting')
param diagnosticSettingName string

@description('The name of the Front Door profile')
param frontDoorProfileName string

@description('The resource ID of the Log Analytics workspace')
param workspaceId string

@description('Enable access logs')
param enableAccessLogs bool = true

@description('Enable WAF logs')
param enableWafLogs bool = true

@description('Enable health probe logs')
param enableHealthProbeLogs bool = true

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' existing = {
  name: frontDoorProfileName
}

resource diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingName
  scope: frontDoorProfile
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: enableAccessLogs
      }
      {
        category: 'FrontDoorHealthProbeLog'
        enabled: enableHealthProbeLogs
      }
      {
        category: 'FrontDoorWebApplicationFirewallLog'
        enabled: enableWafLogs
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output diagnosticSettingId string = diagnosticSetting.id
