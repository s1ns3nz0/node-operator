# Validator CloudWatch monitoring

Status: collection architecture accepted by the user on 2026-09-14 with
"ㅇㅇ 저렇게 승인할게". Local implementation is authorized. Image publication
and live resource mutation remain subject to explicit target-level authority.

## Outcome

An operator can distinguish validator participation, node readiness, signing
health and missing telemetry in CloudWatch. A running Pod or successful signing
request must never be presented as a finalized on-chain attestation.

Ethereum Launchpad recommends monitoring with Prometheus/Grafana, not CloudWatch
specifically: https://launchpad.ethereum.org/checklist. CloudWatch is the user's
chosen presentation platform. AWS supports Prometheus ingestion with its agent:
https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights-Prometheus.html.

## Proposed implementation

Use a private CloudWatch Agent Prometheus collector without adding AMP or Grafana.
Select and approve its exact image through the existing release supply-chain
boundary before packaging. Inventory metric names against the pinned client
versions; do not copy names from unrelated versions or infer emitted metrics
from a dashboard template.

Dashboard sections:

1. Telemetry freshness and collection errors, independent of workload health.
2. Consensus/execution sync, head/finalized progress and connected peers.
3. Validator status, balance/effective balance, expected participation and
   finalized attestation outcomes. Verified chain evidence remains distinct from
   client-reported successful submissions. Unobserved epochs remain unknown,
   not missed; missed requires complete authoritative coverage.
4. Signer successes/rejections and fence connection activity, labeled according
   to what the underlying logs actually prove.
5. Infrastructure health and scoped workload/Vault audit delivery. Do not display
   raw Vault audit records, credentials or private key material in widgets.

Export only an explicit allowlist with bounded deployment/network/validator-set
dimensions. Do not use slots, request IDs or signing roots as metric dimensions.
Do not enable EC2 detailed monitoring. Missing/stale data must remain visible;
never fill a missing health measurement with a healthy zero. Dashboard presence
does not replace immutable audit storage or existing three-duty acceptance.

## Delivery and acceptance

### Inspected baseline and unresolved inputs

The current source labels Prysm Beacon v7.1.8 and Nethermind
1.39.3-chiseled in `deploy/prysm/statefulset.yaml` and
`deploy/nethermind/statefulset.yaml`. These labels locate the source versions;
they do not independently prove the contents of their pinned image digests.
Client metric contracts must be checked against those actual release inputs.

`.ci/validator/approved-runtime-images.json` contains a Fluent Bit approval,
and `scripts/release/installer_artifact_inventory.py` projects it as
`validator-log-collector`. The inspected runtime and GitOps catalogs do not
contain an approved CloudWatch Agent image. Therefore the proposed agent is a
new release dependency, not an already approved digest that can be deployed now.
The repository's reviewed image approval process must bind its digest before
use; no implementation may silently substitute a latest tag.

The proposed collector runs inside private EKS with only explicitly selected
internal scrape targets. Its AWS delivery uses a dedicated workload identity,
not a Vault administrator token, node-wide credentials or static AWS keys.
Exact network paths and IAM actions remain a design output to review before
implementation; this proposal does not authorize wildcard egress or permissions.

For chain evidence, reuse the existing finalized-attestation observer's
verification rules in `scripts/release/observe-hoodi-finalized-attestations.py`.
That observer currently writes evidence, not continuous CloudWatch metrics.
A continuous producer and explicit outage/coverage handling are still needed.
Do not treat its three-duty deployment check as perpetual monitoring.

Proposed operational defaults for acceptance are a 60-second scrape interval
and a distinct stale state after 180 seconds without a successful sample.
These are project defaults, not Ethereum protocol recommendations. They must
not override chain finality timing or classify an unseen attestation as missed.
Dimensions are restricted to one selected Deployment, Network and ValidatorSet;
only explicitly enumerated component/outcome values may add series.

No live account, cluster or publication target is authorized by this document.
Before live verification, the user must approve the exact account, Region,
deployment and resource changes. The acceptance record must identify those
targets and the immutable bundle/image identities, then show sample timestamp,
metric dimensions and widget result without secret/log payload disclosure.

The local acceptance matrix must include successful ingestion, stopped
collector, unreachable scrape endpoint, rejected AWS delivery, client submission
without finalized proof, and incomplete chain coverage. The first case must
produce the intended data; failures must show unavailable/stale/unknown rather
than healthy or an invented zero. Exact emitted metric names and thresholds
must be recorded before dashboard implementation is admitted.

- Terraform owns dashboard, required metric delivery permissions and outputs.
- The downloaded release includes the actual collector assets and the installer
  applies them; metric endpoints remain private under scoped NetworkPolicies.
- Existing approved log collector deployment must be connected, not assumed.
- Test source parsing, dimensions, missing/stale/invalid data and aggregation.
- Demonstrate pinned client endpoint -> collector -> CloudWatch metric -> widget;
  test unavailable sources explicitly. Static JSON tests alone are insufficient.
- Reconcile every widget with its actual producer before claiming completion.
- Live resource mutation, image publication and release publication require
  explicit target-level execution authority. Local tests do not prove delivery.

UC-1 through UC-5 remain excluded. No validator key replacement, deposit,
activation, automatic recovery or security-boundary weakening is authorized by
this dashboard task.
