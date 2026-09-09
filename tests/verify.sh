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
  "$tool_root/container-test"
  "$tool_root/kin-node"
  "$tool_root/tests/acceptance.sh"
  "$tool_root/tests/container-live.sh"
  "$tool_root/tests/convergence.sh"
)

for executable_source in "${executable_sources[@]}"; do
  bash -n "$executable_source"
done

grep -Fqx 'FROM docker.io/library/ubuntu:26.04' "$tool_root/Containerfile"
grep -Fqx 'WORKDIR /workspace/kin-node' "$tool_root/Containerfile"
grep -Fq 'ansible-core==2.20.9' "$tool_root/requirements-test.txt"
grep -Fq 'docker|podman' "$tool_root/container-test"
grep -Fq 'uses: actions/checkout@v6' "$tool_root/.github/workflows/test.yml"
grep -Fq 'run: ./container-test' "$tool_root/.github/workflows/test.yml"

if grep -ERn -i 'vagrant|virtualbox|bento' \
  "$tool_root/Containerfile" \
  "$tool_root/container-test" \
  "$tool_root/kin-node" \
  "$ansible_root"; then
  printf 'FAIL  VM implementation leaked into host configuration or container tests\n' >&2
  exit 1
fi

if grep -En '(\[\[[[:space:]]+-t|test[[:space:]]+-t|tty[[:space:]]+-s|TERM=)' \
  "${executable_sources[@]}"; then
  printf 'FAIL  execution must not depend on a terminal or TTY type\n' >&2
  exit 1
fi

dummy_commit=0000000000000000000000000000000000000000
dummy_node=11111111111111111111111111111111
for playbook in h0.yml h0-acceptance.yml h1.yml h1-acceptance.yml; do
  ANSIBLE_CONFIG="$ansible_root/ansible.cfg" "$ansible_playbook" \
    --inventory "$ansible_root/inventory.ini" \
    --extra-vars "{\"kin_source_commit\":\"$dummy_commit\",\"kin_node_id\":\"$dummy_node\",\"kin_target_distribution\":\"Ubuntu\"}" \
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
