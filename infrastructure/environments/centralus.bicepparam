using '../main.bicep'

param scopeName = 'contoso-prod'
param location = 'centralus'
param workspaceId = '/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-contoso-prod-platform/providers/Microsoft.OperationalInsights/workspaces/law-contoso-prod'
param disablePublicNetworkAccess = false
