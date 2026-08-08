# RESUME — cyan-win Flutter session, paused 2026-08-08 ~17:15Z

Rick paused the session to restart it. This is the context to reload. Read this
first, then `PARITY_AUDIT_2026-08-08.md` beside it.

## The objective, in Rick's words (this supersedes the screen-row framing)

> "on windows we should have parity with cyan-iOS. this means we should be able to
> run on UI end to end dcc based workflows, we should be able to understand what
> happens with+without notes, we should be able to auto install plugins from
> marketplace when we use templates to create workflows, we should be at par from UI
> in terms of signup and role based landing and claims within role. the backend WORKS
> only thing to adjust is how flutter behaves."

Four axes: **(1) drive the DCC spine from the UI · (2) with/without notes · (3)
template → marketplace auto-install · (4) signup + role landing + claims in role.**
`cyan-iOS` (the Mac app, misnamed) is the reference and is **READ ONLY**.
`cyan_flutter` is the entire write surface.

## THE FINDING — everything else is downstream of it

**The whole parity face tree is dead code at runtime.** `lib/main.dart` →
`_AppRoot` → `WorkspaceScreen`, and `lib/screens/workspace_screen.dart` imports only
the LEGACY pre-parity widgets (`icon_rail.dart`, `board_detail_view.dart`, the old
canvas/notebook/notes Jupyter faces). Nothing outside `lib/widgets/parity/` imports
anything from `lib/widgets/parity/`. Proof:

```
grep -rn "widgets/parity" lib/ | grep -v "^lib/widgets/parity/"   # zero hits
```

So all 34 parity faces — Workflow, Dashboard, Spine, Review player, Video face,
Sources, Marketplace, Template picker, Constitution editor, Settings, Ops console,
Lens — are reachable **only from `test/`**. Two shifts of Tier-1 and Tier-2 tests are
green against faces the operator has never been able to open. That is why the app
"has parity" on paper and cannot drive a single station of the spine in the hand.

This reframes the tracker: the rows were honest about the WIDGETS and silent about
the SHELL. The next session's first job is not another face — it is **mounting the
parity shell as the app** and threading its callbacks.

## Audit state

Five-axis adversarial audit, workflow run `wf_5b221b00-aee`. Four axes returned
before the pause; **the signup / role-landing / claims axis had not returned**, and
none of the skeptic verdicts had landed, so every finding below is UNVERIFIED —
treat as strong leads, re-verify before implementing.

Journal (results survive the session):
`C:\Users\ricky\.claude\projects\C--Users-ricky\40086c83-1d98-4c7c-8c78-1de08c996708\subagents\workflows\wf_5b221b00-aee\journal.jsonl`

Full findings with file-level evidence: **`PARITY_AUDIT_2026-08-08.md`**.

Blockers found, by axis:

- **DCC spine:** parity tree orphaned (above); ingest/Sources has no door in `lib/`;
  no `video` board face so review player + scrubber + AE graphics rail cannot open;
  delivered-master has no reachable trigger; Deploy button is `onTap: null`; the step
  `⋯` menu is a decoration; an `awaitingInput` park has no control so the run wedges.
- **Shell:** the live rail has no Market door and a "Coming soon" Lens door, three
  buttons are `onTap: () {}`; Settings is a SnackBar over an orphaned 838-line
  `ParitySettingsView`; the board cube offers Canvas/Notebook/Notes (Canvas is a face
  the Mac DELETED) and not Dashboard/Video; even `ParityHomeShell` default-constructs
  its faces so `onOpenBoard` is null; shortcuts are bound to Meta (Windows key) not
  Control; status bar's "Synced" is hardcoded.
- **Notes:** the structuring lane (freeform → typed proposals → confirm) does not
  exist; "Create workflow" from the ledger (/transpile) is not drawn; "Author workflow
  with Lens" (/generate) missing; `ParityConstitutionEditor` — the house-rules lever,
  i.e. the WITHOUT-notes path — is mounted by nothing; no path authors a decision /
  constitution / preference note; no per-step note-provenance badge, so the operator
  cannot tell whether a run took its args from notes or from the constitution.
