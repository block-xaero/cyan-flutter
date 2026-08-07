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
| 0 | **harness + CI gate** | ci-green | ci-green | P0 — FakeCyanBackend + CyanBackend seam + flutter-parity.yml + trivial widget test + golden baseline step |
| 1 | Boards grid + living wall | ci-green | ci-green | ParityBoardsGrid via seam (no direct FFI); masonry Monokai cards + living-wall running pill; widget test + golden |
| 2 | Explorer / group tree | ci-green | ci-green | ParityExplorerTree via `groupsProvider` seam; Group→Workspace→Board tree, expand/collapse chevrons, type-colored icons, level indent (20px), search filter, selection; widget + golden tests |
| 3 | Board: Workflow (author) | ci-green | ci-green | ParityWorkflowView via boardWorkflowProvider seam; numbered step cells + inference chips (tool/send-to/bound/gate), deployed-locked banner, composer; widget + golden |
| 4 | Board: Dashboard (DAG + gated run) | ci-green | ci-green | ParityDashboardView via boardRunProvider seam; run header + status pill, horizontal DAG of step boxes (AI lane + human lane signals), yellow approval gate (AI Approve/Reject, human Complete), collapsed step list; widget + golden |
| 5 | Board: Notes | ci-green | ci-green | ParityNotesView via boardNotesProvider seam; VSCode-style editor — toolbar (file name + saved dot), line-number gutter, monospaced body with markdown coloring (headings cyan, lists green, quotes muted), status bar (Ln/Col · lines · words · UTF-8); widget + golden |
| 6 | Ops console — Runs | ci-green | ci-green | ParityOpsRuns via opsRunsProvider seam; shared OpsScaffold (Runs/Cost/Efficiency segmented header) + 4 lanes (Queued/Running/Action needed/Done), cinematic 16:9 run cards (status badge, stage/duration strip, in-flight progress, monospaced steps/cost/dur meta, Retry / Approve+Reject actions); widget + golden |
| 7 | Ops console — Cost (asset-min meter) | ci-green | ci-green | ParityOpsCost via costMeterProvider seam; 5-stat headline (billed-min cyan / billed $ green / retry-min orange / saved-min purple / runs), GPU=COGS footnote (margin not billed), per-workflow reconcile table; widget + golden |
| 8 | Ops console — Efficiency | ci-green | ci-green | ParityOpsEfficiency via efficiencyProvider seam; 5 insight cards (gate bottleneck yellow / failure hotspot red / step speed orange / cache purple / retry cyan) + per-step table (runs/gate-p95/fail/top error/exec-p95/cache/retry, ms humanized); widget + golden |
| 9 | Marketplace | ci-green | ci-green | ParityMarketplace via marketplaceProvider seam; header (search + Publish), Featured aisle (horiz), All-plugins masonry of category-band cards (tinted header + glyph + category badge, name/publisher/summary, stage+placement chips, trust + side-effect badges, rating, "Use in a workflow" CTA); widget + golden |
| 10 | Lens (nudges/asks/decisions) | ci-green | ci-green | ParityLensView via lensIntelligenceProvider seam; header (Lens AI + connection dot/status + refresh), "Intelligence" band, 4-tab control (Nudges orange + count badge / Asks cyan / Decisions green / Graph purple), per-tab cards — nudge (icon tile + title + age + detail + board + green Resolve), ask (asker→assignee · age · status pill, answered shows answer+answerer, open shows Answer/Dismiss), decision (content + rationale + decider + age + agree/disagree/comment counts); widget + golden |
| 11 | Chat (polish to parity) | ci-green | ci-green | ParityChatView via boardChatProvider seam; SwiftUI ChatPanel/ChatMessageView "Claude-style" transcript — header (forum icon + board title + "Board chat" + green online pill), left-aligned messages with colored author (own cyan / other green) + faint timestamp + light inline-markdown body (**bold** + `code`), composer (Message… field + cyan Send); widget + golden |
| 12 | Login / landing (front door) | ci-green | n/a | ParityLoginView — PRE-SESSION, so plain callbacks, NOT the seam (login happens before a backend session exists). Brand block (mark + "Cyan" + "Decentralized Collaboration"), two-mode segmented picker (Personal / Organization), personal = Create your identity (no account) + offline promise + Restore (Scan QR · Backup key), organization = optional tenant field + Sign in with your organization, red error notice box, loading overlay, durable-XaeroID footer; 8 widget tests (`test/login_view_test.dart`) |

