@description('The name of the Front Door profile')
param profileName string

@description('Tags to apply to the resource')
param tags object = {}

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: profileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

output profileId string = frontDoorProfile.id
output profileName string = frontDoorProfile.name
output frontDoorId string = frontDoorProfile.properties.frontDoorId
