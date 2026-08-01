// test/lens_surface_test.dart
//
// The LENS SURFACE oracle — the lens as the macOS app ships it: an on-demand
// ask, not an always-on dock. Every test drives `ParityLensSurface` through the
// `CyanBackend` seam (FakeCyanBackend):
//
//   • the lens is INVOKED — nothing of it is mounted, and nothing is read from
//     the engine, until someone asks; dismissing takes it away again
//   • an ask is a round-trip: a visible pending state, then the answer
//   • an ask that fails surfaces the refusal (and a retry) instead of parking
//     on the spinner forever
//
// Plus what the answer actually IS: the boards the engine knows and the signal
// the lens is holding, ranked — the shape of `LensSearchResult.results`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_lens_surface.dart';

import 'support/parity_test_harness.dart';

/// Records every seam verb the surface reaches for — a dock would have called
/// one on mount; the on-demand lens calls none until it is asked.
class _RecordingBackend extends FakeCyanBackend {
  final List<String> calls = [];

  @override
  Future<List<BoardWithContext>> loadAllBoards() {
    calls.add('loadAllBoards');
    return super.loadAllBoards();
  }

  @override
  Future<LensIntelligence> loadLensIntelligence() {
    calls.add('loadLensIntelligence');
    return super.loadLensIntelligence();
  }
}

/// Holds the read open so the PENDING state is observable, exactly as a real
/// engine round-trip holds it.
class _GatedBackend extends FakeCyanBackend {
  final Completer<void> gate = Completer<void>();

  @override
  Future<List<BoardWithContext>> loadAllBoards() async {
    await gate.future;
    return super.loadAllBoards();
  }
}

/// The engine is unreachable — the seam throws rather than answering.
class _FailingBackend extends FakeCyanBackend {
  int attempts = 0;

  @override
  Future<List<BoardWithContext>> loadAllBoards() async {
    attempts++;
    throw StateError('lens engine unreachable');
  }
}

/// The lens answered, but it is not connected to its graph.
class _OfflineLensBackend extends FakeCyanBackend {
  @override
  Future<LensIntelligence> loadLensIntelligence() async =>
      const LensIntelligence(connected: false);
}

/// The host content the lens is invoked OVER.
Widget _workspace() => const ColoredBox(
      color: Color(0xFF272822),
      child: Center(child: Text('workspace content')),
    );

/// The expanded reporter only prints a suite's test name when that test emits
/// output — under a parallel run the others are elided. The acceptance oracle
/// reads those names, so each behaviour states itself once it holds.
void verified(String behaviour) => debugPrint('lens surface — $behaviour');

/// Open the lens and ask [question], WITHOUT settling: a pending ask keeps a
/// spinner on screen, which `pumpAndSettle` would never settle.
Future<void> _ask(WidgetTester tester, String question) async {
  await tester.tap(find.byKey(const ValueKey('lens-invoke')));
  await tester.pump();
  await tester.enterText(find.byKey(const ValueKey('lens-input')), question);
  await tester.tap(find.byKey(const ValueKey('lens-send')));
  await tester.pump();
}

