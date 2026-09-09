# Raw Base64 recovery decoding

1. Compare decoder against pinned Vault source and reproduce with synthetic non-triplet lengths.
2. Decode canonical unpadded standard Base64; convert invalid input errors to redacted CeremonyError.
3. Distinguish recovery begin, prompt, submit and decode stages without response values.
4. Test all length residues and malformed inputs, independent review, normal PR gates; stage after merge.

Sources: https://raw.githubusercontent.com/hashicorp/vault/v1.20.4/sdk/helper/roottoken/encode.go and decode.go in the same directory.
