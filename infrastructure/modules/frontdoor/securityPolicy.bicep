@description('The name of the security policy')
param securityPolicyName string

@description('The name of the parent Front Door profile')
param profileName string

@description('The resource ID of the WAF policy')
param wafPolicyId string

@description('The resource ID of the endpoint to associate with WAF')
param endpointId string

resource profile 'Microsoft.Cdn/profiles@2024-02-01' existing = {
  name: profileName
}

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = {
  name: securityPolicyName
  parent: profile
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyId
      }
      associations: [
        {
          domains: [
            {
              id: endpointId
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

output securityPolicyId string = securityPolicy.id
output securityPolicyName string = securityPolicy.name
