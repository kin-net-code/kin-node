#!/usr/bin/env bash
set -Eeuo pipefail

tool_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

"$tool_root/kin-node" apply-h0
h0_second_apply=$("$tool_root/kin-node" apply-h0 2>&1)
printf '%s\n' "$h0_second_apply"
grep -Eq 'changed=0 .*failed=0' <<<"$h0_second_apply" || {
  printf 'FAIL  second H0 apply was not idempotent\n' >&2
  exit 1
}

"$tool_root/kin-node" apply-h1
h1_second_apply=$("$tool_root/kin-node" apply-h1 2>&1)
printf '%s\n' "$h1_second_apply"
grep -Eq 'changed=0 .*failed=0' <<<"$h1_second_apply" || {
  printf 'FAIL  second H1 apply was not idempotent\n' >&2
  exit 1
}

"$tool_root/kin-node" accept-h0
"$tool_root/kin-node" accept-h1
"$tool_root/kin-node" status | grep -Fq '"config_level": "H1"'
printf 'PASS  H0_H1_LIVE_ACCEPTANCE\n'
