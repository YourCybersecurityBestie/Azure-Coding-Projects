@description('The name of the rule set')
param ruleSetName string

@description('The name of the parent Front Door profile')
param profileName string

@description('X-Frame-Options header value')
@allowed([
  'DENY'
  'SAMEORIGIN'
])
param xFrameOptions string = 'SAMEORIGIN'

@description('HSTS max-age in seconds (default: 1 year)')
param hstsMaxAge int = 31536000

@description('Include subdomains in HSTS')
param hstsIncludeSubdomains bool = true

@description('Enable HSTS preload')
param hstsPreload bool = false

resource profile 'Microsoft.Cdn/profiles@2024-02-01' existing = {
  name: profileName
}

// Build HSTS header value
var hstsValue = hstsPreload
  ? 'max-age=${hstsMaxAge}${hstsIncludeSubdomains ? '; includeSubDomains' : ''}; preload'
  : 'max-age=${hstsMaxAge}${hstsIncludeSubdomains ? '; includeSubDomains' : ''}'

resource ruleSet 'Microsoft.Cdn/profiles/ruleSets@2024-02-01' = {
  name: ruleSetName
  parent: profile
}

// Rule 1: Add security headers to all responses
resource securityHeadersRule 'Microsoft.Cdn/profiles/ruleSets/rules@2024-02-01' = {
  name: 'AddSecurityHeaders'
  parent: ruleSet
  properties: {
    order: 1
    conditions: []
    actions: [
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Overwrite'
          headerName: 'X-Content-Type-Options'
          value: 'nosniff'
        }
      }
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Overwrite'
          headerName: 'X-Frame-Options'
          value: xFrameOptions
        }
      }
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Overwrite'
          headerName: 'Strict-Transport-Security'
          value: hstsValue
        }
      }
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Overwrite'
          headerName: 'X-XSS-Protection'
          value: '1; mode=block'
        }
      }
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Overwrite'
          headerName: 'Referrer-Policy'
          value: 'strict-origin-when-cross-origin'
        }
      }
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Overwrite'
          headerName: 'Permissions-Policy'
          value: 'geolocation=(), microphone=(), camera=()'
        }
      }
    ]
    matchProcessingBehavior: 'Continue'
  }
}

// Rule 2: Remove server identification headers
resource removeServerHeadersRule 'Microsoft.Cdn/profiles/ruleSets/rules@2024-02-01' = {
  name: 'RemoveServerHeaders'
  parent: ruleSet
  dependsOn: [
    securityHeadersRule
  ]
  properties: {
    order: 2
    conditions: []
    actions: [
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Delete'
          headerName: 'X-Powered-By'
        }
      }
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Delete'
          headerName: 'Server'
        }
      }
    ]
    matchProcessingBehavior: 'Continue'
  }
}

output ruleSetId string = ruleSet.id
output ruleSetName string = ruleSet.name
