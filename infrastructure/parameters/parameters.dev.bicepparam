using '../main.bicep'

param environment = 'dev'
param location = 'eastus2'
param baseName = 'myapp'
param appServiceHostName = 'myapp-dev.azurewebsites.net'
param wafMode = 'Detection'
param logRetentionDays = 30
param healthProbePath = '/health'
param tags = {
  project: 'MyApplication'
  costCenter: 'Development'
}
