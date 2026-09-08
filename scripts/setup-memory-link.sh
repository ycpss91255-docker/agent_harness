#!/usr/bin/env bash


# setup-memory-link.sh — link Claude Code per-project memory dir to a
# repo-tracked location so memory ports with the repo across machines.
#
# Claude Code stores per-project memory at:
#   ~/.claude/projects/<encoded-workspace-path>/memory/
# where <encoded-workspace-path> is the absolute workspace path with
# every "/" replaced by "-" (e.g. /home/user/workspace/docker ->
# -home-user-workspace-docker).
#
# This script:
#   1. Resolves the current workspace path (cwd by default, or --workspace
#      <path>). Computes the encoded form.
#   2. Verifies <workspace>/.claude/memory exists as a real directory.
#   3. Checks the existing memory location:
#      - missing -> create symlink
#      - already a symlink to the right target -> skip (idempotent)
#      - symlink to a different target -> replace
#      - real directory with NO content not already in repo memory -> ok
#        to replace (rm + symlink); content-diff detected via diff
#      - real directory with NEW content -> refuse unless --force; user
#        should merge new entries into the repo first
#   4. Creates the symlink and prints verification.
#
# Usage:
#   setup-memory-link.sh [options]
#
# Options:
#   --workspace <path>   Override workspace root (default: $(pwd))
#   --home <path>        Override $HOME (mainly for tests)
#   --force              Replace existing memory dir even if its content
#                        differs from the repo copy. Old dir is moved to
#                        <path>.backup-<timestamp> first.
#   --dry-run            Print what would happen; make no changes.
#   -h, --help           Show this help.
#
# Idempotent: re-running on a correct setup is a no-op.

set -euo pipefail

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

err() {
  printf '[setup-memory-link] ERROR: %s\n' "$*" >&2
}

info() {
  printf '[setup-memory-link] %s\n' "$*"
}

# Encode an absolute path the way Claude Code does it for the projects
# subdirectory: leading + every internal "/" -> "-".
encode_workspace_path() {
  local path="$1"
  # Strip trailing slash if any
  path="${path%/}"
  # Replace all "/" AND "_" with "-".
  # 實測:/home/user/workspace/gitlab_runner 對應的目錄是
  # -home-user-workspace-gitlab-runner（底線也會被換掉）。
  path="${path//\//-}"
  printf '%s' "${path//_/-}"
}

main() {
  local workspace="" home_dir="" force=0 dry_run=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --workspace) workspace="$2"; shift 2 ;;
      --home) home_dir="$2"; shift 2 ;;
      --force) force=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      *) err "unknown arg: $1"; usage; exit 2 ;;
    esac
  done

  if [[ -z "${workspace}" ]]; then
    workspace="$(pwd -P)"
  fi
  if [[ ! -d "${workspace}" ]]; then
    err "workspace not a directory: ${workspace}"
    exit 2
  fi
  # Canonicalise.
  workspace="$(cd -- "${workspace}" && pwd -P)"

  if [[ -z "${home_dir}" ]]; then
    home_dir="${HOME:-}"
  fi
  if [[ -z "${home_dir}" || ! -d "${home_dir}" ]]; then
    err "HOME not a directory: ${home_dir:-<unset>}"
    exit 2
  fi

  local repo_memory="${workspace}/.claude/memory"
  # 記憶不進版控，clone 後這個目錄不存在，直接建起來。
  if [[ ! -d "${repo_memory}" ]]; then
    if (( dry_run )); then
      info "dry-run: would mkdir -p ${repo_memory}"
    else
      mkdir -p -- "${repo_memory}"
      info "created ${repo_memory}"
    fi
  fi

  local encoded
  encoded="$(encode_workspace_path "${workspace}")"
  local project_dir="${home_dir}/.claude/projects/${encoded}"
  local link_path="${project_dir}/memory"

  info "workspace:    ${workspace}"
  info "repo memory:  ${repo_memory}"
  info "link target:  ${link_path}"
  info ""

  # Already correctly linked? -> skip
  if [[ -L "${link_path}" ]]; then
    local current_target
    current_target="$(readlink -- "${link_path}")"
    # Resolve relative target against link's parent.
    if [[ "${current_target}" != /* ]]; then
      current_target="$(cd -- "$(dirname -- "${link_path}")" && cd -- "${current_target}" && pwd -P)"
    fi
    if [[ "${current_target}" == "${repo_memory}" ]]; then
      info "OK: symlink already points at ${repo_memory} -- nothing to do"
      return 0
    fi
    info "existing symlink target differs: ${current_target}"
  fi

  # Existing dir-as-dir handling.
  if [[ -d "${link_path}" && ! -L "${link_path}" ]]; then
    local diff_summary=""
    diff_summary="$(diff -rq -- "${link_path}" "${repo_memory}" 2>/dev/null || true)"
    if [[ -n "${diff_summary}" ]]; then
      info "existing memory dir differs from repo copy:"
      printf '%s\n' "${diff_summary}" | sed 's/^/  /'
      info ""
      if (( force == 0 )); then
        err "refuse to replace dir with new content. Options:"
        err "  - merge changes into ${repo_memory}, commit, re-run"
        err "  - re-run with --force to back up the existing dir + replace"
        exit 1
      fi
      local timestamp
      timestamp="$(date +%Y%m%d-%H%M%S)"
      local backup="${link_path}.backup-${timestamp}"
      if (( dry_run )); then
        info "dry-run: would mv ${link_path} ${backup}"
      else
        mv -- "${link_path}" "${backup}"
        info "backed up existing dir to: ${backup}"
      fi
    else
      if (( dry_run )); then
        info "dry-run: existing dir matches repo copy; would rm -rf and symlink"
      else
        rm -rf -- "${link_path}"
        info "existing dir matched repo copy; removed"
      fi
    fi
  elif [[ -L "${link_path}" ]]; then
    if (( dry_run )); then
      info "dry-run: would rm wrong-target symlink ${link_path}"
    else
      rm -- "${link_path}"
    fi
  fi

  # Ensure project_dir exists (parent of the symlink).
  if [[ ! -d "${project_dir}" ]]; then
    if (( dry_run )); then
      info "dry-run: would mkdir -p ${project_dir}"
    else
      mkdir -p -- "${project_dir}"
      info "created ${project_dir}"
    fi
  fi

  if (( dry_run )); then
    info "dry-run: would symlink ${link_path} -> ${repo_memory}"
    return 0
  fi

  ln -s -- "${repo_memory}" "${link_path}"
  info "OK: created symlink"
  info ""
  info "verify with:"
  info "  ls -la \"${link_path}\""
}

main "$@"