## Tier-2 — the REAL engine (Windows, cyan-win)  ← live section
The 302 widget tests all drive `FakeCyanBackend`; they prove wiring and say nothing about
whether the engine is reached. Tier-2 runs against the natively built
`cyan-backend/target/release/cyan_backend.dll`, staged at `windows\Libraries\`.
Run with `flutter test integration_test/<file> -d windows` (Flutter 3.38.6, `C:\flutter\bin`).

| # | tier-2 target | status | notes |
|---|---|---|---|
| T1 | `integration_test/real_engine_test.dart` | **green (4/4, Windows)** | engine loads from `windows\Libraries`, `cyan_init` writes a real db, full 157-verb surface resolves. The reported ":66 stale symbols" was a misdiagnosis — dumpbin `/EXPORTS` confirms every listed verb exists; the failure was `tearDownAll` (no engine shutdown verb ⇒ SQLite stays open ⇒ Windows won't unlink). |
| T2 | `integration_test/engine_roundtrip_test.dart` | **green (2/2, Windows)** | passed on Windows unmodified: `cyan_init_with_identity` boots, `cyan_create_group`/`cyan_create_workspace` write, and the event bus + `cyan_get_workspaces_for_group` agree on the full set. The Windows write path is real. |
| T3 | Boards wall + Explorer tree (`integration_test/tree_hydration_test.dart`) | **green (3/3, Windows)** | `loadGroups`/`loadAllBoards` now read the engine's tree dump. Seeded engine ⇒ real group names + colours, both workspaces per group (incl. the empty **Plugins** one), 10 boards, and the wall and the tree agree on who owns what. Negative control run: disabling the snapshot turns all 3 red and the wall falls back to "Unknown group". |
| T4 | Board: Workflow author face (`integration_test/workflow_face_test.dart`) | **green (6/6, Windows)** | reads the seeded steps in `cell_order` with the compile's real chips (executor, `depends_on`, gate), the deploy lock, the unfiltered notebook document — and WRITES: authoring and editing a step now round-trips through the engine. Finding a write that never worked is what this test was for. |
| T5 | Board: Dashboard DAG (`integration_test/dashboard_face_test.dart`) | **green (3/3, Windows)** | `loadRun` returned null unconditionally, so the face drew "No run yet" over every board the engine holds a pipeline snapshot for. It now reads `cyan_pipeline_status` — the Dashboard IS that snapshot seen from the run side. One DAG node per compiled step, in snapshot order, each in the lane its executor puts it in (`manual` or a review hold ⇒ human). `needsLens` draws as awaiting-approval, not failed: a park is the run waiting, not the run broken. |
| T6 | Board: Notes (`integration_test/notes_face_test.dart`) | **read green (3/3) · write BLOCKED** | `loadNotes` returned an empty document for every board; it now reads the board's markdown cells exactly as SwiftUI's `NotesEditorViewModel.load()` does (first markdown cell / empty-board template / joined). **The SAVE path is blocked and the test proves it:** `cyan_save_notebook_cell` runs every kind through `workflow::coerce_authoring_cell_type`, and ROUND8 §W1 made `step` the ONLY authorable kind — `markdown` is on `LEGACY_AUTHORING_KINDS` and collapses into it. So a saved notes document is stored as a workflow step and vanishes from the filter the editor reads by, and a board authored through this engine has no markdown cells at all. See the blocked note below. |
| T7 | Ops console — Runs (`integration_test/ops_runs_face_test.dart`) | **green (3/3, Windows)** | `loadOpsRuns` returned `[]`, so the console showed four empty lanes over ten compiled pipelines. There is no tenant-wide runs verb, so the feed is ASSEMBLED — every board asked for its `cyan_pipeline_status`. A board with no pipeline gets no card (not an empty one in Queued). The lane is the engine's own derived run state, mapped not re-derived; nothing is ever put in **Stuck**, because the engine has no such state. Cost fields stay zero — see the Ops Cost block below. |
| T8 | Board: Chat (`integration_test/chat_face_test.dart`) | **green (4/4, Windows)** | `loadChat` returned `[]`. No snapshot verb exists: `cyan_load_chat_history` replays the transcript as `ChatSent` frames, so the read is a replay drained back in — send through the engine, read it back, board-scoped, ordered by the engine's stamp. |

### Blocked, with the reason — checked against the engine's export table, not assumed
| # | screen | why it is blocked | what would unblock it |
|---|---|---|---|
| 5 | Notes — **write** (read is green) | `cyan_save_notebook_cell` coerces EVERY authored kind to `step` (`workflow::coerce_authoring_cell_type`; `markdown` is on `LEGACY_AUTHORING_KINDS`). A saved notes document is stored as a workflow step and vanishes from the markdown filter the editor reads by — and a board authored through this engine has no markdown cells at all, so the reference's reader is a legacy reader. | An engine notes-document kind, **or** a decision to move the face onto the uncoerced `cyan_note_*` ledger — which is SwiftUI's OTHER notes surface (`BoardNotesLedgerView`). That is a product call, not a port call. `notes_face_test.dart`'s third test goes red the moment the coercion stops. |
| 7 | Ops console — Cost | **No verb.** The 157-verb export table has nothing for cost, metering or billing; per-step billing lives behind the lens meter, which this build does not bind. `cyan_pipeline_status` carries only a run total. | An engine verb exposing the asset-minute meter. Engine work ⇒ the Mac session. |
| 8 | Ops console — Efficiency | **No verb.** Nothing in the export table reports gate-p95, failure rates, cache hits or retry burden. | Same as Cost. |
| 9 | Marketplace | **No verb.** The engine exposes `cyan_plugin_catalog` (what is INSTALLED on this device — already wired through `pluginCatalog`) and `cyan_install_plugin_bundle`. There is no storefront/registry read at this baseline. | An engine catalog verb, or a decision that the Marketplace lists installed bundles only. |
| 10 | Lens (nudges / asks / decisions) | **No verb.** The lens surface here is `cyan_parse_lens_command` + `cyan_poll_ai_insights`; nothing reports nudges, asks or decisions. `loadLensIntelligence` returns `connected: false`, which is the honest reading — this build binds no lens. | An engine lens-intelligence verb, plus a bound lens service. |

Also unfixable from this repo, recorded so nobody re-derives it: **the board card's
"N steps" reads 0.** `cyan_get_all_boards` hardcodes `element_count` to 0 and no verb counts
a board's cells without loading all of them; the wall will not load every cell of every
board to caption a card.

**FFI ARITY DRIFT — found and fixed (7 verbs), now guarded.** The symbol drift test asks
"does the engine export this NAME"; a PE export table cannot say what arguments it takes.
Dart FFI resolves by name and trusts the declared signature completely, and the C ABI lets
a caller push too few arguments, so seven verbs were called with the wrong shape:
`cyan_save_notebook_cell` / `cyan_delete_notebook_cell` / `cyan_save_whiteboard_element` /
`cyan_delete_whiteboard_element` (board id pushed in front of the payload the engine
actually wants — **every authored step save silently failed**), `cyan_get_boards_metadata`
(sent a JSON array where the engine wants a scope kind + id), `cyan_get_top_boards` (passed
the limit into a `*const c_char` slot — an integer dereferenced as a pointer),
`cyan_send_direct_chat` (two of four arguments, and a bool read out of a void function).
Plus `cyan_upload_file_to_group`/`_to_workspace`, whose pointers were the wrong way round
AND whose void return was being dereferenced and freed.
New `test/engine_arity_drift_test.dart` reads cyan-backend's own `pub extern "C" fn`
signatures and compares parameter counts + void-ness against the binder's typedefs. It
skips loudly when the engine source is not checked out beside this repo. It does NOT
compare parameter order or types — the swapped upload pair proves a count can match while
the call is still wrong.

**Engine facts this port had to learn the hard way (do NOT relearn):**
- There is **no `cyan_get_groups` verb**. Group and workspace NAMES exist on the wire in
  exactly one place: the engine's tree dump, emitted as a `TreeLoaded` event in answer to
  the `Snapshot` command. `cyan_get_all_boards` gives ids + board metadata only;
  `cyan_get_workspaces_for_group` gives bare ids. Same single source SwiftUI's
  `FileTreeViewModel.loadFromSnapshot` reads.
- `TreeLoaded` is routed to BOTH the `file_tree` and `board_grid` buffers. `cyan_poll_events`
  **pops**, so two pumps on one buffer steal each other's frames. The legacy
  `FileTreeNotifier` owns `file_tree`; the seam reads `board_grid` (nothing else pumps it).
- **`cyan_seed_demo_if_empty` is an INERT no-op** in this engine — kept for ABI stability
  only ("R10FB §D: demo seeding has been REMOVED"). The verb that really seeds is
  **`cyan_seed_demo`**: a fixed, idempotent 3-group / 10-board set, each group provisioned
  with a `General` and a system `Plugins` workspace.
- `cyan_get_all_boards` carries no deploy flag — deploy state is its own row, read with
  `cyan_board_workflow_state` (one point read per board; the wall does that now, so the
  living-wall running pill is real).
- `cyan_get_all_boards` hardcodes `element_count` to **0** and no verb counts a board's
  cells without loading all of them, so `CyanBoard.stepCount` is the engine's silence.
  The card's "N steps" reads 0 for every board until the engine grows a count verb —
  **engine work, and engine work belongs to the Mac session.**

**Seam truth:** `CyanBackendFFI`'s loaders (`loadWorkflow`, `loadNotes`, `loadOpsRuns`,
`loadCostMeter`, `loadEfficiency`, `loadMarketplace`, `loadLensIntelligence`, `loadChat`…)
still return honest EMPTIES. That is the Tier-3 work: real hydration, one screen per commit,
each proved by an integration test where a seeded engine yields non-empty truth.

## Guardrails
Branch `feat/flutter-parity`; never main; commit per screen; UI-only; contract frozen
(additive only, noted here); golden diffs are truth ("looks close" ≠ pass); macOS Flutter
build kept green as the cheap CI canary. Plugin-foundation work (Frame.io) lives in OTHER
repos on `main` against the frozen tag — these two streams never collide.

## Digest log (newest first)
- **2026-08-06 (night, cyan-win) — Tier-2 went from "the engine loads" to "six faces read it", and found four real bugs on the way.** Ten commits on `feat/flutter-parity`, local only — nothing pushed.
  **Green:** all eight Tier-2 suites on Windows, **27 assertions** — `real_engine_test` 3, `engine_roundtrip_test` 2, `tree_hydration_test` 3, `workflow_face_test` 6, `dashboard_face_test` 3, `notes_face_test` 3, `ops_runs_face_test` 3, `chat_face_test` 4. Tier-1 **304/304** (302 + two new drift guards), `flutter analyze` 0 errors.
  **Rung 1 was a misdiagnosis, said so.** The reported "stale symbol list" at `real_engine_test.dart:66` was not stale — `dumpbin /EXPORTS` confirms all 155 listed verbs plus the 5 hardcoded ones resolve (the engine exports 157). The failure was `tearDownAll`: the engine parks `CyanSystem` in a process-lifetime `OnceCell` and exports no shutdown verb, so SQLite stays open and Windows will not unlink an open file. Cleanup now names what it tolerates instead of going red or swallowing.
  **Rung 2 needed no change at all** — the round trip passed on Windows unmodified. Worth recording: the Windows write path is real.
  **Screens hydrated (each one had been returning an honest empty that Tier-1 could never catch):** Boards wall + Explorer tree (the tree dump — there is NO `cyan_get_groups`, so group and workspace names exist in exactly one place on the wire), the living wall's deploy pill (`cyan_board_workflow_state`; the wall drew a dead grid over ten deployed boards), Workflow author (read AND write), Dashboard DAG (`cyan_pipeline_status`), Notes (read), Ops Runs (assembled per board), Chat (replay).
  **Four bugs found by writing the tests, not by looking for bugs:**
  1. **Eleven FFI signature mismatches**, seven of them arity. `cyan_save_notebook_cell` takes ONE argument and Flutter passed the board id first, so the engine parsed a board id as the cell JSON and refused it — **every step an operator ever authored was silently dropped**, the cache took the write and the UI reported success. `cyan_get_top_boards` handed the engine an integer to dereference as a string pointer; `cyan_send_direct_chat` was called with two of four arguments and its void return read as a bool; `cyan_upload_file_to_group`/`_to_workspace` had their pointers reversed AND their void return dereferenced then freed. All fixed, and `test/engine_arity_drift_test.dart` now reads cyan-backend's own `pub extern "C" fn` signatures and compares them to the binder's typedefs — the half of the linker a PE export table cannot provide.
  2. **A silent-success lie**: `saveNotebookCell`/`deleteNotebookCell` caught an FFI exception and returned TRUE "since we saved to cache". The cache is a read fallback, not a write.
  3. **The Tier-2 suites were writing the engine's blob store into the repository** (`DATA_DIR` is a OnceCell defaulting to `"."`, which under `flutter test` is the repo). One store had already been committed in 058a69e. Every suite now sets `cyan_set_data_dir(<temp>)` before booting; a full Tier-2 pass leaves the tree clean.
  4. **Chat double-counts its own messages** without a dedupe by engine id — a send emits a live frame AND the replay emits the stored row.
  **Blocked, with evidence (see the table above):** Notes WRITE (the engine coerces every authored cell to `step`), Ops Cost, Ops Efficiency, Marketplace and Lens intelligence — the last four have **no verb at all** in the 157-verb export table, so they are engine work, which belongs to the Mac session. None of them were faked.
  **Two corrections to the night's brief, both verified against the engine:** `cyan_seed_demo_if_empty` is an INERT no-op here ("R10FB §D: demo seeding has been REMOVED") — the verb that really seeds is `cyan_seed_demo` (3 groups / 10 boards, idempotent); and several seam methods the brief listed as empty (`loadWorkflow`, `pluginCatalog`, the pipeline spine) were already real.
  **For Rick:** the Notes-face question is a genuine product call — the frozen SwiftUI reference (`NotesEditorView`, markdown cells) and the shipped engine (only `step` is authorable) disagree, and SwiftUI has a second notes surface (`BoardNotesLedgerView`) on the uncoerced `cyan_note_*` ledger that the engine does support.
- 2026-06-30 — Row 11 (Chat) GREEN — **PARITY COMPLETE (rows 0–11 all ci-green)**: built `ParityChatView` (lib/widgets/parity/parity_chat_view.dart) — SwiftUI `ChatPanel`/`ChatMessageView` parity, driven only through the seam via `boardChatProvider` (seam `loadChat` + `ChatMessage` model were already present; Fake seeds a 4-message transcript). Matches the reference's clean "Claude-style" transcript (no avatars/bubbles): header (forum icon + board title + "Board chat" + green online pill), left-aligned messages each with a colored author (own = cyan / others = green) + faint timestamp + a markdown body via a small inline span builder (**bold** + `code` → monospaced orange), over a composer (Message… field + cyan Send). Added `test/chat_view_test.dart`: 2 widget tests (header + transcript with seeded authors/timestamp/composer, Send fires onSend) + golden `golden/chat_transcript.png`. Full Tier-1 suite green: **40 passing**, analyze 0 errors.
- 2026-06-30 — Row 10 (Lens AI) GREEN: built `ParityLensView` (lib/widgets/parity/parity_lens_view.dart) — SwiftUI `LensAIView` parity, driven only through the seam via `lensIntelligenceProvider` (seam `loadLensIntelligence` + `LensIntelligence`/`LensNudge`/`LensAsk`/`LensDecision` models were already present; Fake seeds connected + 2 nudges / 2 asks / 2 decisions). Header (auto-awesome + "Lens AI" + connection dot/status + refresh), a tinted "Intelligence — Nudges · Asks · Decisions" band that keeps the differentiator distinct from operational approvals, and a four-way tab control (Nudges orange w/ count badge / Asks cyan / Decisions green / Graph purple, each keyed `lens-tab-…`). Nudge cards: orange icon tile + title + age + detail + owning board + green "Resolve". Ask cards: question + asker→assignee · age · status pill; answered asks render the recorded answer + answerer, open asks get Answer/Dismiss. Decision cards: content + rationale + decider + age + agree/disagree/comment reaction counts. Graph tab is an honest native-surface placeholder. Added `test/lens_view_test.dart`: 4 widget tests (header+tabs+nudges render, Resolve fires onResolveNudge with n1, switch→Asks shows seeded ask+answer, switch→Decisions shows decision) + golden `golden/lens_ai.png`. Tier-1: 36 passing, analyze 0 errors.
- 2026-06-30 — Row 9 (Marketplace) GREEN: the blind `ParityMarketplace` (lib/widgets/parity/parity_marketplace.dart) compiled and rendered — its seam (`loadMarketplace`), `marketplaceProvider`, and `PluginCard`/`PluginCategory`/`PluginSideEffect` models were already in place; only two real layout bugs remained. Fixed: the trust/side-effect badge Row could overflow horizontally on long combos (untrusted + sends-out + rating) → wrapped the two badges in an `Expanded(Wrap)` with the rating pinned right; and the Featured horizontal aisle clipped its cards (fixed 246px height vs ~288px cards) → raised to 300px. Baselined `golden/marketplace.png`. `test/marketplace_test.dart` green (storefront header + Featured/All aisles + category band + trust/side-effect badges + "Use in a workflow" CTA fires). Tier-1: 32 passing, analyze 0 errors.
- 2026-06-30 — STEP 1 (rows 0–8 GREEN, first real compile): the blind P0 harness + rows 1–8 finally built on a real Flutter (3.27.1). Reconciled the interrupted git tree (cleared stale `.git/*.lock`, unstaged the phantom widget deletions). `flutter analyze` was red only from pre-existing DEAD legacy files (old chat panels, board_card/grid, workspace_screen duplicate, debug_screen/login_view, the `cyan_fix_batch/` scratch dir) — all unreachable from `main.dart` and unreferenced by any test; removed them → analyze clean (0 errors; warnings/infos remain, tolerated by the gate's `--no-fatal-*`). Fixed real layout bugs the blind widgets carried: RenderFlex overflows in the dashboard DAG step signals, ops-runs cards, and ops-efficiency insight cards (Flexible + ellipsis / Wrap). Hardened the test harness — `pumpParity` now resizes the actual test surface to the requested `size` (the centered SizedBox was being clamped to the 800×600 window, truncating lazily-built ListViews so off-screen rows never built); tall surfaces for the boards wall + ops-runs lanes. Ops-runs lane headers now carry `ValueKey('ops-lane-…')` (parity status badges legitimately reuse "Queued/Running/Done", exactly as the SwiftUI console disambiguates lanes by accessibilityIdentifier) and the stage strip shows only for in-flight/terminal runs. Baselined 8 golden PNGs. Full Tier-1 suite green: **29 passing**, analyze 0 errors. Marketplace (row 9) still WIP.
- 2026-06-29 — Row 8 (Ops console — Efficiency): added `ParityOpsEfficiency` (lib/widgets/parity/parity_ops_efficiency.dart) via `efficiencyProvider`, in the shared OpsScaffold (Efficiency face). SwiftUI `OperationsConsoleView` Efficiency face: scope header + five insight cards (Gate bottleneck yellow w/ p95-wait + step, Failure hotspot red w/ rate + top error, Step speed p95 orange w/ slowest step, Cache efficiency purple w/ min saved, Retry burden cyan w/ rate) and a per-step table (step | runs | gate-p95 | fail | top error | exec-p95 | cache | retry) with ms-humanized durations (≥1000ms → Xs) and per-column tints (zero values fall back to comment). Extended seam (+`loadEfficiency`); prod FFI returns a zeroed report; Fake seeds the rollup + 4 step rows. Added parity models `EfficiencyReport`/`StepEfficiency`. Added `test/ops_efficiency_test.dart`: 1 widget test (5 cards + 142.0s metric + per-step table) + golden `golden/ops_efficiency.png`. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 7 (Ops console — Cost): added `ParityOpsCost` (lib/widgets/parity/parity_ops_cost.dart) via `costMeterProvider`, wrapped in the shared OpsScaffold (Cost face selected). SwiftUI `OperationsConsoleView` Cost face: scope header ("Asset-minute meter — all boards (tenant)", yellow "awaiting lens meter" when !hasMeter), a five-stat headline of surface cards (billed-min cyan / billed $ green / retry-min orange / saved-min purple / runs foreground), the GPU=COGS footnote ("internal COGS (margin, not billed): X compute-min · Y gpu-sec"), and a per-workflow reconcile table (workflow | runs | assets | billed-min cyan | billed $ green | retry-min orange-if-positive). Extended seam (+`loadCostMeter`); prod FFI returns hasMeter:false zero meter; Fake seeds the 24.5/$12.30 meter + 3 workflow rows. Added parity models `CostMeter`/`WorkflowCost`. Added `test/ops_cost_test.dart`: 1 widget test (headline+footnote+table) + golden `golden/ops_cost.png`. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 6 (Ops console — Runs): added `ParityOpsRuns` (lib/widgets/parity/parity_ops_runs.dart) + shared `OpsScaffold` (lib/widgets/parity/parity_ops_scaffold.dart), driven only through the seam via `opsRunsProvider`. SwiftUI `OperationsConsoleView` Runs face: console header (grid icon + "Ops console" + Runs/Cost/Efficiency segmented control), runs split into 4 lanes (Queued muted / Running cyan / Action needed yellow [approval+stuck+failed] / Done green) each with a colored dot + count, and cinematic 16:9 run cards — gradient poster + film glyph, top-left status badge (Queued/Running/Approval/Stuck/Done/Failed colors), bottom-right stage label (in-flight) or duration timecode (terminal), an in-flight LinearProgressIndicator (currentStep/stepCount), a monospaced meta row (steps X/Y · cost $ · dur), and inline actions (failed → Retry orange outline; approval → Approve green filled + Reject red outline). Extended seam (+`loadOpsRuns`); prod FFI returns []; Fake seeds 6 runs across the lanes. Added parity models `OpsRun`/`RunStatus`(+needsAction). Added `test/ops_runs_test.dart`: 2 widget tests (lanes+cards render, Retry fires onRetry with the failed run) + golden `golden/ops_runs.png`. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 5 (Board: Notes): added `ParityNotesView` (lib/widgets/parity/parity_notes_view.dart) — SwiftUI `NotesEditorView` parity, driven only through the seam via `boardNotesProvider`. VSCode-style: toolbar (green doc icon + file name + type chevron, right-side green "Saved" dot + save icon), a 50px right-aligned monospaced line-number gutter, a surfaceLighter editor body rendering each line monospaced with light markdown coloring (# heading → cyan, list/numbered → green, > quote → comment, else foreground), and a status bar (Ln 1, Col 1 · N lines · N words · UTF-8). Extended seam (+`loadNotes`); prod FFI returns an empty notes.md (Tier-2 deferred); Fake seeds a deployment.md doc for b-eng-4. Added parity model `BoardNotes`. Added `test/notes_view_test.dart`: 1 widget test (toolbar/content/status render) + golden `golden/notes_editor.png`. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 4 (Board: Dashboard DAG + gated run): added `ParityDashboardView` (lib/widgets/parity/parity_dashboard_view.dart) — SwiftUI `DashboardView`/`PipelinePreviewView` parity, driven only through the seam via the existing `boardRunProvider` (no seam change needed — uses the row-1 `WorkflowRun`/`RunStep` models). Run header with title + computed status pill (Done green / Running cyan / Queued muted) + "X / Y steps complete"; horizontal DAG of 142x84 step boxes connected by arrows, each box carrying a dual signal — AI (machine) lane [queued/running/done/failed icon+color] and human (gate) lane [Awaiting you yellow / Approved green / Rejected red]; a yellow approval-gate panel per awaiting-approval step (human → "Complete" green filled; AI → "Approve" green + "Reject" red outline); a collapsed compact step list with status dots + AI/Human tag; and a "No run yet" empty state for boards without a run. Added `test/dashboard_view_test.dart`: 4 widget tests (header+DAG+list render, gate buttons, Complete fires onApprove with step s3, empty state) + golden `golden/dashboard_dag.png`. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 3 (Board: Workflow author): added `ParityWorkflowView` (lib/widgets/parity/parity_workflow_view.dart) — SwiftUI `WorkflowView` parity, driven only through the seam via `boardWorkflowProvider`. Toolbar (Review cyan / Run green / Deploy purple / Reset muted, disabled when no steps or locked), purple "Deployed & locked" banner for deployed boards, numbered-circle step cells with compiled inference chips (tool=cyan extension, bound inputs=green #, send-to=purple, gate chip yellow "Awaiting approval" / green "No approval needed"), orange ambiguity warning, empty state, and the @/#// composer with cyan "Add step". Extended `CyanBackend` seam (+`loadWorkflow`) — additive; prod FFI returns an honest empty `Workflow` (Tier-2 hydration deferred), Fake seeds a compiled+locked 4-step flow for b-eng-1, an uncompiled 3-step (one ambiguous) for b-eng-2. Added parity models `Workflow`/`WorkflowStep`/`StepGate`. Added `test/workflow_view_test.dart`: 4 widget tests (steps+chips render, Run fires, ambiguous warning, empty state) + golden `golden/workflow_author.png`. Commit 3848d43. NOTE: agent cannot run Flutter — CI is the first real signal. Human must push `feat/flutter-parity`.
- 2026-06-29 — Row 2 (Explorer / group tree): added `ParityExplorerTree` (lib/widgets/parity/parity_explorer_tree.dart) — SwiftUI `FileTreeView` parity, driven only through the `CyanBackend` seam via `groupsProvider` (no direct FFI). Group→Workspace→Board tree with expand/collapse chevrons, type-colored Monokai icons (group=group color, workspace=green, board=face color), level*20+8 indentation, "Files" header + cyan (+) button, live search filter (matches + ancestors), row selection tint, empty/no-match states. Tree seeds fully-expanded once for deterministic goldens. Added `test/explorer_tree_test.dart`: 4 widget tests (hierarchy renders, collapse hides children, board tap → onOpenBoard, search filters) + golden `golden/explorer_tree.png` (tagged `golden`). NOTE: agent cannot run Flutter — CI is the first real signal; unverified that it compiles. Human must push `feat/flutter-parity`.
- 2026-06-29 — P0 bootstrap: added the single `CyanBackend` seam (lib/ffi/cyan_backend.dart) with prod `CyanBackendFFI` (wraps existing CyanFFI, no FFI signature changes) + Tier-1 `FakeCyanBackend` (3 groups / 10 boards / 1 sample run); parity view models (parity_models.dart); Riverpod `cyanBackendProvider` + futures. Ported Boards living wall (row 1) as `ParityBoardsGrid` driven only through the seam (Monokai masonry cards + running pill). Added dev deps (golden_toolkit, integration_test); test harness + trivial gate test (replaced the stale counter `widget_test.dart`) + boards widget/golden tests; `dart_test.yaml` golden tag. Created `.github/workflows/flutter-parity.yml` (analyze + `flutter test --exclude-tags golden`, goldens baselined as artifact). NOTE: agent cannot run Flutter — CI is the first real signal; unverified that everything compiles. GIT BLOCKER: workspace FUSE mount forbids unlink, and a stale `.git/index.lock` + interrupted rebase on `main` could not be cleared from this environment, so the branch/commit/push could not be performed here — needs Rick to run the git steps on the host (see report).

---

# PHASE 2 — FULL PARITY vs the LIVING Mac app (Rick's mandate, 2026-08-07)

**The mandate:** EVERYTHING the iOS/Mac app has, Flutter has — exactly. The
2026-06-29 frozen baseline is RETIRED. The reference is `C:\cyan\cyan-iOS`
(synced main), per-screen, re-synced as the Mac app evolves.

## Decisions (taken 2026-08-07, so the port never stalls on them)

- **D1 Baseline**: target = cyan-iOS main as synced on this box. Each new row
  names its Swift reference file. When the Mac app changes, the row reopens.
- **D2 Notes face**: the LEDGER system is the target (`BoardNotesLedgerView` +
  `NotesStructuringView` + today's `NotesEditorView`) — the engine's
  `cyan_note_*` verbs support it. The old markdown-cell-only reference is
  retired; the "engine coerces authored cells to step" block is VOID.
- **D3 Ops console / Marketplace / Lens faces**: these are LENS-HTTP-backed on
  the Mac (`Models/LensConsole.swift` — GET /api/v1/runs etc.), NOT FFI. Port
  = a Dart `LensApi` client seam (with fake) mirroring that file: same
  endpoints, bearer token from config (CYAN_LENS_URL + token). No engine
  verbs needed. The four "blocked: no verb" rows reopen under this lane.
- **D4 Two seams stay two seams**: `CyanBackend` (FFI) + `LensApi` (HTTP),
  each with a Fake. No view talks to either directly — providers only.
- **D5 Process unchanged**: one screen per commit, integration test per
  hydrated face, drift + arity guards are the gate, goldens platform-skipped.

## Phase-2 screen backlog (vs today's 47 Swift views; value order)

| # | screen | Swift reference | lane |
|---|---|---|---|
| 13 | Review player (+ scrubber, approve/comment) | ReviewPlayerView, ScrubberView | FFI |
| 14 | Video face | VideoPlayerFace | FFI |
| 15 | Notes ledger face (typed notes, structuring) | BoardNotesLedgerView, NotesStructuringView | FFI |
| 16 | Notes editor (today's) | NotesEditorView | FFI |
| 17 | Sources sheet | SourcesSheet | FFI |
| 18 | Template picker (clone + auto-install) | TemplatePickerSheet | FFI |
| 19 | Ops console — Runs/Cost/Efficiency vs LENS | OperationsConsoleView + LensConsole | LensApi |
| 20 | Marketplace (live browse + detail) | MarketplaceView, MarketplaceDetailView | LensApi |
| 21 | Lens AI face (nudges/asks/decisions live) | LensAIView | LensApi |
| 22 | Autopilot control + policy chips | WorkflowView (workflow.autopilot), DashboardView (Auto-approved chip) | FFI |
| 23 | Constitution editor | ConstitutionEditorView | FFI |
| 24 | Board files | BoardFilesView | FFI |
| 25 | Chat lane (anchors, board chat parity) | BoardChatLane, ChatPanel | FFI |
| 26 | Review loop / run audit | ReviewLoopView, RunAuditView | FFI |
| 27 | AE queue landing | AEQueueView | FFI |
| 28 | Forge | ForgeView | LensApi |
| 29 | Roster / group transfer / profile / settings / auth | RosterPanel, GroupTransferView, ProfileView, SettingsView, Auth/ | FFI |
| 30 | Cloud operations | CloudOperationsView | LensApi |
| 31 | Region composer / drawing overlay | RegionComposerView, RegionDrawingOverlay | FFI |
| 32 | Status bar (lens dot, tenant, sync) | StatusBar | both |

Rows 13–18 are the demo spine's visible surface — they go first.