void main() {
  testWidgets('lens is invoked on demand and not a persistent dock',
      (tester) async {
    final backend = _RecordingBackend();
    await pumpParity(
      tester,
      ParityLensSurface(child: _workspace()),
      backend: backend,
    );

    // Nothing of the lens is mounted, and the engine has not been touched.
    expect(find.byType(LensAskPanel), findsNothing);
    expect(find.byKey(const ValueKey('lens-input')), findsNothing);
    expect(backend.calls, isEmpty);
    // Only the invoke affordance sits over the content.
    expect(find.byKey(const ValueKey('lens-invoke')), findsOneWidget);
    expect(find.text('workspace content'), findsOneWidget);

    // Invoked — the panel mounts, and STILL nothing has been read: the lens
    // reads when it is asked, not when it appears.
    await tester.tap(find.byKey(const ValueKey('lens-invoke')));
    await tester.pumpAndSettle();
    expect(find.byType(LensAskPanel), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-input')), findsOneWidget);
    expect(backend.calls, isEmpty);

    // Dismissed — gone again, and the workspace underneath is untouched.
    await tester.tap(find.byKey(const ValueKey('lens-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byType(LensAskPanel), findsNothing);
    expect(find.byKey(const ValueKey('lens-invoke')), findsOneWidget);
    expect(find.text('workspace content'), findsOneWidget);

    verified('invoked on demand, never a persistent dock');
  });

  testWidgets('asking lens shows a pending state then an answer',
      (tester) async {
    final backend = _GatedBackend();
    await pumpParity(
      tester,
      ParityLensSurface(child: _workspace()),
      backend: backend,
    );

    await _ask(tester, 'render approval');

    // In flight: the question is on screen with a pending state, no answer.
    expect(find.text('render approval'), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-pending')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-answer')), findsNothing);

    // The engine answers.
    backend.gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('lens-pending')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('lens-answer')), findsOneWidget);
    expect(find.textContaining('matches for'), findsOneWidget);
    expect(find.text('Render + Review Pipeline'), findsOneWidget);

    verified('pending state, then the answer');
  });

  testWidgets('a lens failure surfaces an error rather than hanging',
      (tester) async {
    final backend = _FailingBackend();
    await pumpParity(
      tester,
      ParityLensSurface(child: _workspace()),
      backend: backend,
    );

    await _ask(tester, 'what is blocking the render');
    await tester.pumpAndSettle();

    // The refusal is on screen — verbatim — and the spinner is gone.
    expect(find.byKey(const ValueKey('lens-error')), findsOneWidget);
    expect(find.textContaining('lens engine unreachable'), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-pending')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('lens-answer')), findsNothing);

    // And the surface is still live: Retry re-asks rather than stranding it.
    expect(backend.attempts, 1);
    await tester.tap(find.byKey(const ValueKey('lens-retry')));
    await tester.pumpAndSettle();
    expect(backend.attempts, 2);
    expect(find.byKey(const ValueKey('lens-error')), findsOneWidget);

    verified('a failure surfaces an error, it never hangs');
  });

  testWidgets('an answer ranks boards beside the signal the lens holds',
      (tester) async {
    final backend = _RecordingBackend();
    await pumpParity(
      tester,
      ParityLensSurface(child: _workspace()),
      backend: backend,
    );

    await _ask(tester, 'what is happening with the render approval');
    await tester.pumpAndSettle();

    // The board the words name, with its group/workspace context...
    expect(find.text('Render + Review Pipeline'), findsOneWidget);
    expect(find.text('Engineering › Backend Services'), findsOneWidget);
    // ...and the nudge the lens is holding on it, typed as a nudge.
    expect(find.text('Producer approval is overdue'), findsOneWidget);
    expect(find.text('nudge'), findsWidgets);
    expect(find.text('board'), findsWidgets);

    // Answered off the seam, not off anything cached in the widget.
    expect(backend.calls, contains('loadAllBoards'));
    expect(backend.calls, contains('loadLensIntelligence'));
  });

  testWidgets('an ask that matches nothing says so instead of showing hits',
      (tester) async {
    await pumpParity(tester, ParityLensSurface(child: _workspace()));

    await _ask(tester, 'zzzqqq');
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches "zzzqqq"'), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-error')), findsNothing);
  });

  testWidgets('an offline lens refuses rather than answering thin',
      (tester) async {
    await pumpParity(
      tester,
      ParityLensSurface(child: _workspace()),
      backend: _OfflineLensBackend(),
    );

    await _ask(tester, 'render approval');
    await tester.pumpAndSettle();

    expect(find.textContaining('the lens is offline'), findsOneWidget);
    expect(find.byKey(const ValueKey('lens-answer')), findsNothing);
  });
}
