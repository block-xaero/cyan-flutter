// test/widget_test.dart
//
// Trivial gate-proving test (PARITY_TRACKER row 0). Renders a Monokai-themed
// widget against `FakeCyanBackend` and asserts the harness + theme + seed data
// all wire up. If this is green in CI, the Tier-1 gate is live.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/theme/monokai_theme.dart';

import 'support/parity_test_harness.dart';

void main() {
  test('FakeCyanBackend seeds 3 groups / 10 boards / a sample run', () async {
    final backend = FakeCyanBackend();
    await backend.initialize();
    expect(backend.isReady, isTrue);

    final groups = await backend.loadGroups();
    expect(groups.length, 3, reason: 'spec: 3 demo groups');

    final boards = await backend.loadAllBoards();
    expect(boards.length, 10, reason: 'spec: 10 demo boards');

    final run = await backend.loadRun('b-eng-1');
    expect(run, isNotNull, reason: 'spec: a sample run exists');
    expect(run!.steps.length, 4);
    // A gated human-approval step must exist (the Dashboard differentiator).
    expect(
      run.steps.any((s) =>
          s.kind == RunStepKind.human &&
          s.status == RunStepStatus.awaitingApproval),
      isTrue,
    );
  });

  testWidgets('trivial Monokai widget renders against the fake backend',
      (tester) async {
    await pumpParity(
      tester,
      Container(
        color: MonokaiTheme.background,
        alignment: Alignment.center,
        child: Text('Cyan', style: MonokaiTheme.displayLarge),
      ),
    );

    expect(find.text('Cyan'), findsOneWidget);

    // Theme is wired: the MaterialApp uses the Monokai scaffold background.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, MonokaiTheme.background);
  });
}
