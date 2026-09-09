#!/usr/bin/env bash
set -Eeuo pipefail

tool_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ansible_root="$tool_root/ansible"
ansible_playbook=${KIN_ANSIBLE_PLAYBOOK:-$(command -v ansible-playbook || true)}
source_commit=1111111111111111111111111111111111111111
node_id=22222222222222222222222222222222
test_root=$(mktemp -d "${TMPDIR:-/tmp}/kin-node-container.XXXXXX")
extra_vars=$(printf '{"kin_source_commit":"%s","kin_node_id":"%s"}' \
  "$source_commit" "$node_id")

[[ -n "$ansible_playbook" ]] || {
  printf 'FAIL  ansible-playbook not found\n' >&2
  exit 1
}

run_playbook() {
  ANSIBLE_CONFIG="$ansible_root/ansible.cfg" "$ansible_playbook" \
    --inventory "$ansible_root/inventory.ini" \
    --extra-vars "$extra_vars" \
    "$@"
}

run_logged() {
  local log=$1
  shift
  if ! run_playbook "$@" > "$log" 2>&1; then
    cat "$log" >&2
    return 1
  fi
}

"$tool_root/test"

run_logged "$test_root/h0-first.log" "$ansible_root/playbooks/h0.yml"
run_logged "$test_root/h0-accept.log" "$ansible_root/playbooks/h0-acceptance.yml"
run_logged "$test_root/h0-second.log" "$ansible_root/playbooks/h0.yml"

h0_second_recap=$(grep -E '^localhost +:' "$test_root/h0-second.log")
[[ "$h0_second_recap" == *'changed=0'* && "$h0_second_recap" == *'failed=0'* ]] || {
  printf 'FAIL  container H0 was not idempotent: %s\n' "$h0_second_recap" >&2
  exit 1
}

run_logged "$test_root/h1-first.log" "$ansible_root/playbooks/h1.yml"
run_logged "$test_root/h1-accept.log" "$ansible_root/playbooks/h1-acceptance.yml"
run_logged "$test_root/h1-second.log" "$ansible_root/playbooks/h1.yml"

h1_second_recap=$(grep -E '^localhost +:' "$test_root/h1-second.log")
[[ "$h1_second_recap" == *'changed=0'* && "$h1_second_recap" == *'failed=0'* ]] || {
  printf 'FAIL  container H1 was not idempotent: %s\n' "$h1_second_recap" >&2
  exit 1
}

grep -Fq "PASS H0 node=$node_id" "$test_root/h0-accept.log"
grep -Fq "PASS H1 node=$node_id" "$test_root/h1-accept.log"
/usr/local/bin/kin-node-status | grep -Fq '"config_level": "H1"'

printf 'PASS  H0_H1_CONTAINER_ACCEPTANCE evidence=%s\n' "$test_root"
