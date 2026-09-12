import { readFile } from 'node:fs/promises';
import path from 'node:path';

export const CONFIG_FILE = 'harness.config.json';

export async function readConfig(root) {
  const file = path.join(root, CONFIG_FILE);
  let parsed;
  try {
    parsed = JSON.parse(await readFile(file, 'utf8'));
  } catch (error) {
    throw new Error(`Cannot read ${CONFIG_FILE}: ${error.message}`);
  }
  return parsed;
}

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const string = (value) => typeof value === 'string' && value.trim().length > 0;

/** Deliberately dependency-free subset validation; the JSON Schema is the public contract. */
export function validateConfig(config) {
  const errors = [];
  const requireObject = (value, name) => { if (!isObject(value)) errors.push(`${name} must be an object`); };
  if (!isObject(config)) return ['configuration must be an object'];
  if (config.schemaVersion !== 1) errors.push('schemaVersion must be 1');
  requireObject(config.project, 'project');
  if (!string(config.project?.name)) errors.push('project.name must be a non-empty string');
  if (typeof config.project?.description !== 'string') errors.push('project.description must be a string');
  requireObject(config.paperthin, 'paperthin');
  for (const key of ['source', 'ref']) if (!string(config.paperthin?.[key])) errors.push(`paperthin.${key} must be a non-empty string`);
  requireObject(config.models, 'models');
  requireObject(config.models?.tiers, 'models.tiers');
  for (const tier of ['sol', 'terra', 'luna']) {
    if (!isObject(config.models?.tiers?.[tier]) || !string(config.models.tiers[tier].model)) errors.push(`models.tiers.${tier}.model must be a non-empty string`);
  }
  if (!string(config.models?.fallback)) errors.push('models.fallback must be a non-empty string');
  if (typeof config.models?.recordFallbacks !== 'boolean') errors.push('models.recordFallbacks must be a boolean');
  requireObject(config.policies, 'policies');
  for (const key of ['externalActions', 'worktreesRequiredForMutations', 'humanApprovalForPromotedLearnings', 'ambiguityResolution', 'admissibility']) {
    if (!(key in (config.policies ?? {}))) errors.push(`policies.${key} is required`);
  }
  const admissibility = config.policies?.admissibility;
  if (!isObject(admissibility)) errors.push('policies.admissibility must be an object');
  else {
    for (const key of ['enabled', 'runAfterDurableArtifactChange', 'recordSkippedChecks']) if (typeof admissibility[key] !== 'boolean') errors.push(`policies.admissibility.${key} must be a boolean`);
    if (!string(admissibility.orchestrator)) errors.push('policies.admissibility.orchestrator must be a non-empty string');
    if (!Number.isInteger(admissibility.safeCorrectionAttemptsBeforeEscalation) || admissibility.safeCorrectionAttemptsBeforeEscalation < 0) errors.push('policies.admissibility.safeCorrectionAttemptsBeforeEscalation must be a non-negative integer');
    if (!isObject(admissibility.unexplainable) || !string(admissibility.unexplainable.check) || typeof admissibility.unexplainable.blocksCompletion !== 'boolean') errors.push('policies.admissibility.unexplainable must define check and blocksCompletion');
    if (!isObject(admissibility.unreasonable) || !Array.isArray(admissibility.unreasonable.checks) || admissibility.unreasonable.checks.some((check) => !string(check)) || !string(admissibility.unreasonable.blocksWhen)) errors.push('policies.admissibility.unreasonable must define checks and blocksWhen');
    if (!isObject(admissibility.unacceptable) || !string(admissibility.unacceptable.check) || typeof admissibility.unacceptable.blocksCompletion !== 'boolean' || typeof admissibility.unacceptable.continueSafeRemainder !== 'boolean') errors.push('policies.admissibility.unacceptable must define check, blocksCompletion, and continueSafeRemainder');
  }
  const showDontTell = config.policies?.showDontTell;
  if (!isObject(showDontTell)) errors.push('policies.showDontTell must be an object');
  else {
    for (const key of ['enabled', 'requiredForObservableBehavior', 'independentReview', 'commitSmallArtifacts', 'userAcceptanceBlocksOnlyWhenConfigured']) if (typeof showDontTell[key] !== 'boolean') errors.push(`policies.showDontTell.${key} must be a boolean`);
    if (!string(showDontTell.reportFile)) errors.push('policies.showDontTell.reportFile must be a non-empty string');
  }
  const solidReview = config.policies?.solidReview;
  if (!isObject(solidReview)) errors.push('policies.solidReview must be an object');
  else {
    for (const key of ['enabled', 'preImplementationRequired', 'blocksMaterialFindings']) if (typeof solidReview[key] !== 'boolean') errors.push(`policies.solidReview.${key} must be a boolean`);
    for (const key of ['appliesTo', 'defaultTier', 'reportFile']) if (!string(solidReview[key])) errors.push(`policies.solidReview.${key} must be a non-empty string`);
    if (!Array.isArray(solidReview.integrationRerunTriggers) || solidReview.integrationRerunTriggers.some((trigger) => !string(trigger))) errors.push('policies.solidReview.integrationRerunTriggers must be an array of non-empty strings');
  }
  const requirements = config.policies?.requirementsSteward;
  if (!isObject(requirements)) errors.push('policies.requirementsSteward must be an object');
  else {
    for (const key of ['enabled', 'opensGitHubIssue', 'requiresExplicitApproval', 'taskRequiresApprovedProductSpec']) if (typeof requirements[key] !== 'boolean') errors.push(`policies.requirementsSteward.${key} must be a boolean`);
    for (const key of ['invocation', 'defaultTier', 'canonicalDirectory', 'usesProcess']) if (!string(requirements[key])) errors.push(`policies.requirementsSteward.${key} must be a non-empty string`);
  }
  const roleQuality = config.policies?.roleQuality;
  if (!isObject(roleQuality)) errors.push('policies.roleQuality must be an object');
  else for (const tier of ['luna', 'terra', 'sol']) {
    const role = roleQuality[tier];
    if (!isObject(role)) { errors.push(`policies.roleQuality.${tier} must be an object`); continue; }
    for (const key of ['requiredSkills', 'conditionalSkills', 'controlledSkills', 'requiredEvidence']) if (key in role && (!Array.isArray(role[key]) || role[key].some((value) => !string(value)))) errors.push(`policies.roleQuality.${tier}.${key} must be an array of non-empty strings`);
    if (!Array.isArray(role.requiredEvidence) || role.requiredEvidence.length === 0) errors.push(`policies.roleQuality.${tier}.requiredEvidence must be a non-empty array`);
  }
  const steward = config.policies?.knowledgeSteward;
  if (!isObject(steward)) errors.push('policies.knowledgeSteward must be an object');
  else {
    if (typeof steward.enabled !== 'boolean' || typeof steward.readOnly !== 'boolean') errors.push('policies.knowledgeSteward enabled and readOnly must be boolean');
    for (const key of ['invocation', 'defaultTier', 'defaultPersistence', 'canonicalWikiDirectory', 'reentrySkill', 'driftAudit']) if (!string(steward[key])) errors.push(`policies.knowledgeSteward.${key} must be a non-empty string`);
    if (!Array.isArray(steward.auditTriggers) || steward.auditTriggers.some((trigger) => !string(trigger))) errors.push('policies.knowledgeSteward.auditTriggers must be an array of non-empty strings');
  }
  const ambiguity = config.policies?.ambiguityResolution;
  if (!isObject(ambiguity)) errors.push('policies.ambiguityResolution must be an object');
  else {
    for (const key of ['enabled', 'requiresExplicitUserAcceptance', 'blockAffectedNodeWhenUnresolved']) if (typeof ambiguity[key] !== 'boolean') errors.push(`policies.ambiguityResolution.${key} must be a boolean`);
    if (!Number.isInteger(ambiguity.safeCorrectionAttemptsBeforeInterview) || ambiguity.safeCorrectionAttemptsBeforeInterview < 0) errors.push('policies.ambiguityResolution.safeCorrectionAttemptsBeforeInterview must be a non-negative integer');
    for (const key of ['thinAskResolver', 'intentChecker', 'riskCarver', 'interviewer', 'consolidator', 'decisionChallenge', 'adversarialPlanCheck', 'decisionRecordsDirectory', 'productSpecsDirectory']) if (!string(ambiguity[key])) errors.push(`policies.ambiguityResolution.${key} must be a non-empty string`);
    if (!Array.isArray(ambiguity.hateCheckpoints) || ambiguity.hateCheckpoints.some((checkpoint) => !string(checkpoint))) errors.push('policies.ambiguityResolution.hateCheckpoints must be an array of non-empty strings');
  }
  requireObject(config.adapters, 'adapters');
  if (!Array.isArray(config.adapters?.active)) errors.push('adapters.active must be an array');
  requireObject(config.adapters?.definitions, 'adapters.definitions');
  for (const name of config.adapters?.active ?? []) {
    if (!string(name)) errors.push('adapters.active values must be non-empty strings');
    else if (!isObject(config.adapters.definitions?.[name])) errors.push(`active adapter '${name}' has no definition`);
  }
  return errors;
}
