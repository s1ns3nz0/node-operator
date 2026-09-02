import { createHash } from "node:crypto";

import { deliverEvidence, prepareEvidence } from "./producer.mjs";

const SHA256_DIGEST = /^sha256:[a-f0-9]{64}$/;
const COMMIT_SHA = /^[a-f0-9]{40}$/;
const RFC3339 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const MAXIMUM_SUMMARY_STRING_LENGTH = 4096;
const MAXIMUM_SUMMARY_DEPTH = 6;
const MAXIMUM_SUMMARY_KEY_LENGTH = 128;
const MAXIMUM_SUMMARY_COLLECTION_ENTRIES = 100;
const RAW_MATERIAL_KEY = /(?:raw(?:logs?|scanner(?:reports?|output)?|report)?|(?:scanner|scan)(?:reports?|output)|unredacted(?:payload|report)?|log(?:output|dump)?)/i;
const RAW_MATERIAL_VALUE = /\b(?:raw\s+(?:scanner\s+)?reports?|raw\s+logs?|scanner\s+output|unredacted\s+(?:payload|report)|log\s+dump)\b/i;

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireKeys(value, keys, label) {
  if (!isRecord(value)) throw new TypeError(`${label} must be an object`);
  const unknown = Object.keys(value).filter((key) => !keys.includes(key));
  if (unknown.length > 0) throw new TypeError(`${label} contains unsupported fields: ${unknown.join(", ")}`);
}

function requireText(value, label, maximum = 512) {
  if (typeof value !== "string" || value.length === 0 || value.length > maximum) {
    throw new TypeError(`${label} must be a bounded non-empty string`);
  }
  return value;
}

function requireDigest(value, label) {
  if (typeof value !== "string" || !SHA256_DIGEST.test(value)) throw new TypeError(`${label} must be a sha256 digest`);
  return value;
}

function requireCollectedAt(value) {
  if (typeof value !== "string" || !RFC3339.test(value) || Number.isNaN(Date.parse(value))) {
    throw new TypeError("collectedAt must be an RFC 3339 date-time");
  }
  return value;
}

function requireSummary(value, label) {
  if (!isRecord(value) && !Array.isArray(value)) throw new TypeError(`${label} must be a compact object or array summary`);
  validateCompactSummary(value, label);
  return value;
}

/**
 * Applies the Compliance Ops service boundary before the producer is called.
 * This prevents collector-shaped raw material from reaching either a contract
 * validator or an eventual transport.
 */
function validateCompactSummary(value, label, depth = 0) {
  if (depth > MAXIMUM_SUMMARY_DEPTH) {
    throw new TypeError(`${label} exceeds the maximum summary depth of ${MAXIMUM_SUMMARY_DEPTH}`);
  }
  if (typeof value === "string") {
    if (value.length > MAXIMUM_SUMMARY_STRING_LENGTH) {
      throw new TypeError(`${label} contains a string longer than ${MAXIMUM_SUMMARY_STRING_LENGTH} characters`);
    }
    if (RAW_MATERIAL_VALUE.test(value)) throw new TypeError(`${label} contains prohibited raw collector material`);
    return;
  }
  if (Array.isArray(value)) {
    if (value.length > MAXIMUM_SUMMARY_COLLECTION_ENTRIES) {
      throw new TypeError(`${label} exceeds the maximum of ${MAXIMUM_SUMMARY_COLLECTION_ENTRIES} array entries`);
    }
    value.forEach((entry, index) => validateCompactSummary(entry, `${label}[${index}]`, depth + 1));
    return;
  }
  if (!isRecord(value)) return;
  const entries = Object.entries(value);
  if (entries.length > MAXIMUM_SUMMARY_COLLECTION_ENTRIES) {
    throw new TypeError(`${label} exceeds the maximum of ${MAXIMUM_SUMMARY_COLLECTION_ENTRIES} object entries`);
  }
  for (const [key, child] of entries) {
    if (key.length > MAXIMUM_SUMMARY_KEY_LENGTH) {
      throw new TypeError(`${label} contains a key longer than ${MAXIMUM_SUMMARY_KEY_LENGTH} characters`);
    }
    if (RAW_MATERIAL_KEY.test(key)) throw new TypeError(`${label}.${key} contains prohibited raw collector material`);
    validateCompactSummary(child, `${label}.${key}`, depth + 1);
  }
}

