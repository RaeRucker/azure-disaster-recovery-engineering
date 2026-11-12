// Regional backup foundation (resource group scope, one deployment per region):
//   - Recovery Services vault: GRS with Cross Region Restore, immutability
//     (Unlocked; locking is a separate, deliberate step), always-on soft delete
//   - Azure VM backup policies for each tier (Critical, Important, Supporting, NonProd) from config/backup-tiers.json
//   - Resource-specific diagnostic logs to Log Analytics (the AddonAzureBackup*
//     tables used by the alerts in cloud-observability-incident-response)
//
// Deploy per region:
//   az deployment group create -g rg-backup-eastus2 --template-file infrastructure/main.bicep \
//     --parameters infrastructure/environments/eastus2.bicepparam

@description('Short name used in the vault name, for example the subscription or workload.')
@maxLength(20)
param scopeName string

param location string = resourceGroup().location

@description('Log Analytics workspace for backup diagnostics. Empty skips diagnostics.')
param workspaceId string = ''

@description('Disable public network access to the vault (requires private endpoints for backup traffic).')
param disablePublicNetworkAccess bool = false

param tags object = {
  workload: 'backup'
  managedBy: 'bicep'
}

var tiers = loadJsonContent('../config/backup-tiers.json').tiers

// Backup schedule and retention times are full timestamps; only the time of day matters.
func scheduleTime(hhmm string) string => '2026-01-04T${hhmm}:00Z'

resource vault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: 'rsv-${scopeName}-${location}'
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'
    redundancySettings: {
      // Must be set before the first item is protected; it can't be changed afterwards.
      standardTierStorageRedundancy: 'GeoRedundant'
      crossRegionRestore: 'Enabled'
    }
    securitySettings: {
      immutabilitySettings: {
        // Unlocked: recovery points can't be deleted early, but the setting can still be
        // changed. Lock with scripts/Lock-VaultImmutability.ps1 after restore tests pass.
        state: 'Unlocked'
      }
      softDeleteSettings: {
        // AlwaysON can't be turned off once set.
        softDeleteState: 'AlwaysON'
        softDeleteRetentionPeriodInDays: 14
        enhancedSecurityState: 'Enabled'
      }
    }
  }
}

resource policies 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = [for t in tiers: {
  parent: vault
  name: t.policyName
  properties: {
    backupManagementType: 'AzureIaasVM'
    policyType: t.policyType
    instantRpRetentionRangeInDays: t.instantRestoreDays
    timeZone: 'UTC'
    schedulePolicy: t.frequency == 'Hourly' ? {
      schedulePolicyType: 'SimpleSchedulePolicyV2'
      scheduleRunFrequency: 'Hourly'
      hourlySchedule: {
        interval: t.everyHours
        scheduleWindowStartTime: scheduleTime(t.startTimeUtc)
        scheduleWindowDuration: t.windowHours
      }
    } : {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        scheduleTime(t.startTimeUtc)
      ]
    }
    retentionPolicy: union(
      {
        retentionPolicyType: 'LongTermRetentionPolicy'
        dailySchedule: {
          retentionTimes: [
            scheduleTime(t.startTimeUtc)
          ]
          retentionDuration: {
            count: t.retention.days
            durationType: 'Days'
          }
        }
      },
      t.retention.weeks > 0 ? {
        weeklySchedule: {
          daysOfTheWeek: [
            'Sunday'
          ]
          retentionTimes: [
            scheduleTime(t.startTimeUtc)
          ]
          retentionDuration: {
            count: t.retention.weeks
            durationType: 'Weeks'
          }
        }
      } : {},
      t.retention.months > 0 ? {
        monthlySchedule: {
          retentionScheduleFormatType: 'Weekly'
          retentionScheduleWeekly: {
            daysOfTheWeek: [
              'Sunday'
            ]
            weeksOfTheMonth: [
              'First'
            ]
          }
          retentionTimes: [
            scheduleTime(t.startTimeUtc)
          ]
          retentionDuration: {
            count: t.retention.months
            durationType: 'Months'
          }
        }
      } : {},
      t.retention.years > 0 ? {
        yearlySchedule: {
          retentionScheduleFormatType: 'Weekly'
          monthsOfYear: [
            'January'
          ]
          retentionScheduleWeekly: {
            daysOfTheWeek: [
              'Sunday'
            ]
            weeksOfTheMonth: [
              'First'
            ]
          }
          retentionTimes: [
            scheduleTime(t.startTimeUtc)
          ]
          retentionDuration: {
            count: t.retention.years
            durationType: 'Years'
          }
        }
      } : {}
    )
  }
}]

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(workspaceId)) {
  name: 'diag-to-law'
  scope: vault
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [for category in [
      'CoreAzureBackup'
      'AddonAzureBackupJobs'
      'AddonAzureBackupPolicy'
      'AddonAzureBackupStorage'
      'AddonAzureBackupProtectedInstance'
      'AzureSiteRecoveryJobs'
      'AzureSiteRecoveryReplicatedItems'
    ]: {
      category: category
      enabled: true
    }]
  }
}

output vaultName string = vault.name
output vaultId string = vault.id
output policyIds array = [for (t, i) in tiers: policies[i].id]
