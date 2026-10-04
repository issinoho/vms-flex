#!/usr/bin/env bash
# prepare.sh - build a VMS-ready source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#   3. run the upstream configure on this host, with every platform answer
#      taken from VMS probe results (probed.site) or hand-settled values
#      (vms-manual.site) instead of from Linux
#   4. generate gnulib's headers and config.h, copy them into the tree
#   5. write the MMS source lists and the configuration snapshot
#
# Nothing in staging/ is ever edited by hand: fix things in patches/ or overlay/.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
tarball=$top/cache/$(basename "$UPSTREAM_URL")
stage=$top/staging/$name
hostcfg=$top/cache/hostcfg-$name
cfgdir=$top/overlay/vms/config
snapshot=$top/snapshot
# Configuration answers come from this node's VSI C run; both architectures
# share one CRTL feature set (see docs/vms-environment.md).
PRIMARY_NODE=${PRIMARY_NODE:-ia64}
PRIMARY_TRIPLET=ia64-hp-openvms

step() { echo "prepare: $*"; }
die() { echo "prepare: error: $*" >&2; exit 1; }

"$top/tools/fetch.sh" >/dev/null

# --- 2. extract, patch, overlay -------------------------------------------
step "extracting $name"
rm -rf "$stage"
mkdir -p "$top/staging"
tar -xzf "$tarball" -C "$top/staging"
[ -d "$stage" ] || die "tarball did not unpack to $stage"

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    step "patch $p"
    patch -d "$stage" -p1 -s --no-backup-if-mismatch -F0 < "$top/patches/$p" ||
        die "patch $p does not apply cleanly"
done < "$top/patches/series"

# overlay/ may only add files; changes to upstream files belong in patches/.
(cd "$top/overlay" && find . -type f) | while read -r f; do
    [ -e "$stage/$f" ] && die "overlay/$f would replace an upstream file; use a patch"
    true
done
cp -a "$top/overlay/." "$stage/"

# --- 3. host configure with VMS answers ----------------------------------
step "configure (host, VMS answers)"
rm -rf "$hostcfg"
mkdir -p "$hostcfg"
site=$hostcfg/vms.site
# Answers: the VSI C configure run (vms_configure.sh) if there is one, else the
# function/header probes; vms-manual.site last so it always wins.
answers=$cfgdir/configure-$PRIMARY_NODE.cache
if [ ! -f "$answers" ]; then
    # First pass of a new release: stage the tree for vms_configure.sh, which
    # writes the answers.  The result is not buildable on VMS yet.
    answers=$hostcfg/no-answers.site; : > "$answers"
    step "WARNING: no $(basename "$cfgdir")/configure-$PRIMARY_NODE.cache yet:" \
         "Linux answers (run tools/vms_configure.sh, then prepare again)"
fi
step "answers from $(basename "$answers")"
python3 "$top/tools/nextheaders_site.py" "$stage/configure" "$cfgdir/crtl_modules.txt" \
    > "$cfgdir/next-headers.site"
cat "$answers" "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$site"
mapfile -t cfgargs < <(grep -v -e '^#' -e '^$' "$cfgdir/configure.args")
# Same --host as vms_configure.sh so configure takes the same code paths.
(cd "$hostcfg" && CONFIG_SITE=$site "$stage/configure" -q -C \
    --build="$("$stage/build-aux/config.guess")" --host=$PRIMARY_TRIPLET CC=gcc "${cfgargs[@]}" \
    > configure.out 2>&1) || { tail -20 "$hostcfg/configure.out"; die "configure failed"; }

# --- 4. config.h ----------------------------------------------------------
printvar() {  # printvar <dir> <make variable>
    make -s -C "$hostcfg/$1" -f Makefile -f "$top/tools/printvar.mk" "print-$2"
}
# flex has no gnulib: no generated headers, just src/config.h
# (AC_CONFIG_HEADER([src/config.h])).
cp "$hostcfg/src/config.h" "$stage/src/config.h"

# --- 5. MMS source lists ---------------------------------------------------
# libfl is built twice by explicit rules in descrip.mms (default and AS_IS
# names), so it is not in the generated lists; check it is still two files.
libfl=$(printvar src libfl_la_SOURCES | tr ' ' '\n' | grep '\.c$' | sort | tr '\n' ' ')
[ "$libfl" = "libmain.c libyywrap.c " ] || die "libfl sources changed: $libfl (update descrip.mms)"
lib_srcs=
# flex itself: its sources plus scan.c, the shipped scanner (the Makefile
# copies it to stage1scan.c when not bootstrapping).
# The grammar is listed as parse.y; the release ships the generated parse.c.
src_srcs=$( { printvar src flex_SOURCES; echo scan.c; } | tr ' ' '\n' | sed 's/\.y$/.c/' |
           grep '\.c$' | sort -u)