- **Template → marketplace:** Marketplace unreachable (no Market door); template
  picker unreachable, so clone-time auto-install can never fire; `cyan-media` (the
  default plugin every macOS group gets free) is never provisioned on Windows; the
  clone path does zero plugin resolution; Install can't run inside the Marketplace
  face because no group id is threaded; "Use in a workflow" does nothing; the clone
  blocks the picker up to 90 s then reports "nothing landed", a claim it cannot make.

## Box / repo state at pause

- `cyan_flutter` on `feat/flutter-parity` at `07445c8`, **nothing committed this
  session**. Uncommitted: `lib/main.dart` (boot-trace, see below) + two new docs
  (`PARITY_AUDIT_2026-08-08.md`, this file).
- `flutter analyze` → **0 errors** (608 warnings/infos; the gate is
  `--no-fatal-warnings --no-fatal-infos`, unchanged).
- Tier-1 suite NOT re-run this session (held back to avoid `.dart_tool` collision
  with the audit agents). Last known 436/436.
- `windows\Libraries\cyan_backend.dll` is **current** — the Mac restaged it at
  backend `85887e3` with the full suite green (COORD 17:00Z).
- **Release build is blocked**: a running `cyan_flutter.exe` (PID 35408) holds
  `build\windows\x64\runner\Release\cyan_flutter.exe`, so cmake's INSTALL step fails
  with MSB3073. Close that process before `flutter build windows --release`.
- **AE is available again on this box** (COORD 16:20Z). `C:\cyan\ae_setup.py`
  re-proves the transport and builds the `CYAN_ENDCARD` comp; the W-flight AE legs can
  fly for real after that.

## The fence (mechanical now — do not test it)

`.claude/settings.local.json` in this repo denies Edit/Write on every sibling repo
(backend, iOS, lens, mcp, media, plugins, identity, iac, xaeroid, docs) and denies
`cargo` outright, enforced even in bypass mode. **`cyan_flutter` is the entire write
surface.** `C:\cyan\COORD.md` is the mailbox to the Mac session — write there when
you need the engine/lens side to act.

Earlier this session I rebuilt and restaged the DLL with `cargo` before that fence
existed. Disclosed on COORD; the Mac acked it as harmless (same commit) and has since
superseded it. Do not repeat it.

## The uncommitted `lib/main.dart` edit

Added an env-gated boot timeline: `_bootClock` / `_bootTrace` / `_bootMark()`, marks
at binding-ready, notebook-cache, python-env, model-registry, bindings-resolved,
runApp, and a post-frame `FIRST FRAME`. Costs one bool read per phase unless
`CYAN_BOOT_TRACE=1`. Analyze-clean, never measured — the release build blocker above
stopped it. **Keep or revert freely; it is not load-bearing.**

Why it exists: the "long white window" Rick reported is `main()` blocking the first
frame on `await CyanFFI.initializeCache()` plus a synchronous `dlopen` of the 40 MB
engine DLL before `runApp` is ever called. The fix is UI-side (present the splash
first, resolve the engine after, keep the degraded-build refusal intact — see the long
comment above `CyanBindings.instance` in `main.dart`, which is a real invariant and
must not be softened). This ranks BELOW the four axes.

## Suggested first moves on resume

1. Re-run or resume the audit to get the missing signup/role/claims axis and the
   skeptic verdicts: `Workflow({scriptPath: "C:\\Users\\ricky\\.claude\\projects\\C--Users-ricky\\40086c83-1d98-4c7c-8c78-1de08c996708\\workflows\\scripts\\cyan-flutter-parity-audit-wf_5b221b00-aee.js", resumeFromRunId: "wf_5b221b00-aee"})` — completed agents return cached.
2. Mount the parity shell as the app (`main.dart` → `ParityHomeShell`) and thread
   `onOpenBoard` and the face callbacks. Everything else is gated behind this.
3. Then: board cube gains Dashboard + Video faces; Market and Sources doors on the
   rail; constitution editor mounted; template picker reachable.
4. Gate per screen, unchanged: analyze 0 errors → Tier-1 → golden (platform-skipped
   here) → Tier-2 if it touches a seam → one commit per screen → tracker row updated.
   Never weaken a test. One Tier-2 suite per `flutter test` invocation (OnceCell).
