# ADR 0001: Deploy vaults immutable but unlocked; lock in a separate, evidence-gated step

Status: Accepted

Context. An immutable vault blocks early deletion of recovery points (protection against ransomware and a malicious insider). Once *locked*, immutability can't be disabled and retention can't be reduced for the life of the vault. A retention mistake becomes a permanent cost.

Decision. IaC deploys vaults with immutability *Unlocked* and soft delete *AlwaysON*. Locking is done by `scripts/Lock-VaultImmutability.ps1`, which needs a restore-test reference, verifies GRS and protected items, prompts twice, and records the evidence in the vault's tags.

Consequences. There's a window between deployment and lock where an administrator could disable immutability. That's acceptable because of soft delete (always on) and because the window is short and recorded. The lock decision is auditable from the resource itself.
