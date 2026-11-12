# Auto-enroll VMs into the right backup tier with Azure Policy

Goal: a VM tagged `BackupTier = Tier1` is automatically protected by the Tier 1 policy in its region's vault, with nobody clicking Enable backup. Untagged VMs show up as non-compliant, so gaps are visible.

## How it fits together

```text
VM created with tag BackupTier=Tier2
          │
          ▼
Azure Policy assignment (one per tier per region)
  "Configure backup on virtual machines with a given tag
   to an existing recovery services vault in the same location"
          │  DeployIfNotExists
          ▼
VM protected in rsv-<sub>-<region> with pol-vm-tier2-daily
```

The built-in policy works per region, because a VM can only back up to a vault in its own region. You need one assignment for each tier × region pair.

## 1. Tag the VMs

| Tag | Values |
|---|---|
| `BackupTier` | `Tier1`, `Tier2`, `Tier3`, `Tier4` |

To require the tag on new VMs, also assign the built-in policy Require a tag on resources (Deny), or Inherit a tag from the resource group if missing (Modify) if you set tiers at the resource group level.

## 2. Assign the auto-enroll policy (portal)

1. In the Azure portal, open Policy → Authoring → Definitions.
2. Filter Category = Backup and open Configure backup on virtual machines with a given tag to an existing recovery services vault in the same location.
3. Select Assign.
4. Basics: set the scope to the subscription. Name the assignment `backup-<tier>-<region>`, for example `backup-tier1-eastus`.
5. Parameters:
   - Location of VMs: the region, for example `eastus`
   - Inclusion tag name: `BackupTier`
   - Inclusion tag values: `Tier1`
   - Backup policy: pick `pol-vm-tier1-6h` from that region's vault
6. Remediation: check Create a remediation task so existing tagged VMs get enrolled too, and keep Create a Managed Identity checked.
7. Review + create.

Repeat for each tier and region.

> The assignment's managed identity needs Virtual Machine Contributor and Backup Contributor at the assignment scope. The portal grants these automatically when you create the assignment there. If you deploy with code, grant them yourself.

## 3. Exclude what shouldn't be backed up this way

| Resource | Why exclude | How |
|---|---|---|
| AKS node pools (`MC_*` resource groups) | Nodes are disposable. Protect AKS with AKS Backup or GitOps instead. | Policy exemption on the `MC_*` resource groups, category *Waiver* |
| Databricks managed resource groups | Managed by the platform | Exemption |
| Ephemeral build agents / scale-set instances | Rebuilt from images | Don't tag them; untagged VMs are never enrolled |

Exemptions show up in compliance reports with a reason, so auditors can see that an exclusion was deliberate, not missed.

## 4. Check coverage

Policy → Compliance shows tagged VMs that still aren't protected. To find VMs with no tier tag, run this in Resource Graph Explorer:

```kusto
resources
| where type =~ 'microsoft.compute/virtualmachines'
| where isempty(tags.BackupTier)
| where resourceGroup !startswith 'mc_'
| project subscriptionId, resourceGroup, name, location
```

And VMs that aren't protected at all:

```kusto
resources
| where type =~ 'microsoft.compute/virtualmachines'
| extend vmId = tolower(id)
| join kind=leftouter (
    recoveryservicesresources
    | where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'
    | where properties.backupManagementType == 'AzureIaasVM'
    | extend vmId = tolower(tostring(properties.sourceResourceId))
    | project vmId, protectedBy = tostring(properties.policyName)
  ) on vmId
| where isempty(protectedBy)
| project subscriptionId, resourceGroup, name, location, tier = tostring(tags.BackupTier)
```
