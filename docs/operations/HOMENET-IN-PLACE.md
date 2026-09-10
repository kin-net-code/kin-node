# Homenet in-place preparation and H1 convergence

## Outcome and hard boundary

This runbook retains the installed Ubuntu OS and unrelated host state. It can:

1. inventory known legacy Kin paths and services without changing them;
2. stop and disable only `kin-node`, `kin-bus`, `kin-worker`, and `kin-tunnel`;
3. archive the exact discovered legacy paths with ownership, ACLs and xattrs;
4. bind the archive SHA-256 and path list to the machine ID in root-only receipts;
5. converge and accept H0 and H1 from one exact Git commit.

It does not install a replacement Kin message service. H1 is configuration control,
not Postcards, MCP, identity tooling, inference, or network routing. Those require
later accepted levels. Retiring a still-useful old runtime at M0 therefore creates
downtime; do it only when that is intended.

M0 performs no deletion. Original legacy files stay where they are. It does not
change firewall, DNS, routes, VPNs, OpenBao, VirtualBox, or an old Vagrant guest.
The archive may contain private keys and message content and must never be pasted,
uploaded, or placed in source control.

The current Git commit and local receipts are exact-integrity/provenance records,
not Kin identity proofs. Release signing is not implemented yet; a commit hash alone
does not authenticate a publisher.

## Before the first command

- Use a local console or a second tested SSH session. M0 avoids network changes,
  but an in-place host migration should not rely on one fragile shell.
- Do not clone this repository into `~/kin-node`; that is the default durable root
  of the v0.4.6 VM-based node. Use `~/kin-node-deploy`.
- Have enough free space for the uncompressed legacy paths plus 256 MiB. M0 checks
  this before creating the archive.
- The controller toolchain currently requires Python 3.12 or newer. If the host has
  an older Python, stop at preflight; do not add an unreviewed package repository.
- Never paste a sudo password, private key, tunnel key, archive, database, or
  `/etc/kin-tunnel/runtime.env` into chat.

## Gate 1: acquire and inspect

Use the exact reviewed commit supplied with the deployment handoff, not a later
moving `main`:

```bash
KIN_DEPLOY_COMMIT=REPLACE_WITH_REVIEWED_COMMIT
KIN_DEPLOY_DIR="$HOME/kin-node-deploy"
git clone https://github.com/kin-net-code/kin-node.git "$KIN_DEPLOY_DIR"
cd "$KIN_DEPLOY_DIR"
git checkout --detach "$KIN_DEPLOY_COMMIT"
test "$(git rev-parse HEAD)" = "$KIN_DEPLOY_COMMIT"
./bootstrap-controller
sudo -v
./kin-node inspect-m0
```

Stop after `inspect-m0` and review or paste its output. It reports paths and service
states, not their contents. The safe branches are:

| Inspection result | Next action |
| --- | --- |
| `CLEAN`, no legacy host notices | Check and apply H0 |
| `CLEAN` plus old VM or supervisor notice | Halt/disable the old VM path, inspect again, then check H0 |
| `LEGACY` | Review every path and manual-review notice before M0 cutover |
| Partial M0 artifacts, unexpected service, or unknown state | Stop; do not repair or delete by hand |

## Old v0.4.6 VM boundary

If `~/kin-node/kin-host` exists, it is separate from native M0. Inspect it without
destroying anything:

```bash
"$HOME/kin-node/kin-host" status
systemctl --user is-active kin-node-host.service || true
systemctl --user is-enabled kin-node-host.service || true
VBoxManage list runningvms 2>/dev/null || true
```

If the old node belonged to another local operator account, set
`KIN_LEGACY_HOST_ROOT` to that exact old root for `inspect-m0` and review that
account's user service separately.

If `kin-node-ng0` is running, halt it through the old controller. Disable its
desired-state supervisor so it cannot restart the VM:

```bash
"$HOME/kin-node/kin-host" halt
systemctl --user disable --now kin-node-host.service
```

These commands preserve the VM, its disks, Vagrant metadata, releases, and evidence.
There is no destroy command in this runbook. Run `./kin-node inspect-m0` again.

## Gate 2A: clean native host

When inspection says `CLEAN` and the old VM boundary is inert:

```bash
./kin-node check-h0
./kin-node apply-h0
./kin-node check-h1
./kin-node apply-h1
./kin-node status
```

`check-h0` is Ansible check mode. Read its diff before `apply-h0`.

## Gate 2B: native legacy state

Only after reviewing the `LEGACY` inventory:

```bash
./kin-node cutover-m0 --approve-stop-legacy
sudo sha256sum /var/lib/kin-net/migration/legacy-rootfs.tar.gz
./kin-node accept-m0
./kin-node check-h0
./kin-node apply-h0
./kin-node check-h1
./kin-node apply-h1
./kin-node status
```

The hash printed by `sha256sum` must match `PASS M0 ... archive_sha256=...`.
Do not print or copy the archive itself.

An additional exact old Kin root can be included only when deliberately required:

```bash
./kin-node inspect-m0 --legacy-root "$HOME/kin-node"
./kin-node cutover-m0 --legacy-root "$HOME/kin-node" --approve-stop-legacy
```

This may archive a large VM disk and protected SSH/Vagrant material. The old VM root
is already preserved in place, so this option is not normally necessary.

## Acceptance evidence

A successful H1 handoff has all of the following:

- `PASS M0` or `PASS M0 CLEAN`;
- `PASS H0_APPLY` and an exact-source H0 receipt;
- `PASS H1_APPLY` and an exact-source H1 receipt;
- `./kin-node status` returns `kin-config-level-state/v1`, the machine ID, the
  reviewed source commit, and `"config_level": "H1"`;
- old native Kin services are stopped and disabled;
- an old VM and user supervisor remain inert;
- no claim that Postcards, MCP, routing, identity, or inference is operational.

## Failure and recovery boundary

On any failure, stop. Do not remove a path or edit a receipt to make acceptance pass.
M0 leaves original data in place. If it stopped an old native service before archive
creation failed, the specific service can be restored only after reviewing its former
state from the inspection output:

```bash
sudo systemctl enable --now SERVICE_NAME
```

Do not apply that command generically or to OpenBao. For an old VM, re-enable its
user supervisor only if deliberately rolling back to that node. Archive restoration
is intentionally not automated: extraction as `/` is destructive and requires a
separate, path-by-path recovery decision.
