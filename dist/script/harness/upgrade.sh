#!/usr/bin/env bash
# upgrade.sh - pull a newer harness into the consumer's subtree, then resync.
#
#   ./.agent_harness/upgrade.sh            # latest main
#   ./.agent_harness/upgrade.sh v0.2.0     # a specific release
#
# The resync step is not optional: an upgrade that only pulls leaves the root
# links pointing at skills the new version may have renamed or dropped, and
# nothing would report it -- the agents just silently stop seeing them.
set -euo pipefail

REMOTE="https://github.com/ycpss91255-docker/agent_harness.git"
REF="${1:-main}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HARNESS="${SCRIPT_DIR}"
while [[ "${HARNESS}" != "/" ]]; do
  [[ -f "${HARNESS}/.version" && -d "${HARNESS}/dist" ]] && break
  HARNESS="$(cd -- "${HARNESS}/.." && pwd -P)"
done
[[ -f "${HARNESS}/.version" ]] || { echo "upgrade.sh: subtree root not found" >&2; exit 1; }

ROOT="$(git -C "${HARNESS}" rev-parse --show-toplevel)"
[[ "${HARNESS}" != "${ROOT}" ]] || {
  echo "upgrade.sh: this is the harness repo itself, nothing to pull" >&2; exit 1; }
PREFIX="${HARNESS#"${ROOT}"/}"

cd -- "${ROOT}"
[[ -z "$(git status --porcelain)" ]] || {
  echo "upgrade.sh: working tree is dirty; commit or stash first" >&2; exit 1; }

echo "from ${REMOTE} ${REF} into ${PREFIX}"
git subtree pull --prefix="${PREFIX}" "${REMOTE}" "${REF}" --squash

# Resync AFTER the pull, so the links describe what actually landed.
exec "${HARNESS}/init.sh"
