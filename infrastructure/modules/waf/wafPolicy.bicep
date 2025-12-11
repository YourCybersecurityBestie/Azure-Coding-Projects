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

@description('Tags to apply to the resource')
param tags object = {}

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
      customBlockResponseBody: base64('{"error":"Request blocked by WAF policy"}')
    }
    customRules: {
      rules: [
        {
          name: 'RateLimitRule'
          priority: 100
          enabledState: 'Enabled'
          ruleType: 'RateLimitRule'
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: 1000
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'RegEx'
              matchValue: [
                '.*'
              ]
            }
          ]
          action: 'Block'
        }
      ]
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
