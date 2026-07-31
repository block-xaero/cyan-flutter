#!/usr/bin/env bash
# gate_dashboard_events.sh — the acceptance oracle for the Dashboard event union.
#
# Run by cyan-dev-loop as the stage gate. Exit 0 == the stage is green.
# Three things must ALL hold; any one failing is a red.
#
#   1. THE TEST FILE IS UNMODIFIED. Pinned by checksum, not by `git diff`,
#      because an agent can commit its own edit and defeat a diff check. If the
#      oracle can be edited by the thing being tested, it is not an oracle.
#   2. The new file analyzes clean. Scoped to that ONE file on purpose — the
#      repo carries 666 pre-existing analyze warnings, so a repo-wide clean
#      would be red for reasons no agent here caused.
#   3. The WHOLE suite passes. The 48 tests that already pass must keep passing:
#      converging one stage by breaking another is not convergence.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

TEST=test/dashboard_event_test.dart
IMPL=lib/models/dashboard_event.dart
# Checksum of the oracle as authored. Changing the oracle is a deliberate human
# act — update this line in the same commit, never to make a run go green.
WANT_SHA="acdc01366e2b506ac867dee20365f6a3caef7b9eb5ead31cd5f7b328a0c46d8b"

fail() { echo "GATE RED: $*"; exit 1; }

[ -f "$TEST" ] || fail "the oracle $TEST is missing"
GOT_SHA=$(shasum -a 256 "$TEST" | cut -d' ' -f1)
[ "$GOT_SHA" = "$WANT_SHA" ] || fail "the oracle $TEST was MODIFIED (want ${WANT_SHA:0:12}, got ${GOT_SHA:0:12}) — the test defines done; it is not part of the work"

[ -f "$IMPL" ] || fail "$IMPL does not exist yet"

if ! out=$(flutter analyze "$IMPL" 2>&1); then
  if grep -qE '^\s*(error|warning)' <<<"$out"; then
    echo "$out" | grep -E '^\s*(error|warning)' | head -20
    fail "$IMPL does not analyze clean"
  fi
fi

if ! out=$(flutter test 2>&1); then
  echo "$out" | grep -viE 'file_picker|maintainers|inline implementation' | tail -30
  fail "the test suite is not green"
fi

echo "GATE GREEN: oracle intact, $IMPL analyzes clean, full suite passes"
