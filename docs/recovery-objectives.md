# Recovery objectives

> RPO and RTO values on this page are design targets. They describe what each tier is built to achieve. No measured recovery times are recorded in this repository: measurements come from exercises, and are recorded in each exercise's results file ([DRX-01](../exercises/DRX-01-regional-failure/plan.md)).

## Definitions

| Term | Meaning | Determined by |
|---|---|---|
| RPO (recovery point objective) | Maximum acceptable data loss, measured backwards from the failure | Backup or replication frequency |
| RTO (recovery time objective) | Maximum acceptable time from declaring a disaster to the service working again | Recovery method, automation, dependencies, people |
| MTD | Maximum tolerable downtime before business harm becomes severe | Business owner |

RTO counts the whole path: detection, the decision to fail over, the technical recovery, dependency recovery, and validation. The technical restore alone is usually the shortest part.

## Targets by tier

| Tier | Workloads | RPO target | RTO target | Primary recovery method | Why this method |
|---|---|---|---|---|---|
| Platinum | Customer-facing, financial, identity | 6 h (backup); minutes (ASR replication) | 4 h | Azure Site Recovery failover to the secondary region. Backup (every 6 hours, Enhanced policy) covers logical corruption. | Restoring many VMs from backup can't meet a 4 h RTO. Replication can. |
| Gold | Internal line-of-business | 24 h | 24 h | Cross Region Restore (CRR) from the GRS vault in the paired region | No replication cost; restore time fits the target |
| Silver | Supporting services | 24 h | 72 h | CRR, or rebuild from infrastructure as code plus a data restore | Rebuild is often faster and cleaner than restoring a whole VM |
| Bronze | Dev and test | 24 h | 1 week | Rebuild from IaC | Data rarely needs recovery |

Tier definitions and retention are in [`config/backup-tiers.json`](../config/backup-tiers.json). The tests check that RPO targets match each tier's backup frequency.

## Two kinds of failure, two kinds of recovery

| Failure | Example | Replication (ASR) helps? | Backup helps? |
|---|---|---|---|
| Regional or infrastructure | Region outage, zone failure, host failure | Yes: fail over to the replica | Yes, via CRR (slower) |
| Logical | Ransomware, accidental deletion, bad data migration | No. Replication copies the damage within minutes. | Yes: restore a point in time before the damage |

Platinum therefore needs both: ASR for the RTO, and immutable backups for logical recovery. That is why the vaults are immutable and soft delete is always on. A compromised administrator can't delete the recovery points that ransomware recovery depends on.

## Regional considerations

- Paired region: GRS replicates to the region's Azure pair (for example East US 2 to Central US). CRR restores there. Check the pair for your primary region.
- Capacity: a regional outage moves many customers to the same paired region at once. Deploy capacity reservations, or accept the risk that VM sizes may be unavailable during a large event.
- Dependencies across regions: identity (domain controllers), DNS, Key Vault, and network connectivity must already exist in the secondary region, or recover first. See the [dependency map](dependency-map.md).
- GRS replication lag: geo-replicated backup data trails the primary. Microsoft documents an RPO for CRR in hours, not minutes. Gold targets assume that.
