import assert from "node:assert/strict";
import test from "node:test";

import {
  SIGV4_REQUEST_CONFIGURATION,
  createEvidenceId,
  deliverEvidence,
  prepareEvidence,
  validateProducerEnvelope,
} from "./producer.mjs";

function validOtel(overrides = {}) {
  return {
    source: { kind: "otel", id: "hoodi-node-01" },
    collectedAt: "2026-09-02T00:00:00Z",
    provenance: { reference: "otel:up:hoodi-node-01:20260902T000000Z", collectorVersion: "1.0.0" },
    data: { metricName: "up", value: 1, unit: "1", aggregation: "last" },
    ...overrides,
  };
}

test("prepares stable opaque IDs and immutable SigV4 metadata without an endpoint", () => {
  const first = prepareEvidence(validOtel());
  const second = prepareEvidence(validOtel());
  assert.equal(first.evidenceId, second.evidenceId);
  assert.match(first.evidenceId, /^evidence\.sha256:[a-f0-9]{64}$/);
  assert.equal(first.evidenceId.includes("hoodi-node-01"), false);
  assert.deepEqual(SIGV4_REQUEST_CONFIGURATION, { service: "execute-api", region: "ap-northeast-2", method: "POST", path: "/v1/evidence" });
  assert.equal(Object.isFrozen(SIGV4_REQUEST_CONFIGURATION), true);
  assert.equal("endpoint" in SIGV4_REQUEST_CONFIGURATION, false);
  assert.equal(Object.isFrozen(first), true);
});

test("prepared evidence is a deep immutable clone whose retry body cannot drift", async () => {
  const input = validOtel({ data: { metricName: "up", value: 1, unit: "1", dimensions: { zone: "a" } } });
  const envelope = prepareEvidence(input);
  const initialId = envelope.evidenceId;
  const bodies = [];

  input.data.dimensions.zone = "b";
  assert.equal(envelope.data.dimensions.zone, "a");
  assert.equal(Object.isFrozen(envelope.data), true);
  assert.equal(Object.isFrozen(envelope.data.dimensions), true);
  assert.throws(() => { envelope.data.dimensions.zone = "c"; }, TypeError);

  await deliverEvidence(envelope, { transport: async ({ request }) => {
    bodies.push(request.body);
    return { status: 202 };
  } });
  assert.equal(envelope.evidenceId, initialId);
  assert.equal(bodies.length, 1);
  assert.match(bodies[0], /"zone":"a"/);
});

test("canonical IDs are unaffected by JSON key ordering", () => {
  const first = createEvidenceId({ b: [2, { z: true, a: null }], a: "one" });
  const second = createEvidenceId({ a: "one", b: [2, { a: null, z: true }] });
  assert.equal(first, second);
});

test("enforces source allow-lists, byte caps, and source semantics before transport", () => {
  const accepted = prepareEvidence(validOtel());
  assert.equal(validateProducerEnvelope(accepted).valid, true);
  assert.throws(() => prepareEvidence(validOtel({ data: { metricName: "up", value: 1, unit: "1", rawLogs: "never" } })), /producer boundary/);
  assert.throws(() => prepareEvidence(validOtel({ data: { metricName: "up", value: 1, unit: "1", dimensions: { authorizationHeader: "never" } } })), /producer boundary/);
  for (const key of ["authToken", "bearerToken", "apiKey", "awsSecretAccessKey", "rawScannerReport", "client_secret", "private-key"]) {
    assert.throws(() => prepareEvidence(validOtel({ data: { metricName: "up", value: 1, unit: "1", dimensions: { [key]: "never" } } })), /producer boundary/);
  }
  assert.throws(() => prepareEvidence(validOtel({ data: { metricName: "up", value: "one", unit: "1" } })), /producer boundary/);
  assert.throws(() => prepareEvidence(validOtel({ data: { metricName: "up", value: 1, unit: "1", extra: true } })), /producer boundary/);
  assert.throws(() => prepareEvidence(validOtel({ data: { metricName: "up", value: 1, unit: "1", dimensions: { detail: "x".repeat(256 * 1024) } } })), /producer boundary/);
});

test("default delivery is disabled and never invokes a network transport", async () => {
  const result = await deliverEvidence(prepareEvidence(validOtel()));
  assert.equal(result.delivery, "disabled");
  assert.equal(result.attempts, 1);
  assert.equal(result.response.reason, "evidence delivery is not authorized");
});

test("retries only explicitly transient thrown errors with one unchanged body and ID", async () => {
  const envelope = prepareEvidence(validOtel());
  const received = [];
  const transient = new Error("temporary transport failure");
  transient.transient = true;
  const result = await deliverEvidence(envelope, {
    transport: async ({ request, envelope: sent, attempt }) => {
      received.push({ body: request.body, evidenceId: sent.evidenceId, attempt });
      if (attempt < 3) throw transient;
      return { status: 202, evidenceId: sent.evidenceId };
    },
  });
  assert.equal(result.delivery, "accepted");
  assert.equal(result.attempts, 3);
  assert.deepEqual(received.map(({ evidenceId }) => evidenceId), [envelope.evidenceId, envelope.evidenceId, envelope.evidenceId]);
  assert.equal(new Set(received.map(({ body }) => body)).size, 1);
});

test("does not retry HTTP responses or unmarked thrown errors", async () => {
  const envelope = prepareEvidence(validOtel());
  let calls = 0;
  const response = await deliverEvidence(envelope, { transport: async () => { calls += 1; return { status: 503 }; } });
  assert.equal(response.delivery, 503);
  assert.equal(calls, 1);
  await assert.rejects(
    deliverEvidence(envelope, { transport: async () => { throw new Error("do not retry"); } }),
    /do not retry/,
  );
});
