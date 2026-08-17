#!/usr/bin/env bash
# Fetch listed GitHub skills into ~/.cursor/skills.
# Clones into /tmp. Writes nothing under $HOME until every SKILL.md is found.
# Run as your user, not root.
set -euo pipefail

# GitHub repos cloned once each.
readonly git_sources=(
  'https://github.com/dmmulroy/skills'
  'https://github.com/mattpocock/skills'
  'https://github.com/emilkowalski/skills'
  'https://github.com/SentioLabs/pi-nexus'
  'https://github.com/humanlayer/skills'
)

# Paths relative to a cloned repo. Each must contain SKILL.md.
readonly skills=(
  'tech-spec'
  'bro'
  'plugins/show-me/skills/show-me'
  'skills/productivity/grill-me'
  'skills/productivity/grilling'
  'skills/engineering/grill-with-docs'
  'skills/engineering/implement'
  'skills/engineering/resolving-merge-conflicts'
  'skills/engineering/domain-modeling'
  'skills/engineering/tdd'
  'skills/engineering/prototype'
  'skills/engineering/diagnosing-bugs'
  'skills/engineering/code-review'
  'skills/engineering/codebase-design'
  'skills/engineering/improve-codebase-architecture'
  'skills/productivity/writing-for-agents'
  'skills/productivity/teach'
  'skills/productivity/handoff'
  'skills/emil-design-eng'
  'skills/review-animations'
  'skills/animation-vocabulary'
  'packages/pi-frontend-design/skills/frontend-design'
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

clone_url() {
  local url="${1:?}"
  url="${url%/}"
  [[ "${url}" == *.git ]] || url="${url}.git"
  printf '%s\n' "${url}"
}

assert_safe_path() {
  local path="${1:?}"
  local part
  [[ -n "${path}" && "${path}" == "${path#/}" ]] || die "unsafe skill path: ${path}"
  IFS=/ read -r -a parts <<< "${path}"
  for part in "${parts[@]}"; do
    [[ -n "${part}" && "${part}" != . && "${part}" != .. ]] || \
      die "unsafe skill path: ${path}"
  done
}

find_skill_dir() {
  local rel="${1:?}" clone src
  local -a matches=()
  for clone in "${clone_dirs[@]}"; do
    src="${clone}/${rel}"
    [[ -f "${src}/SKILL.md" ]] || continue
    matches+=("${src}")
  done
  ((${#matches[@]} != 0)) || die "missing ${rel}/SKILL.md in cloned sources"
  ((${#matches[@]} == 1)) || die "found ${#matches[@]} copies of ${rel}; refusing to guess"
  printf '%s\n' "${matches[0]}"
}

((EUID != 0)) || die 'run this as your user, not root'
[[ -n "${HOME:-}" && "${HOME}" != / ]] || die 'HOME is unset or unusable'
((${#git_sources[@]} > 0)) || die 'git_sources is empty'
((${#skills[@]} > 0)) || die 'skills is empty'

for command_name in git mkdir cp rm mktemp; do
  command -v "${command_name}" >/dev/null 2>&1 || die "missing command: ${command_name}"
done

for path in "${skills[@]}"; do
  assert_safe_path "${path}"
done

workdir="$(mktemp -d "${TMPDIR:-/tmp}/cursor-cli-skills.XXXXXX")"
trap 'rm -rf -- "${workdir}"' EXIT

clone_dirs=()
i=0
for source in "${git_sources[@]}"; do
  dest="${workdir}/src-${i}"
  GIT_TERMINAL_PROMPT=0 git clone --depth=1 --single-branch --quiet \
    "$(clone_url "${source}")" "${dest}" || die "git clone failed: ${source}"
  clone_dirs+=("${dest}")
  i=$((i + 1))
done

declare -A claimed_names=()
resolved_srcs=()
resolved_names=()
for path in "${skills[@]}"; do
  src="$(find_skill_dir "${path}")"
  name="$(basename -- "${path}")"
  [[ -z "${claimed_names[${name}]:-}" ]] || die "duplicate skill name ${name} (from ${path})"
  claimed_names["${name}"]=1
  resolved_srcs+=("${src}")
  resolved_names+=("${name}")
done

mkdir -p -- "${HOME}/.cursor/skills"
for i in "${!resolved_srcs[@]}"; do
  dest="${HOME}/.cursor/skills/${resolved_names[i]}"
  rm -rf -- "${dest}"
  cp -a -- "${resolved_srcs[i]}" "${dest}"
  printf 'Installed %s -> %s\n' "${resolved_names[i]}" "${dest}"
done

printf 'Restart Cursor / cursor-agent to pick up the skills.\n'
