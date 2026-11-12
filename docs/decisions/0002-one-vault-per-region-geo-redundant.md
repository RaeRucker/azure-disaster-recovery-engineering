# ADR 0002: One GRS vault per region per subscription, with Cross Region Restore

Status: Accepted

Context. Azure VM backup requires the vault to be in the VM's region. Regional disasters require data outside the region.

Decision. One Recovery Services vault per region (per subscription), geo-redundant storage, Cross Region Restore enabled, set at creation (redundancy can't change after the first item is protected). The same four tier policies go in every vault.

Consequences. GRS costs about twice as much storage as LRS. CRR adds restore capability in the paired region, with a replication lag measured in hours. That suits Gold and Silver targets, but not Platinum, which uses ASR. Consistent policy names in every vault let Azure Policy auto-enrollment reference the same policy per region.
