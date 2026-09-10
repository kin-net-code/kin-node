#!/usr/bin/env bash
set -Eeuo pipefail

tool_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ansible_root="$tool_root/ansible"
ansible_playbook=${KIN_ANSIBLE_PLAYBOOK:-"$tool_root/.venv/bin/ansible-playbook"}
test_root=$(mktemp -d /tmp/kin-m0-systemd.XXXXXX)
legacy_root="$test_root/legacy-native"
state_root="$test_root/var/lib/kin-net"
unit_name=kin-m0-ci-fixture.service
unit_file="/etc/systemd/system/$unit_name"
source_commit=$(git -C "$tool_root" rev-parse --verify HEAD)
node_id=22222222222222222222222222222222
fixture_installed=false

cleanup() {
  if [[ "$fixture_installed" == true ]]; then
    sudo systemctl disable --now "$unit_name" >/dev/null 2>&1 || true
    sudo rm -f -- "$unit_file"
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
  fi
  if [[ "$test_root" == /tmp/kin-m0-systemd.* ]]; then
    sudo rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

[[ -x "$ansible_playbook" ]] || {
  printf 'FAIL  pinned ansible-playbook not found: %s\n' "$ansible_playbook" >&2
  exit 1
}
[[ $(ps -p 1 -o comm=) == systemd ]] || {
  printf 'FAIL  systemd must be PID 1 for this test\n' >&2
  exit 1
}
[[ ! -e "$unit_file" ]] || {
  printf 'FAIL  refusing to overwrite existing unit: %s\n' "$unit_file" >&2
  exit 1
}
if systemctl cat "$unit_name" >/dev/null 2>&1; then
  printf 'FAIL  refusing to shadow existing unit: %s\n' "$unit_name" >&2
  exit 1
fi

mkdir -p "$legacy_root"
printf '%s\n' 'stopped-state-fixture' > "$legacy_root/state.txt"
sudo install -o root -g root -m 0644 \
  "$tool_root/tests/fixtures/kin-m0-ci-fixture.service" "$unit_file"
fixture_installed=true
sudo systemctl daemon-reload
sudo systemctl enable --now "$unit_name"
[[ $(systemctl is-active "$unit_name") == active ]]
[[ $(systemctl is-enabled "$unit_name") == enabled ]]

test_vars=$(printf '{"kin_source_commit":"%s","kin_target_distribution":"Ubuntu","kin_node_id":"%s","kin_state_dir":"%s","kin_state_file":"%s/config-level.json","kin_m0_root":"%s/migration","kin_m0_archive":"%s/migration/legacy-rootfs.tar.gz","kin_m0_capture_manifest":"%s/migration/capture-manifest.json","kin_m0_capture_receipt":"%s/migration/capture-receipt.json","kin_m0_cutover_receipt":"%s/migration/cutover-receipt.json","kin_m0_paths_file":"%s/migration/captured-paths.txt","kin_m0_storage_probe":"%s","kin_legacy_paths":["%s","%s"],"kin_m0_review_paths":[],"kin_m0_services":["%s"],"kin_m0_manage_services":true,"kin_m0_cutover_approved":true,"kin_m0_minimum_free_bytes":0}' \
  "$source_commit" "$node_id" "$state_root" "$state_root" "$state_root" \
  "$state_root" "$state_root" "$state_root" "$state_root" "$state_root" \
  "$test_root" "$legacy_root" "$unit_file" "$unit_name")

run_playbook() {
  sudo -n env ANSIBLE_CONFIG="$ansible_root/ansible.cfg" "$ansible_playbook" \
    --inventory "$ansible_root/inventory.ini" \
    --extra-vars "$test_vars" \
    "$@"
}

run_playbook "$ansible_root/playbooks/m0-inspect.yml" > "$test_root/inspect.log"
run_playbook "$ansible_root/playbooks/m0-cutover.yml" > "$test_root/cutover.log"
run_playbook "$ansible_root/playbooks/m0-acceptance.yml" > "$test_root/accept.log"

[[ $(systemctl is-active "$unit_name" || true) == inactive ]]
[[ $(systemctl is-enabled "$unit_name" || true) == disabled ]]
grep -Fq 'PASS M0 node=' "$test_root/accept.log"

printf 'PASS  M0_SYSTEMD_MIGRATION\n'
