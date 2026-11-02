# DR Test Failover Runbook (Azure Site Recovery)

Purpose: prove that protected workloads can be recovered in the DR region within the agreed RTO/RPO, without affecting production.

Frequency: at least twice a year, and after any major change to replicated workloads.
Estimated time: 2–4 hours, depending on how many VMs and how much application testing is needed.

| Role | Responsibility |
|---|---|
| DR test lead (runs this runbook) | Executes the test, records timings, writes the report |
| Application owners | Validate their applications in the isolated test network |
| Escalation engineer | First escalation if a VM fails to fail over or boot |
| Client / business contact | Approves the test window and signs off on results |

---

## Phase 0: Plan (1–2 weeks before)

- [ ] Agree on the test window with the business contact and announce it to stakeholders.
- [ ] Confirm the isolated test virtual network exists in the DR region and is not peered or connected to production. A test failover VM has the same hostname and IP as production, and connecting the two would cause conflicts.
- [ ] Confirm what's needed inside the test network for app validation (for example a test domain controller, DNS, or a jump box). A domain-joined app usually needs a DC failed over or restored into the same isolated network.
- [ ] Get the application test checklist from each app owner (what "working" means for them).
- [ ] Record the RTO and RPO targets being tested.

## Phase 1: Pre-checks (day of the test)

1. Run the readiness script and save the CSV for the report:
   ```powershell
   .\scripts\Get-AsrReadiness.ps1
   ```
2. In the portal, check each vault: Recovery Services vault → Site Recovery → Replicated items.
   - [ ] Every VM shows Replication health: Healthy and Status: Protected.
   - [ ] Failover readiness has no warnings.
   - [ ] No VM shows a leftover test failover that needs cleanup.
3. Note the latest recovery point for each VM. This is the RPO you'll achieve.

> Stop here if anything is unhealthy. Fix replication or escalate first. Testing from a broken state proves nothing.

## Phase 2: Run the test failover

Use the recovery plan if one exists. It fails VMs over in the right order (for example DC, then database, then app servers) and is what a real disaster would use.

1. Go to Vault → Site Recovery → Recovery Plans, select the plan → Test failover.
   (For a single VM: Replicated items → VM → Test failover.)
2. Recovery point:
   - Latest processed (low RTO): the usual choice
   - Latest app-consistent: for databases that need application consistency
3. Azure virtual network: select the isolated test network. Double-check this. Never select the production network.
4. Select OK and record the start time.
5. Watch progress under Monitoring → Site Recovery jobs and record the time each VM finishes.

## Phase 3: Validate

Connect through the test network's jump box (or Bastion in the test VNet).

Infrastructure checks (DR test lead):

- [ ] Every VM in the plan is Running in the DR region.
- [ ] Each VM boots and accepts a sign-in.
- [ ] Disks are attached and the data volumes are present.
- [ ] Data is current to the recovery point (check a recent file, log entry, or database row).
- [ ] Name resolution works inside the test network.

Application checks (app owners): work through each owner's checklist and record pass/fail with notes.

Record: total time from failover start to "application validated." That is the achieved RTO.

## Phase 4: Clean up

Cleanup deletes the test VMs and their resources. Production replication is unaffected.

1. Recovery Plans → the plan → Cleanup test failover (or per VM from Replicated items).
2. Enter notes on the outcome and check Testing is complete, then select OK.
3. Confirm the cleanup job succeeds under Site Recovery jobs.
4. Re-run `Get-AsrReadiness.ps1` and confirm every VM is back to Healthy with no open test failovers.

## Phase 5: Report

Fill in [`../templates/dr-test-report.md`](../templates/dr-test-report.md) and send it to the business contact and technical team within two business days.

---

## Escalation

| Situation | Action |
|---|---|
| A VM fails the test failover job | Check the job error under Site Recovery jobs. Retry once. If it fails again, escalate to the escalation engineer with the job ID. |
| A VM fails to boot or is unreachable | Check Boot diagnostics and Serial console in the DR region, and capture screenshots for the report. |
| Replication is unhealthy before the test | Do not test. Open a ticket, fix replication, and reschedule. |
| Cleanup fails | Re-run cleanup. If it still fails, delete the test resource group manually after confirming it holds only test resources, then mark the test complete. |
| Anything that could touch production | Stop, clean up, and escalate immediately. |
