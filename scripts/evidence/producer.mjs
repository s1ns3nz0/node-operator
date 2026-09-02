import { createHash } from "node:crypto";

import {
  EVIDENCE_ENVELOPE_SCHEMA_VERSION,
  validateEvidenceEnvelope,
} from "@s1ns3nz0/compliance-contracts";

const DATA_POLICIES = Object.freeze({
  iac: Object.freeze({
    maximumBytes: 256 * 1024,
    fields: Object.freeze(["artifactDigest", "policyResults", "resourceSummary"]),
  }),
  kubernetes: Object.freeze({
    maximumBytes: 256 * 1024,
    fields: Object.freeze([
      "clusterName",
      "namespace",
      "workloadName",
      "imageDigests",
      "securityContextSummary",
      "networkPolicySummary",
    ]),
  }),
  "aws-config": Object.freeze({
    maximumBytes: 512 * 1024,
    fields: Object.freeze([
      "resourceType",
      "resourceId",
      "complianceType",
      "ruleName",
      "configurationItemDigest",
    ]),
  }),
  cloudtrail: Object.freeze({
    maximumBytes: 512 * 1024,
    fields: Object.freeze(["eventName", "eventSource", "eventTime", "eventId", "resourceSummary"]),
  }),
  otel: Object.freeze({
    maximumBytes: 256 * 1024,
    fields: Object.freeze([
      "metricName",
      "value",
      "unit",
      "dimensions",
      "windowStart",
      "windowEnd",
      "aggregation",
    ]),
  }),
});

const SHA256_DIGEST = /^sha256:[a-f0-9]{64}$/;
const RFC3339 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const AGGREGATIONS = new Set(["last", "sum", "average", "min", "max", "count"]);
const PRODUCER_PROHIBITED_KEY = /^(authorization(?:header|headers|token)?|auth(?:token)?|bearertoken|credentials?|accesskey(?:id)?|awsaccesskeyid|apikey|xapikey|secret(?:access)?key|awssecretaccesskey|clientsecret|sessiontoken|idtoken|jwt|oauth(?:token)?|privatekey|signingkey|password|validatorkeys?|rawlogs?|rawscannerreports?|unredactedpayloads?)$/i;

/**
 * Static signing metadata only. It contains neither an endpoint nor credentials
 * and is safe to construct before authorized infrastructure provisioning.
 */
export const SIGV4_REQUEST_CONFIGURATION = Object.freeze({
  service: "execute-api",
  region: "ap-northeast-2",
  method: "POST",
  path: "/v1/evidence",
});

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasText(value, maximum = 512) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum;
}

function hasDateTime(value) {
  return typeof value === "string" && RFC3339.test(value) && !Number.isNaN(Date.parse(value));
}

function addIssue(issues, path, message) {
  issues.push({ path, message });
}

function deepFreeze(value) {
  if (Array.isArray(value)) {
    value.forEach(deepFreeze);
  } else if (isRecord(value)) {
    Object.values(value).forEach(deepFreeze);
  }
  return Object.freeze(value);
}

function immutableJsonClone(value) {
  return deepFreeze(JSON.parse(canonicalJson(value)));
}

function findProducerProhibitedKeys(value, path, issues) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => findProducerProhibitedKeys(entry, `${path}[${index}]`, issues));
    return;
  }
  if (!isRecord(value)) return;
  for (const [key, child] of Object.entries(value)) {
    const childPath = `${path}.${key}`;
    const normalizedKey = key.replaceAll("_", "").replaceAll("-", "").toLowerCase();
    if (PRODUCER_PROHIBITED_KEY.test(normalizedKey)) {
      addIssue(issues, childPath, "contains a prohibited sensitive key");
    }
    findProducerProhibitedKeys(child, childPath, issues);
  }
}

