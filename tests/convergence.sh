#!/usr/bin/env bash
set -Eeuo pipefail

tool_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ansible_root="$tool_root/ansible"
ansible_playbook=${KIN_ANSIBLE_PLAYBOOK:-$(command -v ansible-playbook || true)}

[[ -n "$ansible_playbook" ]] || {
  printf 'FAIL  ansible-playbook not found\n' >&2
  exit 1
}

test_root=$(mktemp -d "${TMPDIR:-/tmp}/kin-node-convergence.XXXXXX")
mkdir -p "$test_root/usr/local/bin"

test_vars=$(printf '{"kin_source_commit":"1111111111111111111111111111111111111111","ansible_distribution":"Ubuntu","ansible_service_mgr":"systemd","ansible_virtualization_type":"virtualbox","ansible_machine_id":"22222222222222222222222222222222","kin_config_dir":"%s/etc/kin-net","kin_state_dir":"%s/var/lib/kin-net","kin_state_file":"%s/var/lib/kin-net/config-level.json","kin_status_command":"%s/usr/local/bin/kin-node-status","kin_legacy_paths":[],"kin_h0_manage_packages":false}' \
  "$test_root" "$test_root" "$test_root" "$test_root")

run_playbook() {
  ANSIBLE_CONFIG="$ansible_root/ansible.cfg" "$ansible_playbook" \
    --inventory "$ansible_root/inventory.ini" \
    --extra-vars "$test_vars" \
    "$@"
}

if run_playbook "$ansible_root/playbooks/h1.yml" > "$test_root/h1-before-h0.log" 2>&1; then
  printf 'FAIL  H1 succeeded without H0\n' >&2
  exit 1
fi
grep -Fq 'H1 requires an accepted H0 state' "$test_root/h1-before-h0.log"

run_playbook "$ansible_root/playbooks/h0.yml" > "$test_root/h0-first.log"
run_playbook "$ansible_root/playbooks/h0-acceptance.yml" > "$test_root/h0-accept.log"
run_playbook "$ansible_root/playbooks/h0.yml" > "$test_root/h0-second.log"

h0_second_recap=$(grep -E '^localhost +:' "$test_root/h0-second.log")
[[ "$h0_second_recap" == *'changed=0'* && "$h0_second_recap" == *'failed=0'* ]] || {
  printf 'FAIL  second H0 apply was not idempotent: %s\n' "$h0_second_recap" >&2
  exit 1
}
grep -Fq 'PASS H0 node=22222222222222222222222222222222' "$test_root/h0-accept.log"
grep -Fq '"config_level": "H0"' "$test_root/var/lib/kin-net/config-level.json"
[[ ! -e "$test_root/usr/local/bin/kin-node-status" ]]

run_playbook "$ansible_root/playbooks/h1.yml" > "$test_root/h1-first.log"
run_playbook "$ansible_root/playbooks/h1-acceptance.yml" > "$test_root/h1-accept.log"
run_playbook "$ansible_root/playbooks/h1.yml" > "$test_root/h1-second.log"

h1_second_recap=$(grep -E '^localhost +:' "$test_root/h1-second.log")
[[ "$h1_second_recap" == *'changed=0'* && "$h1_second_recap" == *'failed=0'* ]] || {
  printf 'FAIL  second H1 apply was not idempotent: %s\n' "$h1_second_recap" >&2
  exit 1
}
grep -Fq 'PASS H1 node=22222222222222222222222222222222' "$test_root/h1-accept.log"
"$test_root/usr/local/bin/kin-node-status" | grep -Fq '"config_level": "H1"'

run_playbook "$ansible_root/playbooks/h0.yml" > "$test_root/h0-after-h1.log"
run_playbook "$ansible_root/playbooks/h0-acceptance.yml" > "$test_root/h0-after-h1-accept.log"
h0_after_h1_recap=$(grep -E '^localhost +:' "$test_root/h0-after-h1.log")
[[ "$h0_after_h1_recap" == *'changed=0'* && "$h0_after_h1_recap" == *'failed=0'* ]] || {
  printf 'FAIL  H0 rerun disturbed H1: %s\n' "$h0_after_h1_recap" >&2
  exit 1
}
grep -Fq 'current=H1' "$test_root/h0-after-h1-accept.log"
"$test_root/usr/local/bin/kin-node-status" | grep -Fq '"config_level": "H1"'

if run_playbook \
  --extra-vars '{"kin_source_commit":"3333333333333333333333333333333333333333"}' \
  "$ansible_root/playbooks/h0.yml" > "$test_root/wrong-source.log" 2>&1; then
  printf 'FAIL  H0 accepted state from another source commit\n' >&2
  exit 1
fi
grep -Fq 'Existing Kin state belongs to another level, source commit or machine' \
  "$test_root/wrong-source.log"

legacy_marker="$test_root/legacy-kin-state"
touch "$legacy_marker"
legacy_vars=$(printf '{"kin_legacy_paths":["%s"]}' "$legacy_marker")
if run_playbook --extra-vars "$legacy_vars" \
  "$ansible_root/playbooks/h0.yml" > "$test_root/legacy-state.log" 2>&1; then
  printf 'FAIL  H0 accepted legacy Kin state\n' >&2
  exit 1
fi
grep -Fq "Legacy Kin state exists at $legacy_marker" "$test_root/legacy-state.log"
unlink -- "$legacy_marker"

printf 'PASS  H0_H1_ISOLATED_CONVERGENCE evidence=%s\n' "$test_root"
