#!/usr/bin/env bash
set -Eeuo pipefail

tool_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

command -v vagrant >/dev/null 2>&1 || {
  printf 'FAIL  vagrant not found on the VM host\n' >&2
  exit 1
}

cd "$tool_root"

vagrant validate
vagrant ssh --command '
  set -eu
  test "$(ps -p 1 -o comm=)" = systemd
  grep -Eq "^[0-9a-f]{32}$" /etc/machine-id
  command -v git >/dev/null
  command -v ansible-playbook >/dev/null
  ansible-playbook --version | head -n 1 | grep -F "core 2.20.9"
  sudo -n true
  printf "PASS  BASE_VM_ACCEPTANCE\n"
'
