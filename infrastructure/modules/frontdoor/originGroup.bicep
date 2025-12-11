@description('The name of the origin group')
param originGroupName string

@description('The name of the parent Front Door profile')
param profileName string

@description('Health probe path')
param probePath string = '/'

@description('Health probe interval in seconds')
param probeIntervalSeconds int = 30

resource profile 'Microsoft.Cdn/profiles@2024-02-01' existing = {
  name: profileName
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  name: originGroupName
  parent: profile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: probePath
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: probeIntervalSeconds
    }
    sessionAffinityState: 'Disabled'
  }
}

output originGroupId string = originGroup.id
output originGroupName string = originGroup.name
