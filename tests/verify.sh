#!/usr/bin/env bash
set -Eeuo pipefail

tool_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ansible_root="$tool_root/ansible"
ansible_playbook=${KIN_ANSIBLE_PLAYBOOK:-$(command -v ansible-playbook || true)}

[[ -n "$ansible_playbook" ]] || {
  printf 'FAIL  ansible-playbook not found\n' >&2
  exit 1
}

executable_sources=(
  "$tool_root/test"
  "$tool_root/kin-node"
  "$tool_root/run"
  "$tool_root/scripts/base-bootstrap.sh"
  "$tool_root/scripts/guest-configure.sh"
  "$tool_root/tests/acceptance.sh"
  "$tool_root/tests/base-vm-acceptance.sh"
  "$tool_root/tests/convergence.sh"
  "$tool_root/tests/guest-source-transfer.sh"
  "$tool_root/tests/orchestration.sh"
  "$tool_root/tests/fixtures/bin/vagrant"
  "$tool_root/tests/fixtures/bin/python3"
  "$tool_root/tests/fixtures/guest-controller"
)

for executable_source in "${executable_sources[@]}"; do
  bash -n "$executable_source"
done

if command -v ruby >/dev/null 2>&1; then
  ruby -c "$tool_root/Vagrantfile"
else
  printf 'SKIP  VAGRANT_RUBY_SYNTAX (ruby unavailable)\n'
fi

grep -Fq 'config.vm.synced_folder ".", "/vagrant", disabled: true' \
  "$tool_root/Vagrantfile" || {
  printf 'FAIL  Vagrant must not mount the host checkout into the node\n' >&2
  exit 1
}
grep -Fq 'config.ssh.forward_agent = false' "$tool_root/Vagrantfile" || {
  printf 'FAIL  Vagrant must not expose the host SSH agent to the guest\n' >&2
  exit 1
}

grep -Fq 'TRUSTED_BASE_BOX = "kin/sanitized-ubuntu-26.04"' \
  "$tool_root/Vagrantfile"
grep -Fq 'TRUSTED_BASE_BOX_VERSION = "20260823.0"' \
  "$tool_root/Vagrantfile"
grep -Fq 'Canonical base provenance rejected; no fallback is configured' \
  "$tool_root/run"

if grep -ERn 'b[e]nto/' "$tool_root" --exclude-dir=.git; then
  printf 'FAIL  Bento remains in the Kin Node execution path\n' >&2
  exit 1
fi

if grep -Eq 'forwarded_port|public_network|private_network' "$tool_root/Vagrantfile"; then
  printf 'FAIL  base VM exposes networking beyond Vagrant SSH and NAT egress\n' >&2
  exit 1
fi

if grep -En '(\[\[[[:space:]]+-t|test[[:space:]]+-t|tty[[:space:]]+-s|TERM=)' \
  "${executable_sources[@]}"; then
  printf 'FAIL  execution must not depend on a terminal or TTY type\n' >&2
  exit 1
fi

if grep -En '(SSH_AUTH_SOCK|ssh-add|github\.com)' \
  "$tool_root/scripts/guest-configure.sh" "$tool_root/Vagrantfile"; then
  printf 'FAIL  the guest path must not receive or use GitHub credentials\n' >&2
  exit 1
fi

grep -Fq 'git -C "$repo_root" bundle create' "$tool_root/run"
grep -Fq 'vagrant upload "$source_bundle"' "$tool_root/run"

python3 -B "$tool_root/tests/test_base_image.py"

dummy_commit=0000000000000000000000000000000000000000
for playbook in h0.yml h0-acceptance.yml h1.yml h1-acceptance.yml; do
  ANSIBLE_CONFIG="$ansible_root/ansible.cfg" "$ansible_playbook" \
    --inventory "$ansible_root/inventory.ini" \
    --extra-vars "{\"kin_source_commit\":\"$dummy_commit\"}" \
    --syntax-check "$ansible_root/playbooks/$playbook"
done

if grep -ERn \
  'ansible\.builtin\.(apt|dnf|package|get_url|git|pip|reboot|service|shell|systemd_service|uri):' \
  "$ansible_root/roles/kin_h1/tasks"; then
  printf 'FAIL  H1 role contains an effect intentionally deferred beyond H1\n' >&2
  exit 1
fi

if grep -ERn \
  'ansible\.builtin\.(dnf|get_url|git|pip|reboot|service|shell|systemd_service|uri):' \
  "$ansible_root/roles/kin_h0/tasks"; then
  printf 'FAIL  H0 role contains an effect outside its base-system contract\n' >&2
  exit 1
fi

grep -Fq 'H1 requires an accepted H0 state' \
  "$ansible_root/roles/kin_h1/tasks/main.yml"

printf 'PASS  H0_H1_STATIC_ACCEPTANCE\n'
