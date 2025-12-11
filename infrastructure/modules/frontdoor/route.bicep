@description('The name of the route')
param routeName string

@description('The name of the parent Front Door profile')
param profileName string

@description('The name of the parent endpoint')
param endpointName string

@description('The resource ID of the origin group')
param originGroupId string

resource profile 'Microsoft.Cdn/profiles@2024-02-01' existing = {
  name: profileName
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' existing = {
  name: endpointName
  parent: profile
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  name: routeName
  parent: endpoint
  properties: {
    originGroup: {
      id: originGroupId
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
    cacheConfiguration: {
      queryStringCachingBehavior: 'IgnoreQueryString'
      compressionSettings: {
        isCompressionEnabled: true
        contentTypesToCompress: [
          'text/html'
          'text/css'
          'text/javascript'
          'application/javascript'
          'application/json'
          'application/xml'
          'text/xml'
          'image/svg+xml'
        ]
      }
    }
  }
}

output routeId string = route.id
output routeName string = route.name
