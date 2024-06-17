param cacheName string = ''

@description('Resource ID of log analytics workspace.')
param diagnosticWorkspaceId string

@description('Optional. The name of logs that will be streamed. "allLogs" includes all possible logs for the resource. Set to `[]` to disable log collection.')
param diagnosticLogCategoriesToEnable array = [
  'allLogs'
]

@description('Optional. The name of metrics that will be streamed.')
param diagnosticMetricsToEnable array = [
  'AllMetrics'
]

var diagnosticsLogs = [{ 
  categoryGroup: 'allLogs'
  enabled: true
 }]

var diagnosticsMetrics = [for metric in diagnosticMetricsToEnable: {
  category: metric
  timeGrain: null
  enabled: true
}]

resource redisCache 'Microsoft.Cache/Redis@2023-08-01' existing = {
  name: cacheName
}

resource cache_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${cacheName}-diagnostics'
  scope: redisCache
  properties: {
    workspaceId:  diagnosticWorkspaceId
    metrics: diagnosticsMetrics
    logs: diagnosticsLogs
  }
}
