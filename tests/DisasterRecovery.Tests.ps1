#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
<#
    Static tests: backup tier design rules, compiled vault template, and script safeguards.
    Run: Invoke-Pester ./tests -Output Detailed   (requires the Bicep CLI on PATH)
#>

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $script:config = Get-Content -Raw (Join-Path $root 'config/backup-tiers.json') | ConvertFrom-Json
    $script:tiers = $script:config.tiers

    $out = Join-Path ([System.IO.Path]::GetTempPath()) "dr-tests-$PID.json"
    & bicep build (Join-Path $root 'infrastructure/main.bicep') --outfile $out 2>&1 | Out-Null
    $script:buildExit = $LASTEXITCODE
    $script:template = Get-Content -Raw $out | ConvertFrom-Json -Depth 100
    $res = $script:template.resources
    $script:resources = @(if ($res -is [System.Management.Automation.PSCustomObject]) { $res.PSObject.Properties.Value } else { $res })
    $script:vault = $script:resources | Where-Object type -EQ 'Microsoft.RecoveryServices/vaults'
    $script:policy = $script:resources | Where-Object type -EQ 'Microsoft.RecoveryServices/vaults/backupPolicies'
    $script:root = $root
}

Describe 'Backup tier design' {
    It 'defines four tiers with unique policy names' {
        $script:tiers.Count | Should -Be 4
        ($script:tiers.policyName | Sort-Object -Unique).Count | Should -Be 4
    }

    It '<name>: RPO target is achievable with its backup frequency' -ForEach @(
        (Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/backup-tiers.json') | ConvertFrom-Json).tiers
    ) {
        $interval = if ($_.frequency -eq 'Hourly') { $_.everyHours } else { 24 }
        $_.targets.rpoHours | Should -BeGreaterOrEqual $interval -Because 'a backup every N hours cannot deliver an RPO below N hours'
    }

    It '<name>: instant restore days are within the policy type limit' -ForEach @(
        (Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/backup-tiers.json') | ConvertFrom-Json).tiers
    ) {
        $max = if ($_.policyType -eq 'V2') { 30 } else { 5 }
        $_.instantRestoreDays | Should -BeGreaterOrEqual 1
        $_.instantRestoreDays | Should -BeLessOrEqual $max
    }

    It 'hourly schedules use Enhanced (V2) policies' {
        foreach ($t in $script:tiers | Where-Object frequency -EQ 'Hourly') { $t.policyType | Should -Be 'V2' }
    }

    It 'more critical tiers never have weaker targets or shorter retention' {
        for ($i = 1; $i -lt $script:tiers.Count; $i++) {
            $hi = $script:tiers[$i - 1]; $lo = $script:tiers[$i]
            $hi.targets.rtoHours | Should -BeLessOrEqual $lo.targets.rtoHours
            $hi.targets.rpoHours | Should -BeLessOrEqual $lo.targets.rpoHours
            $hi.retention.days   | Should -BeGreaterOrEqual $lo.retention.days
        }
    }

    It 'schedule start times are on the hour or half hour' {
        foreach ($t in $script:tiers) { $t.startTimeUtc | Should -Match '^([01]\d|2[0-3]):(00|30)$' }
    }
}

Describe 'Compiled vault template' {
    It 'compiles' { $script:buildExit | Should -Be 0 }

    It 'uses geo-redundant storage with Cross Region Restore' {
        $script:vault.properties.redundancySettings.standardTierStorageRedundancy | Should -Be 'GeoRedundant'
        $script:vault.properties.redundancySettings.crossRegionRestore | Should -Be 'Enabled'
    }

    It 'enables immutability (unlocked) and always-on soft delete' {
        $script:vault.properties.securitySettings.immutabilitySettings.state | Should -Be 'Unlocked'
        $script:vault.properties.securitySettings.softDeleteSettings.softDeleteState | Should -Be 'AlwaysON'
    }

    It 'never deploys a locked vault (locking is a separate, gated step)' {
        ($script:template | ConvertTo-Json -Depth 50) | Should -Not -Match "'Locked'|`"Locked`""
    }

    It 'generates one backup policy per tier from the config' {
        $script:policy.copy.count | Should -Match 'tiers'
    }

    It 'sends backup and Site Recovery logs to resource-specific tables' {
        $diag = $script:resources | Where-Object type -EQ 'Microsoft.Insights/diagnosticSettings'
        $diag.properties.logAnalyticsDestinationType | Should -Be 'Dedicated'
        ($diag | ConvertTo-Json -Depth 20) | Should -Match 'AddonAzureBackupJobs'
    }
}

Describe 'Script safeguards' {
    It 'Lock-VaultImmutability requires confirmation, supports -WhatIf, and demands restore-test evidence' {
        $cmd = Get-Command (Join-Path $script:root 'scripts/Lock-VaultImmutability.ps1')
        $meta = [System.Management.Automation.CommandMetadata]::new($cmd)
        $meta.SupportsShouldProcess | Should -BeTrue
        $meta.ConfirmImpact | Should -Be 'High'
        $cmd.Parameters['RestoreTestReference'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
    }

    It 'Get-AsrReadiness is read-only (no Set/New/Remove/Start/Stop Az calls)' {
        $text = Get-Content -Raw (Join-Path $script:root 'scripts/Get-AsrReadiness.ps1')
        # Set-AzRecoveryServicesAsrVaultContext only selects the vault for the local session.
        $text | Should -Not -Match '(Set|New|Remove|Start|Stop|Update)-AzRecoveryServices(?!AsrVaultContext)'
    }

    It 'every script parses without errors' {
        foreach ($f in Get-ChildItem (Join-Path $script:root 'scripts') -Filter *.ps1) {
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty -Because $f.Name
        }
    }
}

Describe 'Documentation consistency' {
    It 'every relative link in the docs resolves' {
        $broken = foreach ($md in Get-ChildItem $script:root -Recurse -Filter *.md) {
            foreach ($m in [regex]::Matches((Get-Content -Raw $md.FullName), '\]\(([^)#:]+)(#[^)]*)?\)')) {
                $target = Join-Path $md.DirectoryName $m.Groups[1].Value
                if (-not (Test-Path $target)) { "$($md.Name) -> $($m.Groups[1].Value)" }
            }
        }
        $broken | Should -BeNullOrEmpty
    }
}
