import assert from "node:assert/strict";
import test from "node:test";

import { deliverMappedEvidence, mapPrEvidence, mapReleaseEvidence } from "./ci-mapper.mjs";

const digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const commitSha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

function compactSummary(overrides = {}) {
  return {
    artifactDigest: digest,
    collectedAt: "2026-09-02T12:00:00Z",
    policyResults: { decision: "allow", violations: 0 },
    resourceSummary: { terraformModules: 1, manifests: 2 },
    workloads: [{
      clusterName: "hoodi",
      namespace: "node-operator",
      workloadName: "nethermind",
      imageDigests: [digest],
      securityContextSummary: { runAsNonRoot: true, readOnlyRootFilesystem: true },
      networkPolicySummary: { defaultDeny: true, allowedEgress: ["dns", "p2p"] },
    }],
    ...overrides,
  };
}

test("maps compact redacted PR summaries to IAC and Kubernetes v1 envelopes", () => {
  const evidence = mapPrEvidence({ ...compactSummary(), commitSha });
  assert.equal(evidence.length, 2);
  assert.equal(evidence[0].source.kind, "iac");
  assert.match(evidence[0].source.id, /^ci\.sha256:[a-f0-9]{64}$/);
  assert.equal(evidence[0].source.id.includes(commitSha), false);
  assert.deepEqual(evidence[0].data, { artifactDigest: digest, policyResults: { decision: "allow", violations: 0 }, resourceSummary: { terraformModules: 1, manifests: 2 } });
  assert.equal(evidence[1].source.kind, "kubernetes");
  assert.equal(evidence[1].data.workloadName, "nethermind");
  assert.equal(Object.isFrozen(evidence[1]), true);
});

test("maps release summaries using only immutable digest provenance", () => {
  const evidence = mapReleaseEvidence(compactSummary({ workloads: [] }));
  assert.equal(evidence.length, 1);
  assert.match(evidence[0].source.id, /^ci\.sha256:[a-f0-9]{64}$/);
  assert.equal(evidence[0].source.id.includes(digest), false);
  assert.equal(evidence[0].provenance.reference, `artifact:${digest}`);
});

test("rejects raw or unsupported collector material before it reaches producer", () => {
  assert.throws(() => mapPrEvidence({ ...compactSummary(), commitSha, rawLogs: "never" }), /unsupported fields/);
  assert.throws(() => mapReleaseEvidence(compactSummary({ scannerReport: { raw: "never" } })), /unsupported fields/);
  assert.throws(() => mapPrEvidence({ ...compactSummary(), commitSha: "not-a-sha" }), /40-character SHA/);
  assert.throws(() => mapReleaseEvidence(compactSummary({ artifactDigest: "sha256:bad" })), /sha256 digest/);
  assert.throws(() => mapReleaseEvidence(compactSummary({ workloads: [{ ...compactSummary().workloads[0], endpoint: "https://never" }] })), /unsupported fields/);
  assert.throws(() => mapPrEvidence(compactSummary({
    commitSha,
    policyResults: { decision: "allow", nested: { rawScannerReport: "never" } },
  })), /prohibited raw collector material/);
  assert.throws(() => mapPrEvidence(compactSummary({
    commitSha,
    resourceSummary: { terraformModules: 1, nested: { note: "raw scanner report follows" } },
  })), /prohibited raw collector material/);
});

test("enforces service summary depth and string limits before calling the producer", () => {
  const tooDeep = {};
  let cursor = tooDeep;
  for (let level = 0; level <= 6; level += 1) {
    cursor.next = {};
    cursor = cursor.next;
  }
  assert.throws(() => mapPrEvidence(compactSummary({
    commitSha,
    policyResults: tooDeep,
  })), /maximum summary depth/);
  assert.throws(() => mapReleaseEvidence(compactSummary({
    resourceSummary: { detail: "x".repeat(4097) },
  })), /longer than 4096/);
});

test("enforces service nested key and collection limits before calling the producer", () => {
  assert.throws(() => mapPrEvidence(compactSummary({
    commitSha,
    policyResults: { ["k".repeat(129)]: "too long" },
  })), /key longer than 128/);
  assert.throws(() => mapPrEvidence(compactSummary({
    policyResults: Object.fromEntries(Array.from({ length: 101 }, (_, index) => [`entry${index}`, index])),
    commitSha,
  })), /maximum of 100 object entries/);
  assert.throws(() => mapReleaseEvidence(compactSummary({
    policyResults: Array.from({ length: 101 }, (_, index) => index),
  })), /maximum of 100 array entries/);
});

test("derives deterministic bounded opaque source IDs for long workload subjects", () => {
  const workloadName = "w".repeat(253);
  const summary = compactSummary({ workloads: [{ ...compactSummary().workloads[0], workloadName }] });
  const first = mapPrEvidence({ ...summary, commitSha });
  const second = mapPrEvidence({ ...summary, commitSha });
  assert.equal(first[1].source.id, second[1].source.id);
  assert.equal(first[1].source.id.length <= 256, true);
  assert.equal(first[1].source.id.includes(workloadName), false);
  assert.equal(first[1].source.id.includes(commitSha), false);
});

test("mapped delivery is disabled by default and uses injected mocks only", async () => {
  const envelopes = mapPrEvidence({ ...compactSummary(), commitSha });
  const disabled = await deliverMappedEvidence(envelopes);
  assert.deepEqual(disabled.map((result) => result.delivery), ["disabled", "disabled"]);

  const delivered = [];
  const accepted = await deliverMappedEvidence(envelopes, {
    transport: async ({ envelope, request }) => {
      delivered.push({ id: envelope.evidenceId, request });
      return { status: 202, evidenceId: envelope.evidenceId };
    },
  });
  assert.deepEqual(accepted.map((result) => result.delivery), ["accepted", "accepted"]);
  assert.equal(delivered.length, 2);
  assert.equal(delivered.every(({ request }) => request.path === "/v1/evidence" && !Object.hasOwn(request, "endpoint")), true);
});
