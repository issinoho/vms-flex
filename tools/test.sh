#!/usr/bin/env bash
# test.sh <node> - run [.VMS]TEST_SMOKE.COM against the built image on <node>.
# Output is saved to out/smoke-<node>.log; exit status 0 only if all tests pass.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: test.sh <node>}
. "$top/upstream.conf"
remote=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _ | tr a-z A-Z)
read -r _ _ _ _ _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")

mkdir -p "$top/out"
job=$top/cache/smoke-$node.com
# flex runs the node's vms-m4 build (M4_TREE in upstream.conf).
m4img="${WORKDIR%]}.$M4_TREE.BIN_"
{ echo '$ set noon'
  echo '$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")'
  echo "\$ m4img = \"$m4img\" + arch + \"]M4.EXE\""
  echo "\$ @${WORKDIR%]}.$remote.VMS]TEST_SMOKE.COM 'm4img'"
} > "$job"
"$top/tools/vms.sh" "$node" run "$job" | grep -v '^$' | tee "$top/out/smoke-$node.log"
grep -q 'SMOKE: [0-9]* passed, 0 failed' "$top/out/smoke-$node.log"
