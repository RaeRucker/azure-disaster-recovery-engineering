# DRX-01: Regional failure exercise (primary region unavailable)

> Exercise plan. Running it is the only way to turn the RTO/RPO targets into measured results. Until it has been run, no recovery time in this repository is a measurement. Record results in [`results-template.md`](results-template.md).

| | |
|---|---|
| Type | Test failover (non-disruptive: production keeps running) |
| Scope | Order processing application: DC (standing replica), SQL, 2 app servers, web tier |
| Primary → secondary | East US 2 → Central US |
| Targets under test | Platinum: RTO 4 h, RPO 6 h ([recovery objectives](../../docs/recovery-objectives.md)) |
| Duration | Half a day, including cleanup |

## Objectives

1. Measure actual RTO from the declaration to a successful external test transaction.
2. Measure actual RPO: the age of the data in the recovered database at the moment of failover.
3. Prove the recovery plan order and its manual actions work as documented.
4. Find undocumented dependencies.

## Preconditions (go / no-go)

| # | Check | Evidence |
|---|---|---|
| P1 | All protected VMs replication health *Healthy*, no open test failovers | `scripts/Get-AsrReadiness.ps1` output = READY |
| P2 | Isolated test VNet in the secondary region, not peered to production | VNet peerings list (empty) |
| P3 | A standing DC exists in the test VNet, or a DC test-failover copy is planned (isolated only) | |
| P4 | Latest Platinum backup restore test is under 90 days old | Restore test record ([runbook](../../runbooks/backup-restore-validation.md)) |
| P5 | Business owner approved the window. Application owners available for validation. | Change record |
| P6 | Rollback (cleanup) procedure reviewed | This document, *Cleanup* |

Any "no" is a no-go. Reschedule rather than run a partial test.

## Failure scenario

At T0 the exercise lead declares: *"East US 2 is unavailable for compute, storage, and networking. Recovery time estimate from Microsoft: unknown."* No component in the primary region may be used during the exercise.

## Recovery steps

| Step | Action | Owner | Record |
|---|---|---|---|
| 1 | Declare the disaster (T0); start the timeline | Incident commander | T0 |
| 2 | Confirm the scope, and decide to fail over (in a real event: Service Health, business impact) | IC + business owner | Decision time |
| 3 | Run Test failover on recovery plan `rp-orders`, latest processed recovery point, isolated test VNet | DR lead | Start time; recovery point timestamp (for RPO) |
| 4 | Group 1-2 validation: DC reachable; SQL databases online | DR lead | Time |
| 5 | Group 3: app servers start; connection string script action runs | DR lead | Time |
| 6 | Group 4: web tier; the DNS change is *simulated* (test hosts file entry in the isolated VNet) | DR lead | Time |
| 7 | Application owners run the validation script | App owners | Pass/fail per check; time (= RTO end) |

## Verification criteria

| # | Criterion | Pass condition |
|---|---|---|
| V1 | Service available | A test order submitted through the web tier completes end to end |
| V2 | Data current | The newest order in the recovered DB is no older than the RPO target relative to T0 |
| V3 | Integrity | `DBCC CHECKDB` on the recovered database reports 0 errors |
| V4 | Identity | Application service accounts authenticate against the DC |
| V5 | Isolation | No traffic from the test VNet reached production (NSG flow logs / peering absent) |

## Failure handling

| If | Then |
|---|---|
| A VM fails to fail over | Retry once with the latest app-consistent point; otherwise CRR-restore that VM and note the RTO impact |
| A validation check fails | Stop the clock for that criterion, record the finding, and continue with the rest. A partial result is still a result. |
| Anything touches production | Abort: run cleanup immediately and escalate |
| RTO target exceeded | Continue to completion (the measurement still matters), then mark the objective *not met* |

## Cleanup (rollback)

1. Cleanup test failover on `rp-orders`, with notes.
2. Confirm cleanup jobs succeed and `Get-AsrReadiness.ps1` returns READY.
3. Delete any temporary resources created for the test (tagged `exercise=DRX-01`).

## Post-recovery assessment

Fill in [`results-template.md`](results-template.md): measured RTO and RPO vs targets, a timeline, the verification results, issues, and actions. Publish within 5 business days, and update runbooks with anything that was missing.

## Failback (real event only)

A test failover needs no failback. After a real failover: reprotect (replicate back from secondary to primary), wait for the initial sync, plan a maintenance window, fail back, validate as above, then reprotect primary to secondary again. See [runbooks/failback.md](../../runbooks/failback.md).