function opaqueSourceId(subject) {
  // The subject can include a commit, digest, or workload name. Never retain it
  // in source.id, which is observability-facing and bounded by the service.
  return `ci.sha256:${createHash("sha256").update(subject).digest("hex")}`;
}

/**
 * Converts one static workload summary to the only Kubernetes data shape that
 * the v1 producer accepts. The mapper deliberately does not read manifests,
 * logs, scan reports, endpoints, or credentials.
 */
export function mapStaticWorkloadSummary(summary) {
  const allowed = ["clusterName", "namespace", "workloadName", "imageDigests", "securityContextSummary", "networkPolicySummary"];
  requireKeys(summary, allowed, "workload summary");
  for (const key of ["clusterName", "namespace", "workloadName"]) requireText(summary[key], `workload summary.${key}`, 253);
  if (!Array.isArray(summary.imageDigests) || summary.imageDigests.length === 0) throw new TypeError("workload summary.imageDigests must be a non-empty array");
  summary.imageDigests.forEach((digest) => requireDigest(digest, "workload summary.imageDigests entry"));
  for (const key of ["securityContextSummary", "networkPolicySummary"]) {
    if (!isRecord(summary[key])) throw new TypeError(`workload summary.${key} must be an object summary`);
    validateCompactSummary(summary[key], `workload summary.${key}`);
  }
  return {
    clusterName: summary.clusterName,
    namespace: summary.namespace,
    workloadName: summary.workloadName,
    imageDigests: [...summary.imageDigests],
    securityContextSummary: summary.securityContextSummary,
    networkPolicySummary: summary.networkPolicySummary,
  };
}

function prepareIacEvidence(summary, subject, provenanceReference) {
  requireKeys(summary, ["artifactDigest", "collectedAt", "policyResults", "resourceSummary", "workloads"], "CI summary");
  const artifactDigest = requireDigest(summary.artifactDigest, "CI summary.artifactDigest");
  const collectedAt = requireCollectedAt(summary.collectedAt);
  requireSummary(summary.policyResults, "CI summary.policyResults");
  if (!isRecord(summary.resourceSummary)) throw new TypeError("CI summary.resourceSummary must be an object summary");
  validateCompactSummary(summary.resourceSummary, "CI summary.resourceSummary");
  if (summary.workloads !== undefined && !Array.isArray(summary.workloads)) throw new TypeError("CI summary.workloads must be an array");
  const iac = prepareEvidence({
    source: { kind: "iac", id: opaqueSourceId(subject) },
    collectedAt,
    provenance: { reference: provenanceReference, collectorVersion: "1.0.0" },
    data: { artifactDigest, policyResults: summary.policyResults, resourceSummary: summary.resourceSummary },
  });
  const workloads = (summary.workloads ?? []).map((workload) => prepareEvidence({
    source: { kind: "kubernetes", id: opaqueSourceId(`${subject}:${mapStaticWorkloadSummary(workload).workloadName}`) },
    collectedAt,
    provenance: { reference: provenanceReference, collectorVersion: "1.0.0" },
    data: mapStaticWorkloadSummary(workload),
  }));
  return Object.freeze([iac, ...workloads]);
}

/** Maps a compact redacted PR policy summary. No collector output is read here. */
export function mapPrEvidence(summary) {
  if (!isRecord(summary) || !COMMIT_SHA.test(summary.commitSha ?? "")) throw new TypeError("PR summary.commitSha must be a lowercase 40-character SHA");
  const { commitSha, ...compactSummary } = summary;
  return prepareIacEvidence(compactSummary, `pr:${commitSha}`, `git:${commitSha}`);
}

/** Maps a compact redacted release policy summary bound to an immutable bundle digest. */
export function mapReleaseEvidence(summary) {
  requireKeys(summary, ["artifactDigest", "collectedAt", "policyResults", "resourceSummary", "workloads"], "release summary");
  requireDigest(summary.artifactDigest, "release summary.artifactDigest");
  return prepareIacEvidence(summary, `release:${summary.artifactDigest}`, `artifact:${summary.artifactDigest}`);
}

/**
 * Test-only delivery seam. It performs no network I/O unless an explicit mock
 * transport is injected; the default transport remains disabled in producer.
 */
export async function deliverMappedEvidence(envelopes, options = {}) {
  if (!Array.isArray(envelopes)) throw new TypeError("envelopes must be an array");
  return Promise.all(envelopes.map((envelope) => deliverEvidence(envelope, options)));
}
