# Cyan Flutter — Parity Tracker (durable state for the unattended loop)

**Goal:** bring `cyan_flutter` to parity with the blessed SwiftUI app (Monokai, same UX),
**Windows-first** then Linux. macOS/iOS stays primary. **UI-only** port behind a frozen
contract; backend is identical (cyan-backend FFI + Cyan Lens).

**Baseline (frozen target):** every backend/contract repo is pinned at tag
`swiftui-parity-baseline-2026-06-29` (cyan-iOS, cyan-backend, cyan-lens, cyan-iac, cyan-mcp,
xaeroID, cyan-identity, xaeroflux). The port reproduces the SwiftUI screens that exist at
that tag — nothing newer (no Frame.io/annotation UI; that's a later, separate pass).

## How the loop runs (read this first, every run)
- **You (the agent) write Dart + push; you do NOT run Flutter** (no Flutter in this env).
- **The gate is CI** — `.github/workflows/flutter-parity.yml` runs `flutter analyze` +
  `flutter test` (widget + golden) on every push to `feat/flutter-parity`. Tier-1 (vs
  `FakeCyanBackend`) needs no backend and must stay green. Tier-2 (real FFI) is deferred.
- **Branch `feat/flutter-parity` only. NEVER main. Never touch cyan-backend/lens/mcp/forge** —
  UI-only in `cyan_flutter`. Contract is frozen + additive-only.
- **Each run:** read this tracker → pick the next `todo`/`ci-red` screen → write/fix its
  Dart + golden → commit (one screen per commit) → push → update the rows below → write a
  one-line digest at the bottom. **Synchronous only; never wait on a background task.** On a
  persistent red, mark the screen `blocked` with the reason and move to the next independent
  screen — never fake a pass, never weaken a test.

## Phases
- **P0 — Harness + gate (unblocks everything):** `FakeCyanBackend` (Dart, mirrors the
  `CyanBackend` seam), `golden_toolkit` + `integration_test` in pubspec, `flutter-parity.yml`
  CI, a trivial golden proving the gate runs green. **← start here.**
- **P1 — Windows `.dll` + FFI round-trip (later):** cross-compile cyan-backend@baseline →
  Windows `.dll`, wire flutter_rust_bridge, integration test boots engine + `cyan_seed_demo`
  reads 3 groups/10 boards. (Tier-2; needs a Flutter+Rust runner — defer behind P0/P2.)
- **P2..N — Screen-by-screen parity (golden vs the Day-0 SwiftUI reference shots):** order
  by value below.

## Reference screenshots (YOUR Day-0 task, Rick)
Golden targets = screenshots of the blessed Mac app. Drop them in `test/golden/reference/`.
Until they exist, goldens are self-generated (structure) and re-baselined against your shots.
Needed: Login, All-Boards/living-wall, Explorer, Board faces (Workflow/Notes/Dashboard DAG+run),
Ops console (Runs/Cost/Efficiency), Marketplace, Lens, Chat.

## Screen status  (todo · in-progress · ci-green · ci-red · blocked)
| # | screen | tier-1 (Fake) | golden | notes |
|---|---|---|---|---|
| 0 | **harness + CI gate** | in-progress (ci-green-pending) | in-progress | P0 — FakeCyanBackend + CyanBackend seam + flutter-parity.yml + trivial widget test + golden baseline step |
| 1 | Boards grid + living wall | in-progress (ci-green-pending) | in-progress | ParityBoardsGrid via seam (no direct FFI); masonry Monokai cards + living-wall running pill; widget test + golden |
| 2 | Explorer / group tree | todo | todo | groups → workspaces → boards |
| 3 | Board: Workflow (author) | todo | todo | step cells, compile |
| 4 | Board: Dashboard (DAG + gated run) | todo | todo | collapsed pipeline steps, AI+human, Approve/Complete |
| 5 | Board: Notes | todo | todo | markdown |
| 6 | Ops console — Runs | todo | todo | 4-lane feed, action-needed |
| 7 | Ops console — Cost (asset-min meter) | todo | todo | per-workflow + tenant reconcile |
| 8 | Ops console — Efficiency | todo | todo | approval-wait/fail/exec/cache/retry |
| 9 | Marketplace | todo | todo | category-band cards |
| 10 | Lens (nudges/asks/decisions) | todo | todo | |
| 11 | Chat (polish to parity) | todo | todo | exists; align |

## Guardrails
Branch `feat/flutter-parity`; never main; commit per screen; UI-only; contract frozen
(additive only, noted here); golden diffs are truth ("looks close" ≠ pass); macOS Flutter
build kept green as the cheap CI canary. Plugin-foundation work (Frame.io) lives in OTHER
repos on `main` against the frozen tag — these two streams never collide.

## Digest log (newest first)
- 2026-06-29 — P0 bootstrap: added the single `CyanBackend` seam (lib/ffi/cyan_backend.dart) with prod `CyanBackendFFI` (wraps existing CyanFFI, no FFI signature changes) + Tier-1 `FakeCyanBackend` (3 groups / 10 boards / 1 sample run); parity view models (parity_models.dart); Riverpod `cyanBackendProvider` + futures. Ported Boards living wall (row 1) as `ParityBoardsGrid` driven only through the seam (Monokai masonry cards + running pill). Added dev deps (golden_toolkit, integration_test); test harness + trivial gate test (replaced the stale counter `widget_test.dart`) + boards widget/golden tests; `dart_test.yaml` golden tag. Created `.github/workflows/flutter-parity.yml` (analyze + `flutter test --exclude-tags golden`, goldens baselined as artifact). NOTE: agent cannot run Flutter — CI is the first real signal; unverified that everything compiles. GIT BLOCKER: workspace FUSE mount forbids unlink, and a stale `.git/index.lock` + interrupted rebase on `main` could not be cleared from this environment, so the branch/commit/push could not be performed here — needs Rick to run the git steps on the host (see report).
