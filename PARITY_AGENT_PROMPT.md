You are driving the Cyan Flutter parity port to COMPLETION on this Mac. You have Flutter, git
credentials, and a normal filesystem — USE them: actually run the gate, commit, and push. Work
continuously and autonomously, screen after screen, until every row reaches parity and the full
test suite is green. DO NOT stop after one screen and DO NOT stop to ask — grind to done.

REPO: ~/cyan_flutter (this repo). BRANCH: feat/flutter-parity. CONTRACT + DURABLE STATE: read
PARITY_TRACKER.md fully and obey its Guardrails. Status: the P0 harness (the `CyanBackend` seam +
`FakeCyanBackend` + providers in lib/ffi/ + lib/providers/) and rows 1–8 widgets were written
BLIND (committed without ever compiling — expect errors); Marketplace (row 9) is mid-commit;
Lens (10) and Chat (11) are todo.

== STEP 0 — get to a clean, known state ==
- `git status`. An interrupted run left the tree messy (staged deletions of already-committed
  widgets + modified seam files). Reconcile: if uncommitted changes are coherent in-progress work
  (Marketplace + seam extensions), finish and commit them; if they are cruft/half-deletions of
  files that already exist in HEAD, discard them (`git restore <file>`) back to the last good
  commit. Finish STEP 0 with a clean `git status` on `feat/flutter-parity` (create it off `main`
  if you're not on it — NEVER work on main).
- `flutter pub get`.

== STEP 1 — make what already exists actually GREEN ==
- Run `flutter analyze` then `flutter test`. Rows 1–8 never compiled, so there will be real
  errors. FIX them properly (type errors, missing imports, API mismatches). Iterate
  analyze → fix → test until the existing suite passes. Commit the fixes with clear messages.
- NEVER weaken, skip, or delete a test to get green. If a golden needs a first baseline, generate
  it with `flutter test --update-goldens` and commit the PNG.

== STEP 2 — finish the remaining screens (Marketplace 9, Lens 10, Chat 11), ONE AT A TIME ==
For each remaining row, in order:
1. Read the SwiftUI reference (READ-ONLY) under ~/cyan-iOS-ready/Cyan/Cyan/Views and
   .../ViewModels to match behavior + Monokai aesthetics.
2. Build the widget driven ONLY through the `CyanBackend` seam (extend `FakeCyanBackend` with the
   deterministic seeded data that screen needs) + a Riverpod provider. No widget calls FFI directly.
3. Add a widget test (vs `FakeCyanBackend`) + a golden.
4. `flutter analyze && flutter test` until that screen is green.
5. Commit (one screen per commit, clear message). Update that row in PARITY_TRACKER.md → ci-green
   and append a dated one-line digest. Then move to the next screen.

== STEP 3 — push + loop to PARITY ==
- After each green screen (or milestone) `git push` (you have creds) so it's backed up and CI runs.
- Keep going until EVERY row in PARITY_TRACKER.md is genuinely green (`flutter analyze` clean +
  `flutter test` fully passing) and pushed. That is parity. Then do one final full
  `flutter analyze && flutter test`, fix any straggler, push, and summarize what's complete.

== RULES (non-negotiable) ==
- Branch `feat/flutter-parity` only. NEVER commit to main.
- UI-only in ~/cyan_flutter. NEVER touch cyan-backend / cyan-lens / cyan-mcp / cyan-forge or any
  other repo. The FFI/command/event contract is frozen (additive only).
- Everything goes through the `CyanBackend` seam (prod `CyanBackendFFI`, test `FakeCyanBackend`).
- No fake passes, no weakened tests, no `// ignore` to dodge analyze. Real green only.
- Commit per screen; keep PARITY_TRACKER.md status + digest current.
- Autonomous + continuous: do not pause to ask between screens; grind the whole list to green.
