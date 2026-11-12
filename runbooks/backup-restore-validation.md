# Runbook: Backup restore validation

A backup that hasn't been restored is an assumption. This procedure proves that recovery points can be restored, are complete, and are usable. Run it quarterly per tier, after changes to backup configuration, and before locking vault immutability ([`scripts/Lock-VaultImmutability.ps1`](../scripts/Lock-VaultImmutability.ps1) requires a reference to this test).

## Scope per run

| Test | Platinum | Gold and Silver |
|---|---|---|
| Full VM restore to an isolated network | Every quarter | Every quarter, one VM per tier |
| File-level restore | Every quarter | Every half year |
| Cross Region Restore | Every half year | Yearly |
| Database point-in-time restore (SQL workload) | Every quarter | n/a |

## Procedure: full VM restore (portal)

1. Vault → Backup items → Azure Virtual Machine → select the VM → Restore VM.
2. Restore point: pick one at least 24 h old. That proves older points work, not only the latest snapshot.
3. Restore type: *Create new virtual machine*, in an isolated VNet with no peering, so the restored VM can't conflict with production (same hostname and IP).
4. Staging location: a storage account in the same region (needed for vault-tier points).
5. Record the start time. When the restore job completes, record the end time and job duration.

### Validate

| Check | How | Pass |
|---|---|---|
| Boots | Boot diagnostics screenshot; Bastion or Serial Console sign-in | Sign-in prompt reached |
| Disks complete | Disk Management / `lsblk` shows every data disk | All volumes present |
| Data current | Newest file timestamp or newest DB row vs restore point time | Within one backup interval |
| Application data | Service starts; `DBCC CHECKDB` for SQL | No errors |

### Clean up

Delete the restored VM, its disks, its NIC, and the staging blobs. Leave none running: they cost money and duplicate production identities.

## Procedure: Cross Region Restore

1. Vault → Backup items → VM → Restore VM → Secondary region. Only available when CRR is enabled (it is, in `infrastructure/main.bicep`).
2. Same validation as above, in a VNet in the paired region.
3. Record the age of the newest available secondary-region recovery point. That's the effective RPO for a regional failure using CRR.

## Record

| Field | Value |
|---|---|
| Test ID (use as the lock evidence reference) | |
| Vault / item / restore point time | |
| Restore job duration | |
| Validation results | |
| Issues found | |
