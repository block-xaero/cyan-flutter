// engine_unavailable_test.dart
//
// The two behaviours that decide what a BROKEN build does. Everything else in
// the suite asserts the app works; this file asserts that when it can't, it says
// so instead of pretending.
//
// The failure being guarded against is specific and it already happened: the
// macOS app shipped a six-month-old engine with 88 of 155 verbs. The binder
// degraded to no-ops, every screen rendered, every button responded, nothing was
// written, and 296 green widget tests said it was fine — because they drive
// FakeCyanBackend. Nothing on screen said a word.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/screens/engine_unavailable_screen.dart';

void main() {
  group('engine unavailable', () {
    // ── behaviour: a release build refuses to start when the engine cannot be
    //    resolved ───────────────────────────────────────────────────────────
    //
    // "Refuses to start" means the app never presents its normal surface. It is
    // a screen and not a hard exit on purpose: a process that dies at launch
    // explains nothing, and on Windows it dies before there is a console to read
    // it in. The refusal has to be visible to whoever is holding the build.
    testWidgets('a release build refuses to start when the engine cannot be resolved',
        (tester) async {
      await tester.pumpWidget(const EngineUnavailableApp(
        reason: 'the engine library could not be opened: dlopen failed',
        triedPaths: ['/Applications/Cyan.app/Contents/Frameworks/libcyan_core.dylib'],
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('engine_unavailable_title')), findsOneWidget);
      expect(find.text('Cyan cannot start'), findsOneWidget);

      // The screen must say WHY it stopped, in the terms that matter to the
      // person reading it: not "an error occurred" but "nothing would be saved".
      expect(
        find.textContaining('nothing would be saved'),
        findsOneWidget,
        reason: 'the refusal must explain the consequence, or it reads as a '
            'transient glitch worth clicking past',
      );
    });

    // ── behaviour: the engine resolver names the exact paths it tried when it
    //    fails ──────────────────────────────────────────────────────────────
    //
    // "Could not load the engine" is unactionable. The list of paths, in order,
    // is the whole diagnostic — it distinguishes "the build phase never ran"
    // from "it ran and put the file somewhere else".
    testWidgets('the engine resolver names the exact paths it tried when it fails',
        (tester) async {
      const tried = [
        '/Applications/Cyan.app/Contents/Frameworks/libcyan_core.dylib',
        'libcyan_core.dylib',
        '/usr/local/lib/libcyan_core.dylib',
      ];
      await tester.pumpWidget(const EngineUnavailableApp(
        reason: 'the library opened but a required symbol is missing: cyan_init',
        triedPaths: tried,
      ));
      await tester.pumpAndSettle();

      for (final p in tried) {
        expect(find.text(p), findsOneWidget,
            reason: 'the resolver tried $p and did not say so — whoever is '
                'fixing this cannot tell where the engine was expected');
      }

      // The reason itself must survive to the screen, not be flattened into a
      // generic message that loses which symbol failed.
      expect(find.byKey(const Key('engine_unavailable_reason')), findsOneWidget);
      expect(find.textContaining('cyan_init'), findsOneWidget);
    });

    // A resolver with no candidates at all is a distinct fault — a platform the
    // resolver has no plan for — and must not render as an empty gap that reads
    // like "it looked nowhere and that was fine".
    testWidgets('a platform with no candidate paths says so explicitly',
        (tester) async {
      await tester.pumpWidget(const EngineUnavailableApp(
        reason: 'no engine plan for this platform',
        triedPaths: [],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('No candidate paths'), findsOneWidget);
    });
  });
}
