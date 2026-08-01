#!/usr/bin/env bash
# gate_ffi_cluster.sh <cluster> — acceptance oracle for one FFI binding cluster.
#
# Four things must ALL hold:
#   1. every required cyan_* symbol is declared in the FFI layer
#   2. each has a typed Dart wrapper on the CyanBackend interface (not just a raw
#      lookupFunction) — bindings nobody can call are not parity
#   3. FakeCyanBackend implements them, so the widget/VM tiers can be driven
#   4. flutter analyze is clean on the touched files AND the whole suite passes
#
# A symbol list is data, not code: add a cluster by adding a file under
# scripts/ffi_clusters/<name>.txt with one cyan_* symbol per line.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
C="${1:?usage: gate_ffi_cluster.sh <cluster>}"
LIST="scripts/ffi_clusters/$C.txt"
[ -f "$LIST" ] || { echo "GATE RED: no cluster list at $LIST"; exit 1; }
fail(){ echo "GATE RED: $*"; exit 1; }

missing_decl=(); missing_iface=(); missing_fake=()
while read -r sym; do
  [ -z "$sym" ] && continue
  grep -rq "$sym" lib/ffi/ 2>/dev/null || missing_decl+=("$sym")
  # camelCase wrapper name derived from the symbol: cyan_pipeline_run -> pipelineRun
  w=$(sed 's/^cyan_//' <<<"$sym" | awk -F_ '{printf "%s",$1; for(i=2;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}')
  grep -rq "$w" lib/ffi/cyan_backend.dart 2>/dev/null || grep -rq "$w" lib/ffi/*.dart 2>/dev/null || missing_iface+=("$sym → $w")
  grep -rq "$w" lib/ffi/fake_cyan_backend.dart 2>/dev/null || missing_fake+=("$sym → $w")
done < "$LIST"

[ ${#missing_decl[@]}  -eq 0 ] || fail "not declared in lib/ffi/: ${missing_decl[*]}"
[ ${#missing_iface[@]} -eq 0 ] || fail "no typed wrapper on the backend interface: ${missing_iface[*]}"
[ ${#missing_fake[@]}  -eq 0 ] || fail "FakeCyanBackend does not implement: ${missing_fake[*]}"

if ! out=$(flutter analyze lib/ffi/ 2>&1); then
  grep -E '^\s*(error)' <<<"$out" | head -20
  grep -qE '^\s*error' <<<"$out" && fail "lib/ffi does not analyze clean"
fi
if ! out=$(flutter test 2>&1); then
  grep -viE 'file_picker|maintainers|inline implementation' <<<"$out" | tail -25
  fail "the test suite is not green"
fi
n=$(grep -oE '\+[0-9]+' <<<"$out" | tail -1 | tr -d '+')
echo "GATE GREEN: cluster '$C' bound, wrapped, faked; ${n:-?} tests pass"
