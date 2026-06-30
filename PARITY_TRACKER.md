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

## Reference screenshots (OPTIONAL — human eyeball reference only, NOT a gate)
Flutter goldens are generated from the Flutter widgets themselves and lock the Flutter UI
against its own regressions — nothing auto-diffs them against Mac screenshots. So the loop
matches the LOOK from the SwiftUI SOURCE (read-only at `/Users/anirudhvyas/cyan-iOS-ready`)
plus the already-ported Monokai theme. **Do NOT wait on screenshots; never block a screen on
them.** They're purely a human side-by-side aid. If Rick drops any in `test/golden/reference/`
(hero screens are enough: Boards/living-wall, Dashboard DAG+run, Ops console), great; if not,
proceed and Rick eyeballs the built app at the end.

## Screen status  (todo · in-progress · ci-green · ci-red · blocked)
| # | screen | tier-1 (Fake) | golden | notes |
|---|---|---|---|---|
| 0 | **harness + CI gate** | in-progress (ci-green-pending) | in-progress | P0 — FakeCyanBackend + CyanBackend seam + flutter-parity.yml + trivial widget test + golden baseline step |
| 1 | Boards grid + living wall | in-progress (ci-green-pending) | in-progress | ParityBoardsGrid via seam (no direct FFI); masonry Monokai cards + living-wall running pill; widget test + golden |
| 2 | Explorer / group tree | in-progress (ci-green-pending) | in-progress | ParityExplorerTree via `groupsProvider` seam; Group→Workspace→Board tree, expand/collapse chevrons, type-colored icons, level indent (20px), search filter, selection; widget + golden tests |
| 3 | Board: Workflow (author) | in-progress (ci-green-pending) | in-progress | ParityWorkflowView via boardWorkflowProvider seam; numbered step cells + inference chips (tool/send-to/bound/gate), deployed-locked banner, composer; widget + golden |
| 4 | Board: Dashboard (DAG + gated run) | in-progress (ci-green-pending) | in-progress | ParityDashboardView via boardRunProvider seam; run header + status pill, horizontal DAG of step boxes (AI lane + human lane signals), yellow approval gate (AI Approve/Reject, human Complete), collapsed step list; widget + golden |
| 5 | Board: Notes | in-progress (ci-green-pending) | in-progress | ParityNotesView via boardNotesProvider seam; VSCode-style editor — toolbar (file name + saved dot), line-number gutter, monospaced body with markdown coloring (headings cyan, lists green, quotes muted), status bar (Ln/Col · lines · words · UTF-8); widget + golden |
| 6 | Ops console — Runs | in-progress (ci-green-pending) | in-progress | ParityOpsRuns via opsRunsProvider seam; shared OpsScaffold (Runs/Cost/Efficiency segmented header) + 4 lanes (Queued/Running/Action needed/Done), cinematic 16:9 run cards (status badge, stage/duration strip, in-flight progress, monospaced steps/cost/dur meta, Retry / Approve+Reject actions); widget + golden |
| 7 | Ops console — Cost (asset-min meter) | in-progress (ci-green-pending) | in-progress | ParityOpsCost via costMeterProvider seam; 5-stat headline (billed-min cyan / billed $ green / retry-min orange / saved-min purple / runs), GPU=COGS footnote (margin not billed), per-workflow reconcile table; widget + golden |
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
- 2026-06-29 — Row 7 (Ops console — Cost): added `ParityOpsCost` (lib/widgets/parity/parity_ops_cost.dart) via `costMeterProvider`, wrapped in the shared OpsScaffold (Cost face selected). SwiftUI `OperationsConsoleView` Cost face: scope header ("Asset-minute meter — all boards (tenant)", yellow "awaiting lens meter" when !hasMeter), a five-stat headline of surface cards (billed-min cyan / billed $ green / retry-min orange / saved-min purple / runs foreground), the GPU=COGS footnote ("internal COGS (margin, not billed): X compute-min · Y gpu-sec"), and a per-workflow reconcile table (workflow | runs | assets | billed-min cyan | billed $ green | retry-min orange-if-positive). Extended seam (+`loadCostMeter`); prod FFI returns hasMeter:false zero meter; Fake seeds the 24.5/$12.30 meter + 3 workflow rows. Added parity models `CostMeter`/`WorkflowCost`. Added `test/ops_cost_test.dart`: 1 widget test (headline+footnote+table) + golden `golden/ops_cost.png`. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 6 (Ops console — Runs): added `ParityOpsRuns` (lib/widgets/parity/parity_ops_runs.dart) + shared `OpsScaffold` (lib/widgets/parity/parity_ops_scaffold.dart), driven only through the seam via `opsRunsProvider`. SwiftUI `OperationsConsoleView` Runs face: console header (grid icon + "Ops console" + Runs/Cost/Efficiency segmented control), runs split into 4 lanes (Queued muted / Running cyan / Action needed yellow [approval+stuck+failed] / Done green) each with a colored dot + count, and cinematic 16:9 run cards — gradient poster + film glyph, top-left status badge (Queued/Running/Approval/Stuck/Done/Failed colors), bottom-right stage label (in-flight) or duration timecode (terminal), an in-flight LinearProgressIndicator (currentStep/stepCount), a monospaced meta row (steps X/Y · cost $ · dur), and inline actions (failed → Retry orange outline; approval → Approve green filled + Reject red outline). Extended seam (+`loadOpsRuns`); prod FFI returns []; Fake seeds 6 runs across the lanes. Added parity models `OpsRun`/`RunStatus`(+needsAction). Added `test/ops_runs_test.dart`: 2 widget tests (lanes+cards render, Retry fires onRetry with the failed run) + golden `golden/ops_runs.png`. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 5 (Board: Notes): added `ParityNotesView` (lib/widgets/parity/parity_notes_view.dart) — SwiftUI `NotesEditorView` parity, driven only through the seam via `boardNotesProvider`. VSCode-style: toolbar (green doc icon + file name + type chevron, right-side green "Saved" dot + save icon), a 50px right-aligned monospaced line-number gutter, a surfaceLighter editor body rendering each line monospaced with light markdown coloring (# heading → cyan, list/numbered → green, > quote → comment, else foreground), and a status bar (Ln 1, Col 1 · N lines · N words · UTF-8). Extended seam (+`loadNotes`); prod FFI returns an empty notes.md (Tier-2 deferred); Fake seeds a deployment.md doc for b-eng-4. Added parity model `BoardNotes`. Added `test/notes_view_test.dart`: 1 widget test (toolbar/content/status render) + golden `golden/notes_editor.png`. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 4 (Board: Dashboard DAG + gated run): added `ParityDashboardView` (lib/widgets/parity/parity_dashboard_view.dart) — SwiftUI `DashboardView`/`PipelinePreviewView` parity, driven only through the seam via the existing `boardRunProvider` (no seam change needed — uses the row-1 `WorkflowRun`/`RunStep` models). Run header with title + computed status pill (Done green / Running cyan / Queued muted) + "X / Y steps complete"; horizontal DAG of 142x84 step boxes connected by arrows, each box carrying a dual signal — AI (machine) lane [queued/running/done/failed icon+color] and human (gate) lane [Awaiting you yellow / Approved green / Rejected red]; a yellow approval-gate panel per awaiting-approval step (human → "Complete" green filled; AI → "Approve" green + "Reject" red outline); a collapsed compact step list with status dots + AI/Human tag; and a "No run yet" empty state for boards without a run. Added `test/dashboard_view_test.dart`: 4 widget tests (header+DAG+list render, gate buttons, Complete fires onApprove with step s3, empty state) + golden `golden/dashboard_dag.png`. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 3 (Board: Workflow author): added `ParityWorkflowView` (lib/widgets/parity/parity_workflow_view.dart) — SwiftUI `WorkflowView` parity, driven only through the seam via `boardWorkflowProvider`. Toolbar (Review cyan / Run green / Deploy purple / Reset muted, disabled when no steps or locked), purple "Deployed & locked" banner for deployed boards, numbered-circle step cells with compiled inference chips (tool=cyan extension, bound inputs=green #, send-to=purple, gate chip yellow "Awaiting approval" / green "No approval needed"), orange ambiguity warning, empty state, and the @/#// composer with cyan "Add step". Extended `CyanBackend` seam (+`loadWorkflow`) — additive; prod FFI returns an honest empty `Workflow` (Tier-2 hydration deferred), Fake seeds a compiled+locked 4-step flow for b-eng-1, an uncompiled 3-step (one ambiguous) for b-eng-2. Added parity models `Workflow`/`WorkflowStep`/`StepGate`. Added `test/workflow_view_test.dart`: 4 widget tests (steps+chips render, Run fires, ambiguous warning, empty state) + golden `golden/workflow_author.png`. Commit 3848d43. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 2 (Explorer / group tree): added `ParityExplorerTree` (lib/widgets/parity/parity_explorer_tree.dart) — SwiftUI `FileTreeView` parity, driven only through the `CyanBackend` seam via `groupsProvider` (no direct FFI). Group→Workspace→Board tree with expand/collapse chevrons, type-colored Monokai icons (group=group color, workspace=green, board=face color), level*20+8 indentation, "Files" header + cyan (+) button, live search filter (matches + ancestors), row selection tint, empty/no-match states. Tree seeds fully-expanded once for deterministic goldens. Added `test/explorer_tree_test.dart`: 4 widget tests (hierarchy renders, collapse hides children, board tap → onOpenBoard, search filters) + golden `golden/explorer_tree.png` (tagged `golden`). NOTE: agent cannot run Flutter — CI is the first real signal; unverified that it compiles. Human must push `feat/flutter-parity`.
- 2026-06-29 — P0 bootstrap: added the single `CyanBackend` seam (lib/ffi/cyan_backend.dart) with prod `CyanBackendFFI` (wraps existing CyanFFI, no FFI signature changes) + Tier-1 `FakeCyanBackend` (3 groups / 10 boards / 1 sample run); parity view models (parity_models.dart); Riverpod `cyanBackendProvider` + futures. Ported Boards living wall (row 1) as `ParityBoardsGrid` driven only through the seam (Monokai masonry cards + running pill). Added dev deps (golden_toolkit, integration_test); test harness + trivial gate test (replaced the stale counter `widget_test.dart`) + boards widget/golden tests; `dart_test.yaml` golden tag. Created `.github/workflows/flutter-parity.yml` (analyze + `flutter test --exclude-tags golden`, goldens baselined as artifact). NOTE: agent cannot run Flutter — CI is the first real signal; unverified that everything compiles. GIT BLOCKER: workspace FUSE mount forbids unlink, and a stale `.git/index.lock` + interrupted rebase on `main` could not be cleared from this environment, so the branch/commit/push could not be performed here — needs Rick to run the git steps on the host (see report).
