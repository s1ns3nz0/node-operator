# Vault private release endpoint

1. Reissue the Vault leaf certificate with the private release hostname SAN.
2. Apply the separate internal-NLB Service and limited Vault ingress policy.
3. Create split-horizon private DNS alias after NLB allocation.
4. Verify TLS and AWS-auth Transit sign/verify from the private signer.
