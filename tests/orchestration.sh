#!/usr/bin/env bash
set -Eeuo pipefail

tool_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/kin-node-orchestration.XXXXXX")
test_repo="$test_root/kin-node"
test_log="$test_root/vagrant.log"

mkdir -p "$test_repo"
git -C "$tool_root" archive HEAD | tar -x -C "$test_repo"

git -C "$test_repo" init --quiet --initial-branch=agent/codex/prototype
git -C "$test_repo" config user.name 'Kin Node Test'
git -C "$test_repo" config user.email 'kin-node-test.invalid'
git -C "$test_repo" add .
git -C "$test_repo" commit --quiet --message 'test fixture'
git -C "$test_repo" update-ref refs/remotes/origin/agent/codex/prototype HEAD

PATH="$tool_root/tests/fixtures/bin:$PATH" \
KIN_TEST_VAGRANT_LOG="$test_log" \
  "$test_repo/run" > "$test_root/deploy.log"

grep -Fxq 'validate' "$test_log"
grep -Fxq 'up --provider=virtualbox' "$test_log"
grep -Fq 'upload ' "$test_log"
grep -Fq '/tmp/kin-node-source.bundle' "$test_log"
grep -Fq '/tmp/kin-node-guest-configure.sh' "$test_log"
grep -Fq "ssh --command bash /tmp/kin-node-guest-configure.sh 'agent/codex/prototype' '" "$test_log"
grep -Fq 'PASS  VAGRANT_H1 vm=kin-node source=' "$test_root/deploy.log"

touch "$test_repo/untracked-state"
if PATH="$tool_root/tests/fixtures/bin:$PATH" \
  KIN_TEST_VAGRANT_LOG="$test_log" \
    "$test_repo/run" \
    > "$test_root/dirty-checkout.log" 2>&1; then
  printf 'FAIL  host deployer accepted an untracked file\n' >&2
  exit 1
fi
grep -Fq 'checkout has untracked files' "$test_root/dirty-checkout.log"

printf 'PASS  HOST_ORCHESTRATION evidence=%s\n' "$test_root"
