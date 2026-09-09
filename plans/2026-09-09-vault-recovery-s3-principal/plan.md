# Isolated snapshot authorization repair

1. Compare metadata-only host/local HEAD and AWS gateway documentation.
2. Move gateway role scope from Principal to mandatory exact aws:PrincipalArn condition; preserve object/version scope.
3. Add negative regression cases, validate Terraform, independently review and publish ordinary PR.
4. After merge, inspect refreshed saved plan, apply only the isolated endpoint policy, and repeat exact-version HEAD (never download payload through agent).
5. User performs recovery-key ceremony only after preflight passes.

Reference: https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html#vpc-endpoint-policies-principals
