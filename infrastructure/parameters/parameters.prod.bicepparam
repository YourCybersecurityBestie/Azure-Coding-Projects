using '../main.bicep'

param environment = 'prod'
param location = 'eastus2'
param baseName = 'myapp'
param appServiceHostName = 'myapp-prod.azurewebsites.net'
param wafMode = 'Prevention'
param logRetentionDays = 365
param healthProbePath = '/health'
param tags = {
  project: 'MyApplication'
  costCenter: 'Production'
}
