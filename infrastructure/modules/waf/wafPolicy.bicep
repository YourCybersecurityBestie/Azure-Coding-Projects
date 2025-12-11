@description('The name of the WAF policy')
param wafPolicyName string

@description('WAF mode: Detection or Prevention')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Prevention'

@description('Enable request body inspection')
param requestBodyCheck bool = true

@description('Maximum request body size in KB (Premium supports up to 128KB)')
param requestBodySizeInKb int = 128

@description('Rate limit threshold (requests per minute per IP)')
@minValue(100)
@maxValue(5000)
param rateLimitThreshold int = 500

@description('Enable geo-blocking')
param enableGeoBlocking bool = false

@description('Country codes to block (ISO 3166-1 alpha-2). Only used if enableGeoBlocking is true.')
param blockedCountryCodes array = []

@description('Tags to apply to the resource')
param tags object = {}

// Build custom rules array dynamically
var rateLimitRule = {
  name: 'RateLimitRule'
  priority: 100
  enabledState: 'Enabled'
  ruleType: 'RateLimitRule'
  rateLimitDurationInMinutes: 1
  rateLimitThreshold: rateLimitThreshold
  matchConditions: [
    {
      matchVariable: 'SocketAddr'
      operator: 'IPMatch'
      negateCondition: false
      matchValue: [
        '0.0.0.0/0'
      ]
    }
  ]
  action: 'Block'
}

var geoBlockRule = {
  name: 'GeoBlockRule'
  priority: 200
  enabledState: 'Enabled'
  ruleType: 'MatchRule'
  matchConditions: [
    {
      matchVariable: 'SocketAddr'
      operator: 'GeoMatch'
      negateCondition: false
      matchValue: blockedCountryCodes
    }
  ]
  action: 'Block'
}

var customRules = enableGeoBlocking && !empty(blockedCountryCodes) ? [
  rateLimitRule
  geoBlockRule
] : [
  rateLimitRule
]

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: wafPolicyName
  location: 'Global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
      requestBodyCheck: requestBodyCheck ? 'Enabled' : 'Disabled'
      maxRequestBodySizeInKb: requestBodySizeInKb
      customBlockResponseStatusCode: 403
      customBlockResponseBody: base64('{"error":"Request blocked by WAF policy","code":"BLOCKED"}')
    }
    customRules: {
      rules: customRules
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
          ruleGroupOverrides: [
            {
              ruleGroupName: 'BadBots'
              rules: [
                {
                  ruleId: 'Bot100100'
                  enabledState: 'Enabled'
                  action: 'Block'
                }
              ]
            }
            {
              ruleGroupName: 'GoodBots'
              rules: [
                {
                  ruleId: 'Bot200100'
                  enabledState: 'Enabled'
                  action: 'Allow'
                }
              ]
            }
          ]
        }
      ]
    }
  }
}

output wafPolicyId string = wafPolicy.id
output wafPolicyName string = wafPolicy.name
