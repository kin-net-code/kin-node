# Kin Node

Kin Node is a native host-configuration project. Its current contract ends at
configuration level H1: an existing Ubuntu host is proven to be under exact,
versioned Kin configuration control without reinstalling its base OS.

Vagrant, VirtualBox, and a VM image are not part of that contract. Workload VMs
will return later as an isolation boundary for inference-linked risk. They are
not the place where the node control plane lives.

The prototype deliberately does **not** install the tunnel, transport bus, GPU
queue, worker, harnesses, OpenBao, or an IP overlay yet. Those become later,
independently accepted configuration levels after H0 and H1 work on the real
host.

## Configuration levels

| Level | Adds | Acceptance boundary |
| --- | --- | --- |
| Development image | Disposable Ubuntu 26.04 environment with pinned Ansible | Roles converge in Docker or Podman; this is not a node |
| M0 | Optional in-place retirement of a native legacy Kin runtime | Exact Kin services stopped/disabled; root-only archive and SHA-256 receipt; no deletion |
| H0 | Base packages, `/etc/kin-net`, `/var/lib/kin-net`, exact source and stable node identity | Clean or accepted-M0 platform; root ownership and modes; H1 remains absent |
| H1 | H1 state promotion and `/usr/local/bin/kin-node-status` | Matching accepted H0 is mandatory; status returns the accepted machine-readable record |

H0 and H1 are separate Ansible roles. H1 cannot construct or silently repair a
missing H0. Every apply is immediately followed by its read-only acceptance
playbook.

H1 currently proves versioned configuration control; it is not yet a running
Kin Net service. The first real host service belongs in the next level, with its
own start-up and acceptance contract.

M0 is deliberately conservative. It never reinstalls the OS, deletes legacy
files, changes firewall or network policy, stops OpenBao, or manipulates an old
VM. It reports ambiguous resources for review. A legacy VM and its user service
must be halted separately before native cutover.

## Develop and test in a container

The only local prerequisite is Docker or Podman:

```bash
./container-test
```

The wrapper prefers Docker when both are installed. Select explicitly when
needed:

```bash
KIN_CONTAINER_ENGINE=podman ./container-test
```

It builds from `docker.io/library/ubuntu:26.04`, installs the fully pinned test
toolchain, runs the fast tests, then applies and accepts H0 and H1 inside a fresh
container. It uses no TTY, privileged container, systemd imitation, host mount,
or container-engine socket.

The same command runs in GitHub Actions. `Containerfile` is intentionally
compatible with both Docker and Podman. The OCI image is disposable test
equipment, not the production package and not a security boundary for
inference.

## Apply to a host

`kin-node` is the host-facing controller. It operates on the local machine and
supports one configuration boundary at a time:

```bash
./bootstrap-controller
sudo -v
./kin-node inspect-m0
./kin-node check-h0
./kin-node apply-h0
./kin-node apply-h1
./kin-node status
```

`bootstrap-controller` creates the ignored repository-local `.venv` and installs
the pinned `ansible-core==2.20.9` toolchain. The host path requires Ubuntu, Git,
Python 3.12 or newer with `venv`, and current sudo authorization (`sudo -v` before the
controller). That prerequisite remains explicit bootstrap debt.

The controller refuses dirty source and records the exact Git commit and stable
node ID in `/var/lib/kin-net/config-level.json`. Per-source H0/H1 receipts remain
under `/var/lib/kin-net/receipts`. Applying a newer source to an installed H1
returns the honest current boundary to H0; applying H1 then restores it.
This `node_id` is the stable machine/deployment identifier, not the future
cryptographic `kin:id` principal.

If inspection finds native legacy state, do not apply H0 directly. Review the
inventory first, then use the explicit cutover gate:

```bash
./kin-node cutover-m0 --approve-stop-legacy
./kin-node apply-h0
./kin-node apply-h1
```

The archive at `/var/lib/kin-net/migration/legacy-rootfs.tar.gz` can contain keys,
databases and payloads. It is mode `0600`; never paste or upload it. See
[the Homenet in-place runbook](docs/operations/HOMENET-IN-PLACE.md) before using
the cutover action.

## Fast checks without a container

If pinned Ansible is already installed:

```bash
python3 -m venv .venv
.venv/bin/pip install --requirement requirements-test.txt
KIN_ANSIBLE_PLAYBOOK="$PWD/.venv/bin/ansible-playbook" ./test
```

The fast suite checks syntax, policy boundaries, ordering, rejection cases,
isolated convergence, and idempotence. The container run additionally exercises
the roles against a real, disposable Ubuntu 26.04 filesystem.

## VM image decision

There is no VM image decision on the critical path now. When an inference
workload needs a VM, it gets a separate thin launcher and acceptance test. If we
build a custom Vagrant base at that point, the result is a portable `.box` file:
it can be copied directly and installed with `vagrant box add`; it does not need
a Vagrant registry or a binary committed to this repository.
