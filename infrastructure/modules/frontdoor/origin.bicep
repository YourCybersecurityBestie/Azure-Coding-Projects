@description('The name of the origin')
param originName string

@description('The name of the parent Front Door profile')
param profileName string

@description('The name of the parent origin group')
param originGroupName string

@description('The hostname of the backend (App Service)')
param hostName string

@description('Whether to enable certificate name check')
param enforceCertificateNameCheck bool = true

resource profile 'Microsoft.Cdn/profiles@2024-02-01' existing = {
  name: profileName
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' existing = {
  name: originGroupName
  parent: profile
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  name: originName
  parent: originGroup
  properties: {
    hostName: hostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: hostName
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: enforceCertificateNameCheck
  }
}

output originId string = origin.id
output originName string = origin.name