for f in $src_srcs; do [ -f "$stage/src/$f" ] || die "no src/$f in the release"; done
# Replacement functions from lib/ that configure asks for (LIBOBJS, e.g.
# ${LIBOBJDIR}realloc.o): compiled into flex with the VMS-only sources.
libobjs=$(printvar src LIBOBJS | tr ' ' '\n' | sed -n 's|.*/||; s/\.o$/.c/p')
for list in "$lib_srcs" "$src_srcs"; do
    [ -n "$list" ] || continue
    dups=$(echo "$list" | xargs -n1 basename | sort | uniq -d)
    [ -z "$dups" ] || die "duplicate object names: $dups"
done

mkdir -p "$stage/vms"
echo "$lib_srcs" > "$hostcfg/lib-sources.txt"
echo "$src_srcs" > "$hostcfg/src-sources.txt"
{ cat "$top/overlay/vms/extra-sources.txt"
  for f in $libobjs; do echo "lib/$f"; done; } > "$hostcfg/extra-sources.txt"
GEN_MMS_LIB_BASE=src GEN_MMS_CONFIG_DIR=SRC python3 "$top/tools/gen_mms.py" "$cfgdir/ccflags.txt" "$hostcfg/lib-sources.txt" \
    "$hostcfg/src-sources.txt" "$hostcfg/extra-sources.txt" > "$stage/vms/sources.mms"

# --- PCSI kit inputs (vms/kit/MAKE_KIT.COM builds the kit on each node) ----
step "PCSI kit inputs"
: "${KIT_PRODUCER:=ISSINOHO}"
# Three-part versions: the third part is the PCSI update and our VMS patch
# level the ECO, as in vms-bison, so 2.6.4-vms1 is V2.6-4E1.
IFS=. read -r major minor update _ <<< "$UPSTREAM_VERSION"
pcsiversion="V$major.$minor-${update:-0}E$VMS_PATCH_LEVEL"
kitversion="$UPSTREAM_VERSION-vms$VMS_PATCH_LEVEL"
kit=$stage/vms/kit
subst() {
    sed -e "s/@PRODUCER@/$KIT_PRODUCER/g" -e "s/@BASE@/$1/g" \
        -e "s/@PCSIVERSION@/$pcsiversion/g" -e "s/@VERSION@/$UPSTREAM_VERSION/g" \
        -e "s/@KITVERSION@/$kitversion/g" -e "s/@ARCH@/$2/g"
}
for base in I64VMS X86VMS; do
    subst $base "" < "$kit/flex.pcsi\$desc_template" > "$kit/FLEX-$base.PCSI\$DESC"
    subst $base "" < "$kit/flex.pcsi\$text_template" > "$kit/FLEX-$base.PCSI\$TEXT"
done
rm -f "$kit/flex.pcsi\$desc_template" "$kit/flex.pcsi\$text_template"
mv "$kit/flex\$startup.com" "$kit/FLEX\$STARTUP.COM"
mv "$kit/flex\$setup.com" "$kit/FLEX\$SETUP.COM"
subst "" "IA64 and x86-64" < "$kit/readme.vms" > "$kit/README.VMS"; rm -f "$kit/readme.vms"
mkdir -p "$kit/doc"
cp "$stage/COPYING" "$kit/doc/COPYING."
cp "$stage/NEWS" "$kit/doc/NEWS."
cp "$stage/doc/flex.1" "$kit/doc/FLEX.1"
cp "$stage/vms/wc.l" "$kit/doc/WC.L"
# The manual: the doc/flex.info* files are plain text apart from Info's
# control lines (no makeinfo needed on the host).
cat "$stage/doc/flex.info-"[0-9]* |
    sed -e '/^\x1f/d' -e '/^Tag Table:/,$d' -e 's/\x7f[0-9]*//' |
    tr -d '\000-\010\016-\037\177' > "$kit/doc/FLEX.TXT"
printf 'KIT_PRODUCER=%s\nPCSI_VERSION=%s\nKIT_VERSION=%s\n' "$KIT_PRODUCER" "$pcsiversion" \
    "$kitversion" > "$kit/kit.env"

# --- snapshot: the resolved configuration, committed and reviewed ----------
mkdir -p "$snapshot"
cp "$hostcfg/src/config.h" "$snapshot/config.h"
echo "$lib_srcs" > "$snapshot/lib-sources.txt"
echo "$src_srcs" > "$snapshot/src-sources.txt"
# Every cached answer, and where it came from.
cat "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$hostcfg/manual.site"
python3 "$top/tools/cfgreport.py" "$hostcfg/config.cache" "$answers" \
    "$hostcfg/manual.site" > "$snapshot/cache-answers.txt"
step "inherited-from-Linux answers: $(grep -c ' host$' "$snapshot/cache-answers.txt" || true)" \
     "(see snapshot/cache-answers.txt)"

step "staged $stage"
if ! git -C "$top" diff --quiet -- snapshot 2>/dev/null; then
    step "snapshot/ changed - review with: git diff -- snapshot"
fi
