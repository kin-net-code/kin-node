#!/usr/bin/env bash
set -Eeuo pipefail

tool_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ansible_root="$tool_root/ansible"
ansible_playbook=${KIN_ANSIBLE_PLAYBOOK:-$(command -v ansible-playbook || true)}

[[ -n "$ansible_playbook" ]] || {
  printf 'FAIL  ansible-playbook not found\n' >&2
  exit 1
}

test_root=$(mktemp -d "${TMPDIR:-/tmp}/kin-node-migration.XXXXXX")
legacy_root="$test_root/legacy-native"
state_root="$test_root/var/lib/kin-net"
config_root="$test_root/etc/kin-net"
status_command="$test_root/usr/local/bin/kin-node-status"
source_commit=1111111111111111111111111111111111111111
node_id=22222222222222222222222222222222

mkdir -p "$legacy_root/state" "$(dirname -- "$status_command")"
printf '%s\n' 'test-private-key-material' > "$legacy_root/state/private.key"
chmod 600 "$legacy_root/state/private.key"
ln -s state/private.key "$legacy_root/current-key"

test_vars=$(printf '{"kin_source_commit":"%s","kin_target_distribution":"Ubuntu","kin_node_id":"%s","kin_config_dir":"%s","kin_state_dir":"%s","kin_state_file":"%s/config-level.json","kin_status_command":"%s","kin_receipts_dir":"%s/receipts","kin_h0_receipt_file":"%s/receipts/%s-H0.json","kin_h1_receipt_file":"%s/receipts/%s-H1.json","kin_m0_root":"%s/migration","kin_m0_archive":"%s/migration/legacy-rootfs.tar.gz","kin_m0_capture_manifest":"%s/migration/capture-manifest.json","kin_m0_capture_receipt":"%s/migration/capture-receipt.json","kin_m0_cutover_receipt":"%s/migration/cutover-receipt.json","kin_m0_paths_file":"%s/migration/captured-paths.txt","kin_legacy_paths":["%s"],"kin_m0_review_paths":[],"kin_m0_services":[],"kin_m0_manage_services":false,"kin_m0_cutover_approved":true,"kin_m0_minimum_free_bytes":0,"kin_h0_manage_packages":false}' \
  "$source_commit" "$node_id" "$config_root" "$state_root" "$state_root" \
  "$status_command" "$state_root" "$state_root" "$source_commit" "$state_root" \
  "$source_commit" "$state_root" "$state_root" "$state_root" "$state_root" \
  "$state_root" "$state_root" "$legacy_root")

run_playbook() {
  ANSIBLE_CONFIG="$ansible_root/ansible.cfg" "$ansible_playbook" \
    --inventory "$ansible_root/inventory.ini" \
    --extra-vars "$test_vars" \
    "$@"
}

run_playbook "$ansible_root/playbooks/m0-inspect.yml" > "$test_root/inspect.log"
grep -Fq 'LEGACY: stop here for review' "$test_root/inspect.log"

if run_playbook --extra-vars '{"kin_m0_cutover_approved":false}' \
  "$ansible_root/playbooks/m0-cutover.yml" > "$test_root/unapproved.log" 2>&1; then
  printf 'FAIL  M0 cutover ran without explicit approval\n' >&2
  exit 1
fi
grep -Fq 'M0 cutover requires the controller' "$test_root/unapproved.log"

if run_playbook --extra-vars '{"kin_m0_additional_paths":["/"]}' \
  "$ansible_root/playbooks/m0-inspect.yml" > "$test_root/broad-path.log" 2>&1; then
  printf 'FAIL  M0 accepted a broad additional capture path\n' >&2
  exit 1
fi
grep -Fq 'M0 refuses unsafe legacy path' "$test_root/broad-path.log"

if run_playbook "$ansible_root/playbooks/h0.yml" > "$test_root/h0-before-m0.log" 2>&1; then
  printf 'FAIL  H0 crossed legacy state without M0\n' >&2
  exit 1
fi
grep -Fq 'Legacy Kin state exists without a complete M0 archive and cutover receipt' \
  "$test_root/h0-before-m0.log"

run_playbook "$ansible_root/playbooks/m0-cutover.yml" > "$test_root/m0-first.log"
run_playbook "$ansible_root/playbooks/m0-acceptance.yml" > "$test_root/m0-accept.log"
grep -Fq 'PASS M0 node=' "$test_root/m0-accept.log"

archive="$state_root/migration/legacy-rootfs.tar.gz"
receipt="$state_root/migration/capture-receipt.json"
[[ $(stat -c '%a' "$state_root/migration") == 700 ]]
[[ $(stat -c '%a' "$archive") == 600 ]]
tar -tzf "$archive" | grep -Fq "${legacy_root#/}/state/private.key"

python3 - "$archive" "$receipt" <<'PY'
import hashlib
import json
import pathlib
import sys

archive = pathlib.Path(sys.argv[1])
receipt = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert hashlib.sha256(archive.read_bytes()).hexdigest() == receipt["archive_sha256"]
PY

m0_second=$(run_playbook "$ansible_root/playbooks/m0-cutover.yml" 2>&1)
m0_second_recap=$(grep -E '^localhost +:' <<<"$m0_second")
[[ "$m0_second_recap" == *'changed=0'* && "$m0_second_recap" == *'failed=0'* ]] || {
  printf 'FAIL  second M0 cutover was not idempotent: %s\n' "$m0_second_recap" >&2
  exit 1
}

run_playbook "$ansible_root/playbooks/h0.yml" > "$test_root/h0-after-m0.log"
run_playbook "$ansible_root/playbooks/h0-acceptance.yml" > "$test_root/h0-after-m0-accept.log"

uncaptured_path="$test_root/uncaptured-legacy"
printf '%s\n' 'late legacy state' > "$uncaptured_path"
uncaptured_vars=$(printf '{"kin_legacy_paths":["%s","%s"]}' "$legacy_root" "$uncaptured_path")
if run_playbook --extra-vars "$uncaptured_vars" \
  "$ansible_root/playbooks/h0-acceptance.yml" > "$test_root/uncaptured.log" 2>&1; then
  printf 'FAIL  H0 accepted a legacy path absent from the M0 receipt\n' >&2
  exit 1
fi
grep -Fq 'M0 receipts do not describe this machine, archive and cutover boundary' \
  "$test_root/uncaptured.log"
unlink -- "$uncaptured_path"

cp -- "$archive" "$archive.known-good"
printf x >> "$archive"
if run_playbook "$ansible_root/playbooks/m0-acceptance.yml" > "$test_root/tampered.log" 2>&1; then
  printf 'FAIL  M0 accepted a modified legacy archive\n' >&2
  exit 1
fi
grep -Fq 'M0 evidence hash does not match its capture receipt' "$test_root/tampered.log"
mv -- "$archive.known-good" "$archive"
run_playbook "$ansible_root/playbooks/m0-acceptance.yml" > "$test_root/restored.log"

printf 'PASS  M0_ISOLATED_MIGRATION evidence=%s\n' "$test_root"
