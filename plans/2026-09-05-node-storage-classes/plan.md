# Private node storage-class preparation

1. Server-side dry-run the reviewed Nethermind and Prysm StorageClasses.
2. Apply only those two cluster-scoped StorageClasses.
3. Read back the non-sensitive parameters and confirm no node workload or PVC was created.
4. Remove the temporary EKS administrator access.
