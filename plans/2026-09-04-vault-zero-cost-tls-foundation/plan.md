# Zero-cost Vault internal TLS foundation

1. Pin the supported cert-manager chart and all runtime images from official
   release metadata, then add them to the existing digest-reviewed private ECR
   mirror boundary.
2. Define a namespaced self-signed bootstrap issuer, a Vault-only CA
   certificate, and a Vault server certificate. The cert-manager controller,
   rather than an operator or Git, creates the resulting Secret objects.
3. Define the fail-closed ingress boundary for future Vault pods and document
   the required client labels, RBAC restriction, private mirror, and renewal
   procedure.
4. Validate only locally. A separate, explicitly approved saved-plan task must
   mirror/install/apply in the documented order and confirm object names and
   readiness without reading Secret data.
