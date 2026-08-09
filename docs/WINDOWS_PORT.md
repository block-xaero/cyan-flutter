# The Windows port — what differs from the Mac, and why

Living document for `cyan_flutter` on **cyan-win**. Everything here is a place
where Windows genuinely diverges from `cyan-iOS` (the macOS SwiftUI reference,
canonical at `main @ 7b60d27`) or from the Mac's own build. If a section stops
being true, fix it here in the same commit that changes the behaviour.

Intended to be folded into / linked from `cyan-docs`; this repo is the Windows
session's only write surface, so it is authored here and mirrored there by the
Mac session. See `C:\cyan\COORD.md`.

---

## 1. The mount edge — the port's defining bug

For two shifts every parity face was **dead code at runtime**. `lib/main.dart`
mounted the pre-parity `WorkspaceScreen`, and nothing outside
`lib/widgets/parity/` imported anything from `lib/widgets/parity/`:

```
grep -rn "widgets/parity" lib/ | grep -v "^lib/widgets/parity/"   # zero hits
```

436 Tier-1 assertions and 15 Tier-2 suites were green over screens no operator
could open, because **runtime reachability was never a tracker row**.

It is one now. `test/app_root_test.dart` carries a repo oracle, read off disk,
that fails if app code stops importing the parity shell. When adding a face, the
row is not done until a running user can reach it.

## 2. The video surface — the biggest platform divergence

`video_player` **has no Windows implementation**. Its pub cache carries
`video_player_android`, `_avfoundation`, `_web` and nothing else, so
`VideoPlayerController.file()` throws on Windows.

| | macOS | Windows / Linux |
|---|---|---|
| surface | `VideoPlayerReviewSurface` (AVFoundation) | `MediaKitReviewSurface` (libmpv) |
| chosen by | `reviewVideoSurfaceFactoryProvider`, on `defaultTargetPlatform` | same |
| ProRes / DNx | native | via ffmpeg |
| exact seek | zero-tolerance AVFoundation seek | `hr-seek=yes`, `hr-seek-framedrop=no` |

**Media Foundation cannot open ProRes**, which is why `video_player_win` — the
drop-in that needs no new code — was rejected: it would have played proxies and
failed on the masters the review station exists for. BRAW is out of scope
entirely (Blackmagic SDK only); the surface sees conform outputs.

`libmpv-2.dll` (~28 MB) ships in the Release bundle. Versions are **pinned**, not
caret-ranged: a decoder that silently changed seek behaviour would break frame
accuracy without failing a test.

## 3. Frame accuracy — the rule

**Seek to the CENTRE of a frame; read back with FLOOR.** The two must change
together.

`frameToPosition` / `positionToFrame` / `durationToFrameCount` in
`lib/services/review_video_surface.dart` are pure and shared by both surfaces, so
the property is proved once without a decoder — `test/frame_accuracy_test.dart`,
nine rates including all three NTSC pulldowns.

Aiming at the frame *boundary* (what the port did originally, on both platforms)
asks the decoder for the instant where frame N−1 ends and N begins; which frame
comes back is then decided by float rounding and the decoder's tie-breaking.
Centre-aiming buys half a frame of tolerance either way.

**Cutting timeshifts, and it is handled**: `ConformFrameMap`
(`review_player_controller.dart`) is decoded from the engine's `conform_map` op
and maps master-frame anchors to the conformed proxy. Markers draw at
`displayFrameForMaster(e.tcIn)`; capture maps back with `masterFrameForDisplay`.
A master frame the cut removed lands on the first surviving proxy frame after
it. The map degrades to identity when an older cut is on screen.

## 4. Keyboard — accelerators are NOT Command

Swift binds ⌘1..⌘4. Carrying `meta: true` across literally put them on the
**Windows key**, which the shell partly owns (Win+1..9 drives the taskbar). The
board face chords now follow `defaultTargetPlatform`; the test presses the
platform's accelerator and asserts the *other* platform's modifier does nothing.

Any new shortcut must do the same. Grep for `_kAcceleratorIsMeta`.

## 5. Assets

`pubspec.yaml` had **no `assets:` key at all**, so no Flutter asset in this
project could load — which is why the login drew a placeholder hexagon while the
real brand mark sat unused in the repo. `assets/icons/app_icon.png` is
byte-identical to cyan-iOS's `CyanBrandMark.imageset/cyan-wordmark.png`.

`assets/plugins/cyan-media.cyanplugin` is the default plugin every group is
provisioned with, offline (`lib/models/default_plugins.dart`). **Mac-owned**: do
not hand-edit, request a restage on COORD.md.

## 6. Box facts that cost real time

- **Display is at 225% scaling** (window DPI 216; a 1280×720 logical window is
  2880×1620 physical). Screenshot code that is not per-monitor-DPI-aware samples
  a virtualised region and makes a correctly centred layout look badly offset.
  Use `SetProcessDpiAwarenessContext(-4)` before `CopyFromScreen`, and
  `GetWindowRect` for the true rect.
- **Developer Mode must stay ON.** Without it `flutter pub get` cannot create
  plugin symlinks and fails for *any* plugin, not just new ones — the project
  only appears to work because `.dart_tool` was already populated. Key:
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense = 1`.
- **Never edit source with PowerShell `Set-Content`.** It reads a UTF-8 file as
  ANSI and rewrites it double-encoded, silently mojibaking every em-dash and
  box-drawing character. Tests cannot catch it when only comments are hit.
- A **stale `cyan_flutter.exe` blocks the build** — cmake's INSTALL step cannot
  overwrite `runner/Release`. If it was launched from another logon context
  (e.g. the Mac over ssh) even `taskkill /F` returns access denied.
- `windows\Libraries\cyan_backend.dll` **goes stale silently**. Mac-owned;
  request a restage rather than running cargo (mechanically fenced).

## 7. The gate

`flutter analyze` 0 errors (warnings/infos tolerated) → `flutter test` →
golden if visual → Tier-2 `flutter test integration_test/<file> -d windows`,
**one suite per invocation** (the engine parks `CyanSystem` in a process-lifetime
`OnceCell`). Never weaken a test. Goldens are platform-specific and skip loudly
here; the Mac re-baselines after a deliberate visual change.
