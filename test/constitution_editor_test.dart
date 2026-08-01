// test/constitution_editor_test.dart
//
// PARITY face `settings_identity` — the constitution editor. Tier-1: drives
// `ParityConstitutionEditor` through the `CyanBackend` seam (FakeCyanBackend)
// and asserts the merged chain it LOADS (markdown, hash, soft preferences,
// provenance, hard rules) and the rule it SAVES — written through the seam and
// then read back off the engine's own resolve.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/widgets/parity/parity_constitution_editor.dart';

import 'support/parity_test_harness.dart';

const Size _panel = Size(720, 1100);

void main() {
  testWidgets('the constitution editor loads and saves house rules',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityConstitutionEditor(boardId: 'b-eng-1'),
        backend: backend, size: _panel);

    // LOADS — the merged chain the runs steer by, plus its chain hash.
    expect(find.text('Effective constitution'), findsOneWidget);
    expect(
        find.text('Nothing ships outside the device before the review gate.'),
        findsWidgets);
    expect(find.byKey(const ValueKey('constitution-hash')), findsOneWidget);
    // The soft preference rows are kept APART from the constitution.
    expect(find.text('Cut proxies at 1080p; keep the masters untouched.'),
        findsWidgets);
    expect(find.text('1 contributing note(s)'), findsOneWidget);

    // SAVES — a board-scope constitution rule, through the seam.
    await tester.enterText(
      find.byKey(const ValueKey('constitution-rule-field')),
      'Deliver every master at 24 fps.',
    );
    await tester.tap(find.byKey(const ValueKey('constitution-add-rule')));
    await tester.pumpAndSettle();

    final saved =
        await backend.noteListScoped('b-eng-1', 'board', kind: 'constitution');
    expect(
        saved.map((n) => n.text), contains('Deliver every master at 24 fps.'));

    // …and it comes back onto the face out of the ENGINE's resolve, not from
    // the draft that was typed.
    expect(find.byKey(const ValueKey('constitution-saved')), findsOneWidget);
    expect(find.text('Deliver every master at 24 fps.'), findsWidgets);
    expect(find.text('2 contributing note(s)'), findsOneWidget);
  });

  testWidgets('the editor shows the hard rules the engine classified',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityConstitutionEditor(boardId: 'b-eng-1'),
        backend: backend, size: _panel);

    // A measured, modal rule is HARD — and it carries its text verbatim.
    await tester.enterText(
      find.byKey(const ValueKey('constitution-rule-field')),
      'Audio must land at -14 LUFS.',
    );
    await tester.tap(find.byKey(const ValueKey('constitution-add-rule')));
    await tester.pumpAndSettle();

    expect(find.text('Hard rules — a run may not trade these away'),
        findsOneWidget);
    expect(find.text('Audio must land at -14 LUFS.'), findsWidgets);

    final effective = await backend.constitutionEffective('b-eng-1');
    expect(effective.hard.map((r) => r.text),
        contains('Audio must land at -14 LUFS.'));
  });

  testWidgets('a group rule is inherited by every board of the group',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityConstitutionEditor(boardId: 'b-eng-1'),
        backend: backend, size: _panel);

    await tester.tap(find.byKey(const ValueKey('constitution-scope-group')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('constitution-rule-field')),
      'No cut leaves the group without a second pair of eyes.',
    );
    await tester.tap(find.byKey(const ValueKey('constitution-add-rule')));
    await tester.pumpAndSettle();

    // Anchored on the GROUP, so it merges into the chain of a SIBLING board
    // too — not just the one it was authored from.
    final sibling = await backend.constitutionResolved('b-eng-2');
    expect(sibling.markdown,
        contains('No cut leaves the group without a second pair of eyes.'));
    expect(find.text('No cut leaves the group without a second pair of eyes.'),
        findsWidgets);
  });

  testWidgets('a preference is saved apart from the constitution',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityConstitutionEditor(boardId: 'b-eng-1'),
        backend: backend, size: _panel);

    await tester
        .tap(find.byKey(const ValueKey('constitution-kind-preference')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('constitution-rule-field')),
      'Prefer warm grades on the reel openers.',
    );
    await tester.tap(find.byKey(const ValueKey('constitution-add-rule')));
    await tester.pumpAndSettle();

    final resolved = await backend.constitutionResolved('b-eng-1');
    expect(resolved.preferences,
        contains('Prefer warm grades on the reel openers.'));
    expect(resolved.markdown,
        isNot(contains('Prefer warm grades on the reel openers.')));
  });
}
