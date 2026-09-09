# Fixed-width Lease MicroTime

1. Correlate fence exit with EKS audit metadata; identify precise HTTP422 validation error.
2. Serialize renewTime with six fractional digits including trailing zeroes; regression-test all trailing-zero cases.
3. Review, merge and publish through existing fence image workflow; do not relax the fail-closed fence.
4. Stop singleton/fence, release only reviewed expired Lease, deploy reviewed digest and reactivate through existing gates.
5. Observe stable renewals beyond prior failure interval and subsequent actual duties.
