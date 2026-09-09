#!/usr/bin/env bash
set -Eeuo pipefail

tool_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/kin-node-guest-transfer.XXXXXX")
source_repo="$test_root/source"
source_bundle="$test_root/source.bundle"
target_checkout="$test_root/target"
guest_log="$test_root/guest.log"

mkdir -p "$source_repo"
cp "$tool_root/tests/fixtures/guest-controller" "$source_repo/kin-node"

git -C "$source_repo" init --quiet --initial-branch=agent/codex/prototype
git -C "$source_repo" config user.name 'Kin Node Test'
git -C "$source_repo" config user.email 'kin-node-test.invalid'
git -C "$source_repo" add kin-node
git -C "$source_repo" commit --quiet --message 'guest fixture'
source_commit=$(git -C "$source_repo" rev-parse HEAD)
git -C "$source_repo" bundle create "$source_bundle" refs/heads/agent/codex/prototype

KIN_GUEST_SOURCE_BUNDLE="$source_bundle" \
KIN_GUEST_TARGET_CHECKOUT="$target_checkout" \
KIN_GUEST_ANSIBLE_PLAYBOOK=/bin/true \
KIN_TEST_GUEST_LOG="$guest_log" \
  "$tool_root/scripts/guest-configure.sh" agent/codex/prototype "$source_commit" \
  > "$test_root/first.log"

[[ ! -e "$source_bundle" ]]
[[ "$(git -C "$target_checkout" rev-parse HEAD)" == "$source_commit" ]]
[[ "$(printf 'apply-h0\napply-h1\nstatus\n')" == "$(cat "$guest_log")" ]]
grep -Fq 'PASS  GUEST_H1 source=' "$test_root/first.log"

git -C "$source_repo" bundle create "$source_bundle" refs/heads/agent/codex/prototype
: > "$guest_log"
KIN_GUEST_SOURCE_BUNDLE="$source_bundle" \
KIN_GUEST_TARGET_CHECKOUT="$target_checkout" \
KIN_GUEST_ANSIBLE_PLAYBOOK=/bin/true \
KIN_TEST_GUEST_LOG="$guest_log" \
  "$tool_root/scripts/guest-configure.sh" agent/codex/prototype "$source_commit" \
  > "$test_root/resume.log"

[[ ! -e "$source_bundle" ]]
[[ "$(printf 'apply-h0\napply-h1\nstatus\n')" == "$(cat "$guest_log")" ]]
grep -Fq 'PASS  GUEST_H1 source=' "$test_root/resume.log"

git -C "$source_repo" bundle create "$source_bundle" refs/heads/agent/codex/prototype
if KIN_GUEST_SOURCE_BUNDLE="$source_bundle" \
  KIN_GUEST_TARGET_CHECKOUT="$target_checkout" \
  KIN_GUEST_ANSIBLE_PLAYBOOK=/bin/true \
  KIN_TEST_GUEST_LOG="$guest_log" \
    "$tool_root/scripts/guest-configure.sh" agent/codex/prototype \
    3333333333333333333333333333333333333333 \
    > "$test_root/wrong-commit.log" 2>&1; then
  printf 'FAIL  guest accepted a checkout at the wrong commit\n' >&2
  exit 1
fi
grep -Fq 'target checkout is not at the requested source commit' \
  "$test_root/wrong-commit.log"
unlink -- "$source_bundle"

printf 'PASS  GUEST_SOURCE_TRANSFER evidence=%s\n' "$test_root"
