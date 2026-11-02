<#
.SYNOPSIS
    Pre-test readiness check for Azure Site Recovery: replication health of every protected VM
    across one or more Recovery Services vaults, plus each vault's recovery plans.

.DESCRIPTION
    Run this before a DR test (and attach the output to the test report). It answers:
      - Is every VM replicating and healthy?
      - Is any VM already in a test failover that wasn't cleaned up?
      - Which VMs are in which recovery plan?

    Read-only. Writes a CSV to .\output and prints a summary.

.EXAMPLE
    .\Get-AsrReadiness.ps1

.EXAMPLE
    .\Get-AsrReadiness.ps1 -VaultName rsv-dr-eastus2, rsv-dr-centralus
#>
[CmdletBinding()]
param(
    # Limit to specific vaults. Defaults to every vault in the current subscription.
    [string[]] $VaultName,
    [string]   $OutputFolder = (Join-Path $PSScriptRoot '../output')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name Az.RecoveryServices)) {
    throw "Az.RecoveryServices is not installed. Run: Install-Module Az.RecoveryServices -Scope CurrentUser"
}
if (-not (Get-AzContext)) { throw 'No Azure context found. Run Connect-AzAccount first.' }

# Property names differ slightly between Az module versions; read them defensively.
function Get-Prop($Object, [string[]] $Names) {
    foreach ($n in $Names) {
        $p = $Object.PSObject.Properties[$n]
        if ($p -and $null -ne $p.Value -and "$($p.Value)" -ne '') { return $p.Value }
    }
    return $null
}

$vaults = @(Get-AzRecoveryServicesVault)
if ($VaultName) { $vaults = @($vaults | Where-Object Name -in $VaultName) }
if (-not $vaults) { throw 'No matching Recovery Services vaults found in the current subscription.' }

$items = [System.Collections.Generic.List[object]]::new()
$plans = [System.Collections.Generic.List[object]]::new()

foreach ($vault in $vaults) {
    Write-Information "Checking $($vault.Name) ..." -InformationAction Continue
    $null = Set-AzRecoveryServicesAsrVaultContext -Vault $vault

    foreach ($fabric in @(Get-AzRecoveryServicesAsrFabric)) {
        foreach ($container in @(Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric)) {
            foreach ($rpi in @(Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container)) {
                $errors = @(Get-Prop $rpi 'ReplicationHealthErrors') | Where-Object { $_ } |
                          ForEach-Object { Get-Prop $_ 'ErrorMessage', 'SummaryMessage' }
                $items.Add([pscustomobject]@{
                    Vault             = $vault.Name
                    VM                = Get-Prop $rpi 'FriendlyName'
                    SourceFabric      = $fabric.FriendlyName
                    ReplicationHealth = Get-Prop $rpi 'ReplicationHealth'
                    ProtectionState   = Get-Prop $rpi 'ProtectionStateDescription', 'ProtectionState'
                    TestFailoverState = Get-Prop $rpi 'TestFailoverStateDescription', 'TestFailoverState'
                    ActiveLocation    = Get-Prop $rpi 'ActiveLocation'
                    LastTestFailover  = Get-Prop $rpi 'LastSuccessfulTestFailoverTime'
                    Errors            = ($errors -join ' | ')
                })
            }
        }
    }

    foreach ($plan in @(Get-AzRecoveryServicesAsrRecoveryPlan)) {
        $vmNames = @(Get-Prop $plan 'ReplicationProtectedItems') | Where-Object { $_ } |
                   ForEach-Object { Get-Prop $_ 'FriendlyName' }
        $plans.Add([pscustomobject]@{
            Vault        = $vault.Name
            RecoveryPlan = $plan.FriendlyName
            VMs          = ($vmNames -join ', ')
        })
    }
}

# A VM is ready to test when replication is Normal, it's protected, and no test failover is open.
$notReady = @($items | Where-Object {
    $_.ReplicationHealth -ne 'Normal' -or
    ("$($_.TestFailoverState)" -notin @('', 'None', 'NotApplicable', 'Not applicable'))
})

New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$csv = Join-Path $OutputFolder ("asr-readiness-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmm'))
$items | Export-Csv -Path $csv -NoTypeInformation -Encoding utf8

Write-Information '' -InformationAction Continue
Write-Information 'Recovery plans' -InformationAction Continue
$plans | Format-Table -AutoSize -Wrap

Write-Information 'Replicated VMs' -InformationAction Continue
$items | Sort-Object Vault, VM | Format-Table Vault, VM, ReplicationHealth, ProtectionState, TestFailoverState -AutoSize

if ($notReady.Count -eq 0) {
    Write-Information "READY: all $($items.Count) replicated VMs are healthy with no open test failovers." -InformationAction Continue
} else {
    Write-Information "NOT READY: $($notReady.Count) of $($items.Count) VMs need attention before testing:" -InformationAction Continue
    $notReady | Format-Table Vault, VM, ReplicationHealth, TestFailoverState, Errors -AutoSize -Wrap
}
Write-Information "CSV: $csv" -InformationAction Continue
