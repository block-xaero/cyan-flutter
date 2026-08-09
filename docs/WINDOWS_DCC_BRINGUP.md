# Windows DCC bring-up — the same end-to-end spine the Mac drives

**Status: table stakes, not a stretch goal.** Windows has to actuate and sense every
plugin and show the result in the review player, the same way the Mac does — including
the AI LUT. Parity of the *faces* is not parity of the *product*: a board that renders
correctly but cannot drive Premiere, Resolve, Pro Tools and After Effects is a picture of
Cyan, not Cyan.

**Nothing in the fence ever blocked this.** The deny rules in `.claude/settings.local.json`
cover `Edit`/`Write` on the other repos (and `cargo`) so the two sessions cannot collide on
the engine. Running flights, driving plugins, and executing `flutter test` were always
allowed. The reason Windows has not done it yet is that the Mac session kept the flights
and scoped the Windows lane to UI — that was a scoping mistake, and this document corrects it.

Tick items here as they land, in the same commits that change behaviour. The Mac session
pulls this file and mirrors it into `cyan-docs`.

---

## Phase 0 — report the ground truth (do this first, it decides everything below)

Nothing here needs code. It tells the Mac session what to stage and which rungs are even
possible on your box.

- [ ] **Which DCC apps are actually installed?** For each of Premiere Pro, After Effects
      (we know 2026 is there), DaVinci Resolve, Pro Tools: installed yes/no, version, and
      whether it launches. A rung against an app you do not have is a skip, not a failure —
      but we need to know which is which.
- [ ] **Free disk space** on `C:` and whether a second volume exists. The media corpus
      subset below is ~515 MB; the full set is several GB.
- [ ] **Frame.io credentials.** The Mac reads `~/.frameio.env` fresh per plugin call
      (the engine refreshes tokens in-process, so a child that inherits launch env goes
      stale). Windows needs the equivalent at `C:\Users\ricky\.frameio.env`. **Do not ask
      the Mac session to copy it** — that is Rick's to place, and neither session should be
      moving credentials around. Report only whether the file exists.
- [ ] **Does `ffmpeg` resolve on PATH?** The colour engine shells out to it
      (`CYAN_FFMPEG` overrides). No ffmpeg, no graded picture.

## Phase 1 — the rig (Mac owes you most of this; say the word if anything is missing)

- [ ] `C:\cyan\cyan_backend.dll` is current. Mac restages it with every engine change —
      check the COORD note names a DLL newer than your last pull.
