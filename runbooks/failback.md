# Runbook: Failback after a real Azure Site Recovery failover

Failback is a second, planned migration, not an undo button. Treat it with the same care as the failover.

## Preconditions

- The primary region has been healthy for an agreed period (for example 48 h), confirmed in Service Health.
- The business approved a maintenance window. Failback means a short outage while the final sync and switch happen.

## Steps

1. Commit the failover in the secondary region if you haven't already (the recovery points are no longer needed).
2. Reprotect: replicated items or recovery plan → *Re-protect*. Replication now runs secondary → primary. Wait for the initial replication to complete and for health to show *Healthy* (this can take hours for large disks).
3. Plan failover (primary as the target) in the maintenance window. *Planned* failover shuts down the source VMs and syncs the final changes, so no data is lost.
4. Validate with the same criteria as the exercise (V1-V5 in [DRX-01](../exercises/DRX-01-regional-failure/plan.md)).
5. Switch DNS or Front Door back to the primary, using low TTLs set before the window.
6. Commit, then reprotect again (primary → secondary), so the workload is protected for the next event.
7. Check backup jobs in the primary-region vault resume, and run an on-demand backup for Tier 1 items.

## Common problems

| Problem | Cause |
|---|---|
| Reprotect fails | The original VM or disks in the primary region were deleted, or the cache storage account is missing |
| Data written after failover is missing after failback | An unplanned failover was used instead of planned, or reprotect wasn't complete |
| Backups stop after failback | VMs are new resources; re-enable backup or check that Azure Policy auto-enrollment ([docs](../docs/auto-enroll-with-azure-policy.md)) covers them |
