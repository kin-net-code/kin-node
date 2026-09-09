# Kin Node

This repository is the small, deployment-facing Kin Node prototype. Its current
contract ends at configuration level H1: a fresh Ubuntu VM is constructed and
proven to be under exact, versioned Kin configuration control.

It deliberately does **not** install the tunnel, transport bus, GPU queue,
worker, harnesses, OpenBao, or an IP overlay yet. Those become later,
independently accepted configuration levels after this base path works on the
real host.

## Deploy a fresh H1 VM

The VM host needs Git, Vagrant, and VirtualBox. It also needs outbound Internet
access for the public repository, Vagrant box, Ubuntu packages, and pinned
Python packages.

```bash
git clone https://github.com/kin-net-code/kin-node.git && cd kin-node && ./run
```

That is the whole operator interface. No GitHub account, SSH key, forwarded
agent, guest password, copied script sequence, or terminal-type detection is
involved.

The default guest is named `kin-node` and uses 2 GiB RAM and two CPUs. These can
be changed before the first run:

```bash
KIN_NODE_VM_NAME=kin-node-test KIN_NODE_VM_MEMORY_MB=2048 KIN_NODE_VM_CPUS=2 ./run
```

## What `./run` does

1. Refuses dirty, detached, or unpushed source so the installed revision is
   unambiguous.
2. Validates and starts the pinned, headless, NAT-only Ubuntu VM.
3. Accepts the base execution environment.
4. Creates a temporary Git bundle for the exact host commit and uploads it
   through Vagrant. The guest receives no host credential.
5. Applies and accepts H0.
6. Applies and accepts H1.
7. Prints the installed JSON state and a final `PASS  VAGRANT_H1` line.

| Level | Adds | Acceptance boundary |
| --- | --- | --- |
| Base VM | Ubuntu 26.04, systemd, machine identity, Git, Python, pinned Ansible 2.20.9, passwordless Vagrant sudo | Execution prerequisites work; no Kin state exists |
| H0 | Base packages, `/etc/kin-net`, `/var/lib/kin-net`, exact source and machine identity | Clean supported platform; root ownership and modes; H1 remains absent |
| H1 | H1 state promotion and `/usr/local/bin/kin-node-status` | Matching accepted H0 is mandatory; status returns the accepted machine-readable record |

H0 and H1 are separate Ansible roles. H1 cannot construct or silently repair a
missing H0. Every apply is immediately followed by its read-only acceptance
playbook.

## Development checks

The fast suite exercises syntax, policy boundaries, isolated H0/H1 convergence,
idempotence, rejection cases, Git-bundle transfer, and mocked host orchestration:

```bash
python3 -m venv .venv
.venv/bin/pip install ansible-core==2.20.9
KIN_ANSIBLE_PLAYBOOK="$PWD/.venv/bin/ansible-playbook" ./test
```

`./run` is the real VM acceptance path. Re-running it at the same commit is
supported. This MVP intentionally refuses to retarget an existing guest to a
different commit; use a fresh VM name while we are learning the upgrade path.
