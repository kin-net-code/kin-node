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

test_vars=$(printf '{"kin_source_commit":"1111111111111111111111111111111111111111","kin_target_distribution":"Ubuntu","kin_node_id":"22222222222222222222222222222222","kin_config_dir":"%s/etc/kin-net","kin_state_dir":"%s/var/lib/kin-net","kin_state_file":"%s/var/lib/kin-net/config-level.json","kin_status_command":"%s/usr/local/bin/kin-node-status","kin_receipts_dir":"%s/var/lib/kin-net/receipts","kin_h0_receipt_file":"%s/var/lib/kin-net/receipts/1111111111111111111111111111111111111111-H0.json","kin_h1_receipt_file":"%s/var/lib/kin-net/receipts/1111111111111111111111111111111111111111-H1.json","kin_m0_root":"%s/var/lib/kin-net/migration","kin_m0_archive":"%s/var/lib/kin-net/migration/legacy-rootfs.tar.gz","kin_m0_capture_manifest":"%s/var/lib/kin-net/migration/capture-manifest.json","kin_m0_capture_receipt":"%s/var/lib/kin-net/migration/capture-receipt.json","kin_m0_cutover_receipt":"%s/var/lib/kin-net/migration/cutover-receipt.json","kin_m0_paths_file":"%s/var/lib/kin-net/migration/captured-paths.txt","kin_legacy_paths":[],"kin_m0_review_paths":[],"kin_m0_manage_services":false,"kin_h0_manage_packages":false}' \
  "$test_root" "$test_root" "$test_root" "$test_root" "$test_root" "$test_root" \
  "$test_root" "$test_root" "$test_root" "$test_root" "$test_root" "$test_root" "$test_root")

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

next_commit=3333333333333333333333333333333333333333
next_receipts=$(printf '{"kin_source_commit":"%s","kin_h0_receipt_file":"%s/var/lib/kin-net/receipts/%s-H0.json","kin_h1_receipt_file":"%s/var/lib/kin-net/receipts/%s-H1.json"}' \
  "$next_commit" "$test_root" "$next_commit" "$test_root" "$next_commit")
run_playbook --extra-vars "$next_receipts" \
  "$ansible_root/playbooks/h0.yml" > "$test_root/source-upgrade-h0.log"
run_playbook --extra-vars "$next_receipts" \
  "$ansible_root/playbooks/h0-acceptance.yml" > "$test_root/source-upgrade-h0-accept.log"
grep -Fq '"config_level": "H0"' "$test_root/var/lib/kin-net/config-level.json"
grep -Fq "\"source_commit\": \"$next_commit\"" "$test_root/var/lib/kin-net/config-level.json"
[[ ! -e "$test_root/usr/local/bin/kin-node-status" ]]
[[ -f "$test_root/var/lib/kin-net/receipts/1111111111111111111111111111111111111111-H1.json" ]]

run_playbook --extra-vars "$next_receipts" \
  "$ansible_root/playbooks/h1.yml" > "$test_root/source-upgrade-h1.log"
run_playbook --extra-vars "$next_receipts" \
  "$ansible_root/playbooks/h1-acceptance.yml" > "$test_root/source-upgrade-h1-accept.log"
grep -Fq '"config_level": "H1"' "$test_root/var/lib/kin-net/config-level.json"

wrong_node=44444444444444444444444444444444
if run_playbook --extra-vars "{\"kin_node_id\":\"$wrong_node\",\"kin_source_commit\":\"$next_commit\",\"kin_h0_receipt_file\":\"$test_root/var/lib/kin-net/receipts/$next_commit-H0.json\"}" \
  "$ansible_root/playbooks/h0.yml" > "$test_root/wrong-node.log" 2>&1; then
  printf 'FAIL  H0 accepted state from another machine\n' >&2
  exit 1
fi
grep -Fq 'Existing Kin state belongs to another schema, level or machine' \
  "$test_root/wrong-node.log"

legacy_marker="$test_root/legacy-kin-state"
touch "$legacy_marker"
legacy_vars=$(printf '{"kin_legacy_paths":["%s"]}' "$legacy_marker")
if run_playbook --extra-vars "$legacy_vars" \
  "$ansible_root/playbooks/h0.yml" > "$test_root/legacy-state.log" 2>&1; then
  printf 'FAIL  H0 accepted legacy Kin state\n' >&2
  exit 1
fi
grep -Fq 'Legacy Kin state exists without a complete M0 archive and cutover receipt' \
  "$test_root/legacy-state.log"
unlink -- "$legacy_marker"

printf 'PASS  H0_H1_ISOLATED_CONVERGENCE evidence=%s\n' "$test_root"
