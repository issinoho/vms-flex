#!/usr/bin/env bash
# installcheck.sh <node> - install the node's kit, verify it, run m4 from it
# (macro expansion, syscmd/esyscmd, error status), and remove it again.
# This changes the system while it runs (PCSI database, SYS$COMMON:[M4],
# M4$ROOT); run kit.sh first.
# Output: out/install-<node>.txt (don't redirect this script's stdout there).
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: installcheck.sh <node>}
. "$top/upstream.conf"
REMOTE=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _ | tr a-z A-Z)
"$top/tools/vms.sh" "$node" put "$top/tools/vms_installcheck.com" >/dev/null
read -r _ _ _ _ _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
mkdir -p "$top/out"
log=$top/out/install-$node.txt
job=$top/cache/installcheck-$node.com
printf '$ set noon\n$ @%sVMS_INSTALLCHECK.COM %s\n' "$WORKDIR" "$REMOTE" > "$job"
VMS_TIMEOUT=1800 "$top/tools/vms.sh" "$node" run "$job" > "$log" 2>&1
grep -aE 'install status|Installed|startup procedure|M4_[A-Z_]*: |SUCREMOVE|after removal|items found' "$log"
for check in VERSION EXPAND ESYSCMD ERROR_SEVERITY; do
    grep -aq "M4_$check: PASS" "$log" || { echo "installcheck: M4_$check did not pass" >&2; exit 1; }
done
grep -aq 'M4\$ROOT after removal: \[\]' "$log" &&
    grep -aq 'files after removal: \[\]' "$log" &&
    grep -aq 'startup after removal: \[\]' "$log"
