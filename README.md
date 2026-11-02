# Azure Disaster Recovery Engineering

Backup and disaster recovery designed from recovery objectives outward. Tiered RPO/RTO targets map to a recovery method per tier. Immutable, geo-redundant Recovery Services vaults and their Tier 1-4 policies are defined in Bicep. Azure Site Recovery handles Tier 1 failover. Around that sit the runbooks, the dependency map, and a structured regional-failure exercise that turns the targets into measurements.

| | |
|---|---|
| Project type | Independently built design and lab code. It generalizes professional work (tiered immutable backup for an audit; ASR failover testing and reporting for a CIO). No client data or configuration is included. |
| Local validation | Bicep build and lint clean; 22 Pester tests pass; PSScriptAnalyzer clean ([evidence](docs/validation/README.md)) |
| Cloud validation | Not yet deployed. No restore test or failover exercise has been run from this repository, so every RPO/RTO value here is a target, not a measurement. |

## Problem

Backups are often configured one VM at a time with default policies, never restore-tested, and stored somewhere a compromised admin account can delete. DR "plans" list VMs without the order they need to start in, the decision process, or a way to measure whether the targets were met. A ransomware event and a regional outage need different recovery mechanisms, and many designs only cover one of them.

## Approach

```mermaid
flowchart LR
    OBJ["Recovery objectives<br/>RPO / RTO per tier"] --> METH["Recovery method per tier<br/>ASR, CRR, rebuild"]
    METH --> IMPL["Implementation<br/>immutable GRS vaults,<br/>tier policies (Bicep),<br/>ASR recovery plans"]
    IMPL --> TEST["Validation<br/>restore tests,<br/>DRX-01 exercise"]
    TEST --> MEAS["Measured RTO / RPO<br/>vs targets"]
    MEAS -. "gaps" .-> OBJ
```

## Recovery tiers

| Tier | RPO target | RTO target | Method | Backup policy |
|---|---|---|---|---|
| 1 | 4 h backup / minutes replication | 4 h | ASR failover + immutable backup | Enhanced, every 4 h; 35 d / 12 w / 36 m / 10 y |
| 2 | 24 h | 24 h | Cross Region Restore | Daily; 30 d / 12 w / 12 m |
| 3 | 24 h | 72 h | CRR or rebuild from IaC | Daily; 30 d / 4 w |
| 4 | 24 h | 1 week | Rebuild from IaC | Daily; 14 d |

Why each tier uses its method, and why Tier 1 needs both replication and backup: [docs/recovery-objectives.md](docs/recovery-objectives.md).

## Architecture

```mermaid
flowchart TB
    subgraph PRI["Primary region (East US 2)"]
        VMS["Workload VMs<br/>tag BackupTier=TierN"]
        RSV1["rsv-&lt;scope&gt;-eastus2<br/>GRS, immutable, soft delete always on<br/>Tier 1-4 policies"]
        VMS -- "backup (Azure Policy auto-enroll)" --> RSV1
    end
    subgraph SEC["Secondary region (Central US, Azure pair)"]
        GRS["Geo-replicated backup data<br/>(Cross Region Restore)"]
        RSV2["rsv-&lt;scope&gt;-centralus<br/>(protects secondary workloads)"]
        REP["ASR replicas<br/>Tier 1 only"]
    end
    RSV1 -- "GRS replication" --> GRS
    VMS -- "ASR continuous replication (Tier 1)" --> REP
    RSV1 & RSV2 -- "AddonAzureBackup* logs" --> LAW["Log Analytics<br/>alerts + backup report"]
```

## Engineering decisions and tradeoffs

| Decision | Reason | Tradeoff | Record |
|---|---|---|---|
| Immutable but unlocked at deploy; lock separately with evidence | A locked vault's retention can never be reduced, so a mistake becomes permanent | A short window where immutability could be disabled (soft delete still always on) | [ADR 0001](docs/decisions/0001-immutability-locked-separately.md) |
| One GRS vault per region, CRR enabled at creation | VM backup is regional; redundancy can't change after first use | Roughly twice the backup storage cost of LRS | [ADR 0002](docs/decisions/0002-one-vault-per-region-geo-redundant.md) |
| Recovery method chosen by RTO | Backup restores can't meet a 4 h RTO for a multi-tier app; replication can, but copies logical damage | Two mechanisms to test | [ADR 0003](docs/decisions/0003-recovery-method-by-tier.md) |
| Tier policies generated from one JSON file | Same policy names in every vault, so Azure Policy auto-enrollment works per region | Changing a policy changes it everywhere (intended) | [config](config/backup-tiers.json) |
| Domain controllers not in the ASR recovery plan | Restoring DCs from replicas risks USN rollback; a standing DC in the secondary region is the supported pattern | One always-on VM in the secondary region | [dependency map](docs/dependency-map.md) |

