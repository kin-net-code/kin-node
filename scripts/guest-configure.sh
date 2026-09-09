#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  exit 1
}

source_branch=${1:-}
source_commit=${2:-}
source_bundle=${KIN_GUEST_SOURCE_BUNDLE:-/tmp/kin-node-source.bundle}
target_checkout=${KIN_GUEST_TARGET_CHECKOUT:-"${HOME:?HOME is required}/kin-node"}
ansible_playbook=${KIN_GUEST_ANSIBLE_PLAYBOOK:-/opt/kin-node-base/ansible/bin/ansible-playbook}

[[ "$source_branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$ ]] || \
  fail "invalid source branch"
[[ "$source_branch" != *..* && "$source_branch" != */ && "$source_branch" != *//* ]] || \
  fail "invalid source branch"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || fail "invalid source commit"
[[ -f "$source_bundle" ]] || fail "source bundle was not uploaded"

if [[ ! -e "$target_checkout" ]]; then
  git clone --branch "$source_branch" "$source_bundle" "$target_checkout"
fi

checkout_commit=$(git -C "$target_checkout" rev-parse --verify HEAD 2>/dev/null) || \
  fail "target checkout is not a Git repository"
[[ "$checkout_commit" == "$source_commit" ]] || \
  fail "target checkout is not at the requested source commit"
[[ -z "$(git -C "$target_checkout" status --porcelain --untracked-files=normal)" ]] || \
  fail "target checkout is not clean"

unlink -- "$source_bundle"

controller="$target_checkout/kin-node"
[[ -x "$controller" ]] || fail "node controller is not executable"

KIN_ANSIBLE_PLAYBOOK="$ansible_playbook" \
  "$controller" apply-h0
KIN_ANSIBLE_PLAYBOOK="$ansible_playbook" \
  "$controller" apply-h1
"$controller" status

printf 'PASS  GUEST_H1 source=%s\n' "$source_commit"