/** Canonical JSON avoids object-key ordering differences in IDs and retries. */
export function canonicalJson(value) {
  if (value === null || typeof value === "boolean" || typeof value === "number" || typeof value === "string") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isRecord(value)) {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(",")}}`;
  }
  throw new TypeError("evidence values must be JSON-shaped");
}

/**
 * Creates an opaque, stable identifier. It deliberately exposes no source ID,
 * provenance reference, endpoint, or payload content.
 */
export function createEvidenceId(record) {
  const digest = createHash("sha256").update(canonicalJson(record)).digest("hex");
  return `evidence.sha256:${digest}`;
}

function validateAllowedFields(envelope, issues) {
  const policy = DATA_POLICIES[envelope.source.kind];
  if (!policy) return;

  const dataKeys = Object.keys(envelope.data);
  if (dataKeys.length === 0) {
    addIssue(issues, "$.data", "must contain at least one source-approved summary field");
  }
  for (const key of dataKeys) {
    if (!policy.fields.includes(key)) {
      addIssue(issues, `$.data.${key}`, `is not allowed for source kind ${envelope.source.kind}`);
    }
  }

  const byteLength = Buffer.byteLength(canonicalJson(envelope.data), "utf8");
  if (byteLength > policy.maximumBytes) {
    addIssue(issues, "$.data", `exceeds the ${policy.maximumBytes}-byte limit for ${envelope.source.kind}`);
  }
  findProducerProhibitedKeys(envelope.data, "$.data", issues);
}

function validateSummarySemantics(envelope, issues) {
  const { kind } = envelope.source;
  const data = envelope.data;
  const requireText = (key, maximum = 512) => {
    if (key in data && !hasText(data[key], maximum)) addIssue(issues, `$.data.${key}`, "must be a bounded non-empty string");
  };
  const requireDigest = (key) => {
    if (key in data && (typeof data[key] !== "string" || !SHA256_DIGEST.test(data[key]))) {
      addIssue(issues, `$.data.${key}`, "must be a lowercase sha256 digest");
    }
  };
  const requireRecord = (key) => {
    if (key in data && !isRecord(data[key])) addIssue(issues, `$.data.${key}`, "must be a summary object");
  };

  if (kind === "iac") {
    requireDigest("artifactDigest");
    requireRecord("resourceSummary");
    if ("policyResults" in data && !Array.isArray(data.policyResults) && !isRecord(data.policyResults)) {
      addIssue(issues, "$.data.policyResults", "must be a summary object or array");
    }
  }
  if (kind === "kubernetes") {
    for (const key of ["clusterName", "namespace", "workloadName"]) requireText(key, 253);
    for (const key of ["securityContextSummary", "networkPolicySummary"]) requireRecord(key);
    if ("imageDigests" in data && (!Array.isArray(data.imageDigests) || data.imageDigests.some((item) => typeof item !== "string" || !SHA256_DIGEST.test(item)))) {
      addIssue(issues, "$.data.imageDigests", "must be an array of lowercase sha256 digests");
    }
  }
  if (kind === "aws-config") {
    for (const key of ["resourceType", "resourceId", "complianceType", "ruleName"]) requireText(key);
    requireDigest("configurationItemDigest");
  }
  if (kind === "cloudtrail") {
    for (const key of ["eventName", "eventSource", "eventId"]) requireText(key);
    if ("eventTime" in data && !hasDateTime(data.eventTime)) addIssue(issues, "$.data.eventTime", "must be an RFC 3339 date-time");
    requireRecord("resourceSummary");
  }
  if (kind === "otel") {
    for (const key of ["metricName", "unit"]) requireText(key);
    if ("value" in data && (typeof data.value !== "number" || !Number.isFinite(data.value))) addIssue(issues, "$.data.value", "must be a finite number");
    if ("dimensions" in data && !isRecord(data.dimensions)) addIssue(issues, "$.data.dimensions", "must be a summary object");
    for (const key of ["windowStart", "windowEnd"]) {
      if (key in data && !hasDateTime(data[key])) addIssue(issues, `$.data.${key}`, "must be an RFC 3339 date-time");
    }
    if ("aggregation" in data && (typeof data.aggregation !== "string" || !AGGREGATIONS.has(data.aggregation))) {
      addIssue(issues, "$.data.aggregation", "must be one of last, sum, average, min, max, count");
    }
  }
}

/** Validates the Compliance Ops v1 producer boundary before a transport sees data. */
export function validateProducerEnvelope(envelope) {
  const contract = validateEvidenceEnvelope(envelope);
  if (!contract.valid) return contract;

  const issues = [];
  validateAllowedFields(contract.value, issues);
  validateSummarySemantics(contract.value, issues);
  return issues.length === 0 ? { valid: true, value: contract.value } : { valid: false, issues };
}

function disabledTransport() {
  return { status: "disabled", reason: "evidence delivery is not authorized" };
}

/**
 * Creates and validates a v1 envelope. No request is sent by this function.
 * `evidenceId` is derived from the record if the caller does not provide one.
 */
export function prepareEvidence({ source, collectedAt, provenance, data, evidenceId }) {
  const unsignedRecord = {
    schemaVersion: EVIDENCE_ENVELOPE_SCHEMA_VERSION,
    source,
    collectedAt,
    provenance,
    data,
  };
  const envelope = {
    schemaVersion: EVIDENCE_ENVELOPE_SCHEMA_VERSION,
    evidenceId: evidenceId ?? createEvidenceId(unsignedRecord),
    source,
    collectedAt,
    provenance,
    data,
  };
  const result = validateProducerEnvelope(envelope);
  if (!result.valid) {
    const error = new Error("evidence does not meet the producer boundary");
    error.issues = result.issues;
    throw error;
  }
  // The caller's source/data objects may be mutable. Return an independent,
  // deeply frozen JSON clone so retry body and its hash cannot diverge later.
  return immutableJsonClone(envelope);
}

/**
 * Delivers only through an injected transport. The default is a disabled local
 * transport. A retry is permitted only when the transport throws an error with
 * `transient === true`; responses, including non-202 HTTP responses, are terminal.
 */
export async function deliverEvidence(envelope, { transport = disabledTransport, maxAttempts = 3 } = {}) {
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 10) {
    throw new RangeError("maxAttempts must be an integer between 1 and 10");
  }
  const validation = validateProducerEnvelope(envelope);
  if (!validation.valid) {
    const error = new Error("evidence does not meet the producer boundary");
    error.issues = validation.issues;
    throw error;
  }

  const body = canonicalJson(validation.value);
  const request = Object.freeze({
    ...SIGV4_REQUEST_CONFIGURATION,
    body,
  });
  let lastError;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      const response = await transport(Object.freeze({ envelope: validation.value, request, attempt }));
      return Object.freeze({ delivery: response?.status === 202 ? "accepted" : response?.status ?? "disabled", response, attempts: attempt, evidenceId: validation.value.evidenceId });
    } catch (error) {
      lastError = error;
      if (error?.transient !== true || attempt === maxAttempts) throw error;
    }
  }
  throw lastError;
}