What happens when a dependency fails mid-recovery (VM won't boot, no capacity, DNS not updated, Key Vault unreachable): [dependency-map.md](docs/dependency-map.md#failure-handling-during-failover).

## Repository contents

| Path | Purpose |
|---|---|
| [`infrastructure/main.bicep`](infrastructure/main.bicep) | Regional vault (GRS, CRR, immutability, soft delete, diagnostics) and Tier 1-4 VM policies |
| [`config/backup-tiers.json`](config/backup-tiers.json) | Tier schedules, retention, and RPO/RTO targets |
| [`docs/recovery-objectives.md`](docs/recovery-objectives.md) | Definitions, targets, regional versus logical failure |
| [`docs/dependency-map.md`](docs/dependency-map.md) | Dependencies, recovery plan groups, failure handling |
| [`docs/auto-enroll-with-azure-policy.md`](docs/auto-enroll-with-azure-policy.md) | Tag-based backup enrollment, exemptions, coverage queries |
| [`exercises/DRX-01-regional-failure/`](exercises/DRX-01-regional-failure/plan.md) | Exercise plan (preconditions, scenario, steps, verification, failure handling) and results template |
| [`runbooks/`](runbooks/) | ASR test failover, backup restore validation, failback |
| [`scripts/Get-AsrReadiness.ps1`](scripts/Get-AsrReadiness.ps1) | Read-only replication health and recovery-plan inventory |
| [`scripts/Lock-VaultImmutability.ps1`](scripts/Lock-VaultImmutability.ps1) | Irreversible lock, gated on restore-test evidence |
| [`templates/dr-test-report.md`](templates/dr-test-report.md) | Leadership report for a completed test |

## Deployment

```bash
for region in eastus2 centralus; do
  az group create -n "rg-backup-$region" -l "$region"
  az deployment group what-if -g "rg-backup-$region" --template-file infrastructure/main.bicep \
    --parameters "infrastructure/environments/$region.bicepparam"
  az deployment group create  -g "rg-backup-$region" --template-file infrastructure/main.bicep \
    --parameters "infrastructure/environments/$region.bicepparam"
done
```

Then: enable auto-enrollment ([guide](docs/auto-enroll-with-azure-policy.md)), configure ASR replication and the `rp-orders` recovery plan for Tier 1 VMs, run a [restore validation](runbooks/backup-restore-validation.md), and only then [lock immutability](scripts/Lock-VaultImmutability.ps1).

Required roles: Backup Contributor (vaults, policies), Site Recovery Contributor (ASR), Resource Policy Contributor (auto-enrollment).

## Validation

```powershell
Invoke-Pester ./tests -Output Detailed
```

The tests check that RPO targets are achievable with each tier's backup frequency, instant-restore limits per policy type, that critical tiers never have weaker targets or shorter retention, the compiled vault's resilience settings, that IaC never deploys a locked vault, the lock script's safeguards, that the readiness script is read-only, and that every documentation link resolves.

The cloud-side validation is the [restore runbook](runbooks/backup-restore-validation.md) and [DRX-01](exercises/DRX-01-regional-failure/plan.md).

## Security

Immutability and always-on soft delete protect recovery points from deletion by a compromised account. Enhanced security for soft delete is enabled. Locking requires evidence and leaves an audit trail in tags. Test restores go to isolated networks only, to avoid duplicate identities on the production network. Restored VMs contain production data: clean them up immediately after validation.

## Cost considerations

Charges come from backup protected-instance fees (per VM, by size band), backup storage (GRS, roughly twice LRS; long yearly retention dominates over time), ASR per-instance fees for Tier 1 plus replica disks and cache storage, and restore-test compute and disks (short-lived). Retention is the biggest long-term lever: 10-year yearly points for Tier 1 add up. Set them from a real requirement. Teardown: unlocked vaults can be deleted after stopping protection and deleting backup data, and soft delete keeps that data for 14 more days. Locked vaults can't have retention reduced. Don't lock lab vaults.

## Limitations and known gaps

- Not deployed. The backup policy JSON is type-checked by Bicep but hasn't been accepted by Azure yet.
- No measured RTO/RPO. DRX-01 hasn't been run.
- ASR replication and recovery plan configuration are documented procedures, not IaC.
- Database-native backup (Azure SQL long-term retention, PostgreSQL Flexible Server) is described in the objectives but not implemented here.

## Future improvements

1. Deploy to a lab subscription, run a restore validation, and publish the measured restore duration.
2. Run DRX-01 against a two-VM lab app and replace the targets table with target versus measured.
3. Add ASR (replication policy, protected items, recovery plan) to Bicep.
4. Add a Backup vault with PostgreSQL Flexible Server long-term retention to the same tiers.
