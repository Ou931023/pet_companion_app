const GIT_COMMIT_PATTERN = /^[0-9a-f]{40}$/i;

function resolveDeploymentRevision(env = process.env) {
  const candidate = String(env?.RENDER_GIT_COMMIT || "").trim();
  if (!GIT_COMMIT_PATTERN.test(candidate)) return null;
  return candidate.toLowerCase();
}

module.exports = {
  resolveDeploymentRevision,
};