- [ ] Plugin bundles staged: `cyan-media`, `frameio`, `premiere-uxp`, `premiere-watcher`,
      `ae`, `davinci-resolve`, `protools` as `.cyanplugin` in
      `C:\cyan\cyan_flutter\assets\plugins\`, plus a writable `CYAN_PLUGINS_ROOT`.
      **Bundle shape matters:** POSIX tar with a single top-level directory named for the
      plugin id. A canonical-signing blob is not a bundle and unpacks to nothing.
- [ ] Media corpus subset at your `CYAN_MEDIA_ROOT`. Ask Mac to push
      `SET_A_2398_prores422` (376 MB), `SET_E_ccby_24p_mixed_res` (138 MB) and
      `SET_F_review_proxy.mp4` (1 MB) — enough for the Wes and 90s boards.
- [ ] `integration_test/flight_harness.dart` resolves Windows paths. It is platform-aware
      already; the thing to check is that `plugsmoke.py` and the per-call credential read
      work with Windows path separators and that the python it shells to is the right one.

## Phase 2 — actuation and sense, one plugin at a time

The pattern for every row: the plugin must **do** something real (actuation) and Cyan must
**notice** it (sense). Both halves, or the row is not done. Evidence means a dispatch
result on the step and a row on the ledger — not a green status.

- [ ] **cyan-media** — `probe` on a real SET; `separate_tracks` on a clip with audio
      (splits into audio and picture essences); `conform`. Evidence: derived files exist on
      disk AND appear as files on the board.
- [ ] **frameio** — `upload_file` puts a review proxy up; a comment typed in Frame.io comes
      back through `list_comments` and lands as a `source='frameio'` ledger note. This is
      the round trip that closes the producer window, so it is the highest-value row here.
- [ ] **premiere-uxp** — `add_markers` and `export_sequence` against a real project.
      Remember the panel binds `127.0.0.1` by doctrine, so this is seat-bound: it must run
      on the box with Premiere, which is the whole point of testing it on Windows.
- [ ] **premiere-watcher** — `scan_exports` senses an editor export you make by hand.
      Also make a *rejection* in Premiere and confirm it comes back as a rejected op rather
      than being silently dropped.
- [ ] **ae** — `apply_op op=set_text` writes a real title into the `CYAN_ENDCARD` comp and
      `op=render_comp` renders it. Two Mac-learned traps: DoScript needs the script's
      **contents**, not its path (passing the path makes AE execute the path string and
      throw "Expected: ;"), and the app name must match exactly (`Adobe After Effects 2026`).
- [ ] **davinci-resolve** — `apply_look` reports `"applied":true` with a cube path, and
      `capture_grade` brings a grade back. This is the AI-LUT rung.
- [ ] **protools** — `stage_turnover`, `inject_notes`, `parse_aaf`. Skip with a note if
      Pro Tools is not installed.

## Phase 3 — the review player shows the cumulative effect

This is the row Rick cares most about and the one a UI port is uniquely placed to prove.

- [ ] Player timecode in/out and region edits produce ledger ops.
- [ ] Edits accepted in Premiere, edits **rejected** in Premiere, and new agent edits all
      show correctly and *together* — the cumulative state, not the last write.
- [ ] Stage lineage is selectable: `review_versions` answers and the player lists v1..vHEAD.
- [ ] The colour stage appears **after** relink/conform, and the AI LUT is visible as its
      own stage.
- [ ] Cutting timeshifts stay correct across stages (`ConformFrameMap` is ported and
      applied — that part is already yours).

## Phase 4 — the full matrix, the way the Mac runs it

Four combinations, and they are genuinely different code paths:

- [ ] WITH notes × AUTOPILOT
- [ ] WITHOUT notes × AUTOPILOT
- [ ] WITH notes × HUMAN-GATED
- [ ] WITHOUT notes × HUMAN-GATED

Two things that will bite, both learned the hard way on the Mac:

**A `needs_human:` park is RELEASED, never approved.** When a plugin tool has local side
effects the gate parks the step (`failed` + `error` starting `needs_human:`). Calling the
ordinary approve verb on it stamps `human_approved` **and the tool never runs** — the walk
proceeds to a "delivered" master whose grade never happened, with every status green.
Retry is not a workaround either: it clears the carried approval so the step re-parks
forever. Use `CyanFFI.pipelineRelease(boardId, stepId, reviewer: '…')`. In the Dashboard,
a step whose error starts `needs_human:` gets a **Release** action — not Approve, not Retry.

**Approve as a named human.** The bare approve verb stamps `anonymous`. Pass the signed-in
user through `cyan_pipeline_approve_as` so gates read `supervisor:rick` rather than nothing.
On an autopilot board the same gates read `policy:dev-floor@v0[evidence]`, and that contrast
is the demo.

- [ ] Autopilot gates carry a policy stamp with its evidence in brackets.
- [ ] Human-gated boards carry named humans on every gate.
- [ ] The colour **op** on every board carries a person's name — autopilot may decide *that*
      the grade runs, only a human decides *what* it is. A colour op with a policy stamp is
      a bug, not a mode.

## Phase 5 — accumulation (the trap that cost the Mac a full day)

- [ ] Every finished board carries, as **files on the board**: its source clips, its endcard
      render, its `<look>.cube`, its `<look> — graded.mp4`, and its master.

A board shows `objects` rows. An asset-registry row is invisible to a board — the registry
being right proves nothing. Verify with:

```sql
SELECT name, source_peer FROM objects WHERE type='file' AND board_id = ?;
```

And when you add any artifact lane of your own, remember `set_class_location`'s `class` is
a **closed vocabulary** (`clip | sequence`). Anything else errors, and because these chains
are best-effort the board row vanishes with only a warning. Fingerprint: an asset row with
`class=NULL, location=NULL`.

---

## What Mac owns, so you never wait on the wrong thing

Engine changes, the DLL, plugin bundle authoring and restaging, goldens (macOS-only), and
`cyan-docs`. If a rung above needs an engine fix, say so in COORD and it will land — the
fence exists so we do not both edit the engine, not to stop you from needing it changed.
