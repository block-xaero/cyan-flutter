#!/usr/bin/env bash
# gate_face.sh <face> — acceptance oracle for one UI face.
#
# The behaviour list in scripts/parity_faces/<face>.txt is AUTHORED BY A HUMAN and
# is the spec. Each line is a behaviour that must exist as a PASSING test. The
# agent writes the implementation and the tests; it cannot choose WHICH
# behaviours count, cannot rename them away, and cannot delete them.
#
# Four checks:
#   1. every behaviour in the manifest maps to a test that RAN and PASSED
#   2. the whole suite is green (no regression in other faces)
#   3. the suite GREW — a stage that deletes tests to go green fails
#   4. flutter analyze reports no errors
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

F="${1:?usage: gate_face.sh <face>}"
LIST="scripts/parity_faces/$F.txt"
BASE="scripts/parity_faces/.suite_high_water"
[ -f "$LIST" ] || { echo "GATE RED: no manifest at $LIST"; exit 1; }

# app_builds is gated by an ACTUAL application build, not by test names. A suite
# can be green while the app does not link.
if [ "$F" = "app_builds" ]; then
  flutter analyze 2>&1 | grep -qE '^\s*error' && { echo "GATE RED: analyze errors"; exit 1; }
  if ! out=$(flutter build macos --debug 2>&1); then
    tail -25 <<<"$out"; echo "GATE RED: the app does not build"; exit 1
  fi
  flutter test >/dev/null 2>&1 || { echo "GATE RED: suite not green"; exit 1; }
  echo "GATE GREEN: the app builds as a real application"; exit 0
fi
fail(){ echo "GATE RED: $*"; exit 1; }

out=$(flutter test --reporter expanded 2>&1)
rc=$?
clean=$(grep -viE 'file_picker|maintainers|inline implementation' <<<"$out")

missing=()
while IFS= read -r b; do
  [ -z "$b" ] && continue
  # a behaviour is satisfied when a PASSING test name contains all its keywords
  kw=$(tr ' ' '\n' <<<"$b" | grep -vE '^(a|an|the|and|is|are|its|it|to|not|of|then|for|from|with|does|do|that|there|per|on|in|at|by)$' | tr '\n' ' ')
  if ! awk -v kws="$kw" '
      /^[0-9:]+ \+[0-9]+/ && !/\-[0-9]+/ {
        line=tolower($0); n=split(kws,a," "); ok=1;
        for(i=1;i<=n;i++){ if(a[i]!="" && index(line,tolower(a[i]))==0){ ok=0; break } }
        if(ok){ found=1 }
      } END { exit !found }' <<<"$clean"; then
    missing+=("$b")
  fi
done < "$LIST"

[ ${#missing[@]} -eq 0 ] || { printf 'GATE RED: no passing test covers:\n'; printf '   - %s\n' "${missing[@]}"; exit 1; }

[ $rc -eq 0 ] || { tail -25 <<<"$clean"; fail "the suite is not green"; }

n=$(grep -oE '\+[0-9]+' <<<"$clean" | tail -1 | tr -d '+')
# Anti-deletion: one shared high-water mark. Stages only ever ADD tests, so a
# count below the highest ever seen means coverage was removed. Serial execution
# makes this exact — it was racy while stages ran concurrently.
prev=$(cat "$BASE" 2>/dev/null || echo 0)
[ "${n:-0}" -ge "$prev" ] || fail "test count fell below the high-water mark ($prev -> $n) — coverage was removed"
[ "${n:-0}" -gt "$prev" ] && echo "${n:-0}" > "$BASE"

if out2=$(flutter analyze 2>&1); then :; fi
grep -qE '^\s*error' <<<"$out2" && { grep -E '^\s*error' <<<"$out2" | head -10; fail "analyze reports errors"; }

echo "GATE GREEN: face '$F' — all $(wc -l < "$LIST" | tr -d ' ') behaviours covered by passing tests; ${n} tests total"
