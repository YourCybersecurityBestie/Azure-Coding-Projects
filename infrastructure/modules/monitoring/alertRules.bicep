@description('Base name for alert rules')
param alertNamePrefix string

@description('Resource ID of the Front Door profile')
param frontDoorProfileId string

@description('Resource ID of the Log Analytics workspace')
param workspaceId string

@description('Action group ID to notify (optional)')
param actionGroupId string = ''

@description('WAF block threshold per 5 minutes')
param wafBlockThreshold int = 100

@description('Origin health percentage threshold')
param originHealthThreshold int = 80

@description('Request count spike threshold (percentage increase)')
param requestSpikeThreshold int = 200

@description('Location for alert rules')
param location string

@description('Tags to apply to resources')
param tags object = {}

// WAF Blocks Alert - Triggers when WAF blocks exceed threshold
resource wafBlocksAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${alertNamePrefix}-waf-blocks'
  location: location
  tags: tags
  properties: {
    displayName: 'High WAF Block Rate'
    description: 'Alert when WAF blocks exceed ${wafBlockThreshold} requests in 5 minutes'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [
      workspaceId
    ]
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: '''
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
| where action_s == "Block"
| summarize BlockCount = count() by bin(TimeGenerated, 5m)
'''
          timeAggregation: 'Total'
          metricMeasureColumn: 'BlockCount'
          operator: 'GreaterThan'
          threshold: wafBlockThreshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: !empty(actionGroupId) ? [actionGroupId] : []
    }
  }
}

// Origin Health Alert - Triggers when origin health drops below threshold
resource originHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${alertNamePrefix}-origin-health'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when origin health drops below ${originHealthThreshold}%'
    severity: 1
    enabled: true
    scopes: [
      frontDoorProfileId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'OriginHealthPercentage'
          metricName: 'OriginHealthPercentage'
          operator: 'LessThan'
          threshold: originHealthThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: !empty(actionGroupId) ? [
      {
        actionGroupId: actionGroupId
      }
    ] : []
  }
}

// 4xx Error Rate Alert
resource clientErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${alertNamePrefix}-4xx-errors'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when 4xx error percentage exceeds 10%'
    severity: 3
    enabled: true
    scopes: [
      frontDoorProfileId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Percentage4XX'
          metricName: 'Percentage4XX'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: !empty(actionGroupId) ? [
      {
        actionGroupId: actionGroupId
      }
    ] : []
  }
}

// 5xx Error Rate Alert
resource serverErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${alertNamePrefix}-5xx-errors'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when 5xx error percentage exceeds 5%'
    severity: 1
    enabled: true
    scopes: [
      frontDoorProfileId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Percentage5XX'
          metricName: 'Percentage5XX'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: !empty(actionGroupId) ? [
      {
        actionGroupId: actionGroupId
      }
    ] : []
  }
}

// Latency Alert
resource latencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${alertNamePrefix}-high-latency'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when total latency exceeds 3 seconds'
    severity: 2
    enabled: true
    scopes: [
      frontDoorProfileId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'TotalLatency'
          metricName: 'TotalLatency'
          operator: 'GreaterThan'
          threshold: 3000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: !empty(actionGroupId) ? [
      {
        actionGroupId: actionGroupId
      }
    ] : []
  }
}

// Anomaly Detection for Request Count (unusual traffic patterns)
resource requestAnomalyAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${alertNamePrefix}-request-anomaly'
  location: location
  tags: tags
  properties: {
    displayName: 'Unusual Traffic Pattern Detected'
    description: 'Alert when request count deviates significantly from baseline'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT15M'
    scopes: [
      workspaceId
    ]
    windowSize: 'PT1H'
    criteria: {
      allOf: [
        {
          query: '''
AzureDiagnostics
| where Category == "FrontDoorAccessLog"
| summarize CurrentCount = count() by bin(TimeGenerated, 15m)
| extend Hour = datetime_part("hour", TimeGenerated)
| extend DayOfWeek = datetime_part("weekday", TimeGenerated)
| join kind=leftouter (
    AzureDiagnostics
    | where Category == "FrontDoorAccessLog"
    | where TimeGenerated > ago(7d) and TimeGenerated < ago(1h)
    | extend Hour = datetime_part("hour", TimeGenerated)
    | extend DayOfWeek = datetime_part("weekday", TimeGenerated)
    | summarize HistoricalAvg = avg(1.0) by Hour, DayOfWeek
    | extend HistoricalAvg = HistoricalAvg * 900
) on Hour, DayOfWeek
| extend PercentChange = iff(HistoricalAvg > 0, (CurrentCount - HistoricalAvg) / HistoricalAvg * 100, 0)
| where PercentChange > 200 or PercentChange < -80
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: !empty(actionGroupId) ? [actionGroupId] : []
    }
  }
}

output wafBlocksAlertId string = wafBlocksAlert.id
output originHealthAlertId string = originHealthAlert.id
output clientErrorAlertId string = clientErrorAlert.id
output serverErrorAlertId string = serverErrorAlert.id
output latencyAlertId string = latencyAlert.id
