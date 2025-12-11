@description('The name of the existing App Service')
param appServiceName string

@description('The Front Door ID (from Front Door profile properties.frontDoorId)')
param frontDoorId string

@description('Allow Azure services to bypass restrictions (for deployment slots, etc.)')
param allowAzureServices bool = true

resource appService 'Microsoft.Web/sites@2023-12-01' existing = {
  name: appServiceName
}

// Configure access restrictions to only allow Front Door traffic
resource appServiceConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  name: 'web'
  parent: appService
  properties: {
    ipSecurityRestrictions: concat(
      [
        {
          name: 'AllowFrontDoor'
          description: 'Allow traffic from Azure Front Door'
          priority: 100
          action: 'Allow'
          tag: 'ServiceTag'
          ipAddress: 'AzureFrontDoor.Backend'
          headers: {
            'x-azure-fdid': [
              frontDoorId
            ]
          }
        }
      ],
      allowAzureServices ? [
        {
          name: 'AllowAzureServices'
          description: 'Allow Azure services for deployment'
          priority: 200
          action: 'Allow'
          tag: 'ServiceTag'
          ipAddress: 'AzureCloud'
        }
      ] : [],
      [
        {
          name: 'DenyAll'
          description: 'Deny all other traffic'
          priority: 2147483647
          action: 'Deny'
          ipAddress: 'Any'
        }
      ]
    )
    ipSecurityRestrictionsDefaultAction: 'Deny'
    scmIpSecurityRestrictions: [
      {
        name: 'AllowAzureServices'
        description: 'Allow Azure services for SCM/deployment'
        priority: 100
        action: 'Allow'
        tag: 'ServiceTag'
        ipAddress: 'AzureCloud'
      }
      {
        name: 'DenyAll'
        description: 'Deny all other SCM traffic'
        priority: 2147483647
        action: 'Deny'
        ipAddress: 'Any'
      }
    ]
    scmIpSecurityRestrictionsDefaultAction: 'Deny'
    scmIpSecurityRestrictionsUseMain: false
  }
}

output restrictionsApplied bool = true
