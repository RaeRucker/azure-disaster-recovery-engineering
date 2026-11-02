# Disaster Recovery Test Report

| | |
|---|---|
| Organization | [Client / business unit] |
| Test date | [Date] |
| Test lead | [Name] |
| Environment | Azure Site Recovery, [N] Recovery Services vault(s), [N] protected VMs |
| Regions | Primary: [region] → DR: [region] |
| Overall result | Passed / Passed with issues / Failed |

## Executive summary

[Two or three sentences for leadership. Example: "All 12 protected servers recovered successfully in the disaster recovery region. Applications were validated by their owners, and recovery took 1 hour 20 minutes against a 4-hour target. No production systems were affected."]

## Objectives and results

| Measure | Target | Achieved | Result |
|---|---|---|---|
| Recovery time (RTO) | [4 hours] | [1 h 20 m] | Pass |
| Data loss window (RPO) | [1 hour] | [12 minutes] | Pass |
| VMs recovered | [12] | [12] | Pass |
| Applications validated | [5] | [5] | Pass |

## Scope

| Vault | Recovery plan | VMs |
|---|---|---|
| [vault-1] | [plan-1] | [vm-a, vm-b, vm-c] |
| [vault-2] | [plan-2] | [vm-d, vm-e] |

## Timeline

| Time | Event |
|---|---|
| [09:00] | Pre-checks complete, all VMs healthy |
| [09:10] | Test failover started (recovery point: latest processed) |
| [09:42] | All VMs running in DR region |
| [10:30] | Application validation complete |
| [10:45] | Cleanup complete, replication healthy |

## Validation results

| VM / application | Boot | Sign-in | Data current | App check | Notes |
|---|---|---|---|---|---|
| [vm-a] | Pass | Pass | Pass | Pass | |

## Issues and follow-up actions

| # | Issue | Impact | Owner | Due |
|---|---|---|---|---|
| 1 | [e.g. App server needed manual DNS update in test network] | [Low] | [Name] | [Date] |

## Method

The test followed the standard DR test failover runbook: readiness checks, a test failover into an isolated network with no connection to production, validation by infrastructure and application owners, cleanup, and post-test replication checks. Production systems and replication were not affected.

## Sign-off

| Name | Role | Date |
|---|---|---|
| | Business / IT owner | |
| | DR test lead | |
