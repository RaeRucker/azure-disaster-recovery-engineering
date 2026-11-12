# DRX-01 results: [date]

> Fill in with measured values only. Leave a field blank rather than estimating.

| Measure | Target | Measured | Met? |
|---|---|---|---|
| RTO (T0 to V1 pass) | 4 h | | |
| RPO (T0 minus newest recovered transaction) | 6 h | | |
| Failover job duration (recovery plan) | n/a | | |

## Timeline

| Time (UTC) | Event |
|---|---|
| | T0 declared |
| | Failover decision |
| | Test failover started (recovery point: ) |
| | Groups 1-2 validated |
| | Group 3 validated |
| | Group 4 validated |
| | V1 passed (RTO end) |
| | Cleanup complete |

## Verification

| # | Criterion | Result | Evidence |
|---|---|---|---|
| V1 | Service available | | |
| V2 | Data current | | |
| V3 | Integrity | | |
| V4 | Identity | | |
| V5 | Isolation | | |

## Findings and actions

| # | Finding | Impact on RTO/RPO | Action | Owner | Due |
|---|---|---|---|---|---|
