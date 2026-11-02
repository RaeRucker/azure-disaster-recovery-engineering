# Local validation results

Actual output, captured on 2026-11-02. No vaults were deployed and no failover or restore was run. Recovery targets in this repository are targets, not measurements.

## Bicep
```text
$ bicep build infrastructure/main.bicep && bicep lint infrastructure/main.bicep
$ bicep build-params infrastructure/environments/{eastus2,centralus}.bicepparam
(no errors, no warnings; Bicep 0.48.1)
```

## PSScriptAnalyzer
```text
scripts: 0 findings; tests: 0 findings
```

## Pester
```text
Pester v5.7.1
Starting discovery in 1 files.
Discovery found 22 tests in 281ms.
Running tests.
Running tests from './tests/DisasterRecovery.Tests.ps1'
Describing Backup tier design
  [+] defines four tiers with unique policy names
  [+] : RPO target is achievable with its backup frequency
  [+] : RPO target is achievable with its backup frequency
  [+] : RPO target is achievable with its backup frequency
  [+] : RPO target is achievable with its backup frequency
  [+] : instant restore days are within the policy type limit
  [+] : instant restore days are within the policy type limit
  [+] : instant restore days are within the policy type limit
  [+] : instant restore days are within the policy type limit
  [+] hourly schedules use Enhanced (V2) policies
  [+] more critical tiers never have weaker targets or shorter retention
  [+] schedule start times are on the hour or half hour
Describing Compiled vault template
  [+] compiles
  [+] uses geo-redundant storage with Cross Region Restore
  [+] enables immutability (unlocked) and always-on soft delete
  [+] never deploys a locked vault (locking is a separate, gated step)
  [+] generates one backup policy per tier from the config
  [+] sends backup and Site Recovery logs to resource-specific tables
Describing Script safeguards
  [+] Lock-VaultImmutability requires confirmation, supports -WhatIf, and demands restore-test evidence
  [+] Get-AsrReadiness is read-only (no Set/New/Remove/Start/Stop Az calls)
  [+] every script parses without errors
Describing Documentation consistency
  [+] every relative link in the docs resolves
Tests completed in 3.07s
Tests Passed: 22, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
RESULT: Passed passed=22 failed=0
```

## Not yet validated

| Check | Status |
|---|---|
| Vault and policy deployment (the backup policy schema is type-checked by Bicep, not by Azure) | Not run |
| Backup restore validation | Not run |
| DRX-01 exercise (ASR test failover) | Not run. No RTO/RPO measurement exists yet. |
