#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install --yes --no-install-recommends \
  ca-certificates \
  git \
  python3 \
  python3-venv

install -d -o root -g root -m 0755 /opt/kin-node-base
python3 -m venv /opt/kin-node-base/ansible

/opt/kin-node-base/ansible/bin/pip install \
  --disable-pip-version-check \
  --no-cache-dir \
  ansible-core==2.20.9 \
  cffi==2.1.1 \
  cryptography==50.0.1 \
  Jinja2==3.1.6 \
  MarkupSafe==3.0.3 \
  packaging==26.3 \
  pycparser==3.0 \
  PyYAML==6.0.3 \
  resolvelib==1.2.1

for command_name in ansible ansible-config ansible-inventory ansible-playbook; do
  ln -sfn "/opt/kin-node-base/ansible/bin/${command_name}" \
    "/usr/local/bin/${command_name}"
done

test "$(ps -p 1 -o comm=)" = systemd
grep -Eq '^[0-9a-f]{32}$' /etc/machine-id
su -s /bin/sh -c 'sudo -n true' vagrant
git --version
ansible-playbook --version | head -n 1 | grep -F 'core 2.20.9'

printf 'PASS  BASE_VM_READY\n'
