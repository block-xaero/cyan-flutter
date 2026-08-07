// test/notes_ledger_test.dart
//
// PARITY face `notes_face` — the board NOTES LEDGER (Swift:
// BoardNotesLedgerView + NotesLedgerViewModel), mounted as the right column of
// the Notes face. Tier-1: every assertion is driven through the `CyanBackend`
// seam (FakeCyanBackend), no dylib.
//
// The four behaviours in scripts/parity_faces/notes_face.txt:
//   • a note records its author and timestamp
//   • editing a note is last write wins
//   • notes survive a backend reload
//   • deleting a note removes it from the ledger

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/providers/notes_ledger_provider.dart';
import 'package:cyan_flutter/widgets/parity/parity_notes_ledger.dart';
import 'package:cyan_flutter/widgets/parity/parity_notes_view.dart';

import 'support/parity_test_harness.dart';

/// The Notes face wide enough that the editor and the ledger column both lay
/// out — the ledger is a column OF the face, not a screen of its own.
const Size _face = Size(1000, 800);

/// A board the fake seeds a real ledger on: two house rules and one editor note
/// from another peer (so authorship is not all "You").
const String _board = 'b-eng-1';
const String _ravisNote =
    'Conformed the offline against the EDL; two shots need a retime.';

/// `yyyy-MM-dd HH:mm` in local time — written out here rather than borrowed
/// from the widget's formatter, so the assertion is independent of it.
String _stampLabel(int epochSeconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

void main() {
  testWidgets('a note records its author and timestamp', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    // The ledger renders the board's recorded notes, grouped.
    expect(find.byType(ParityNotesLedger), findsOneWidget);
    expect(find.text('Board ledger'), findsOneWidget);
    expect(find.text(_ravisNote), findsOneWidget);
    expect(find.text('HOUSE RULES'), findsOneWidget);
    expect(find.text('NOTES'), findsOneWidget);

    final seeded = await backend.noteList(_board);
    final ravi = seeded.firstWhere((n) => n.id == 'n-note-eng-1');

    // AUTHOR — the resolved name and the craft role the engine stamped at
    // authoring time. Never the raw node id.
    expect(ravi.authorId, 'node-ravi-91de');
    // Scoped to THIS note's row: the same teammate authors more than one note
    // on the board, and asserting a bare text match would only be testing that
    // the fixture happens to have one of them.
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('notes-ledger-author-n-note-eng-1')))
            .data,
        'Ravi Shah · editor');
    expect(find.textContaining(ravi.authorId), findsNothing);
    // This device's own notes read "You" rather than its node id.
    expect(find.text('You · producer'), findsNWidgets(2));

    // TIMESTAMP — the row carries the note's own edit time out of the ledger.
    expect(ravi.updatedAt, greaterThan(0));
    expect(find.text(_stampLabel(ravi.updatedAt)), findsOneWidget);

    // A note authored HERE is stamped by the engine too — both the author and
    // the time come back off the ledger, not from the draft that was typed.
    await tester.enterText(
        find.byKey(const ValueKey('notes-ledger-field')), 'Locked reel 3.');
    await tester.tap(find.byKey(const ValueKey('notes-ledger-add')));
    await tester.pumpAndSettle();

    final mine = (await backend.noteList(_board))
        .firstWhere((n) => n.text == 'Locked reel 3.');
    expect(mine.authorId, isNotEmpty);
    expect(mine.createdAt, greaterThan(0));
    expect(mine.updatedAt, greaterThan(0));
    expect(find.text(_stampLabel(mine.updatedAt)), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('editing a note is last write wins', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    final before = (await backend.noteList(_board))
        .firstWhere((n) => n.id == 'n-note-eng-1');

    // Edit the note in place through the row's own editor.
    await tester
        .tap(find.byKey(const ValueKey('notes-ledger-edit-n-note-eng-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('notes-ledger-edit-field-n-note-eng-1')),
      'Conform landed; the two retimes are approved.',
    );
    await tester
        .tap(find.byKey(const ValueKey('notes-ledger-edit-save-n-note-eng-1')));
    await tester.pumpAndSettle();

    // The LATER write is the one that stands — one note, not two, and the
    // earlier text is gone from both the ledger and the screen.
    final after = (await backend.noteList(_board))
        .where((n) => n.id == 'n-note-eng-1')
        .toList();
    expect(after, hasLength(1));
    expect(after.single.text, 'Conform landed; the two retimes are approved.');
    expect(after.single.updatedAt, greaterThan(before.updatedAt));
    // The edit keeps the note's ORIGINAL authorship and creation time.
    expect(after.single.authorId, before.authorId);
    expect(after.single.createdAt, before.createdAt);

    expect(find.text('Conform landed; the two retimes are approved.'),
        findsOneWidget);
    expect(find.text(_ravisNote), findsNothing);

    // …and the losing side of the rule: a write whose clock is BEHIND the
    // note's current edit time is stale. It loses and never reaches the engine.
    final ledger = NotesLedgerController(backend: backend, boardId: _board);
    addTearDown(ledger.dispose);
    await ledger.load();

    final current = ledger.state.byId('n-note-eng-1')!;
    final stale = await ledger.editNote(
      'n-note-eng-1',
      'a stale peer overwrote this',
      now: current.updatedAt - 60,
    );
    expect(stale, isFalse);
    expect(
      (await backend.noteList(_board)).firstWhere((n) => n.id == current.id).text,
      'Conform landed; the two retimes are approved.',
    );

    // A write at or after that edit time wins.
    final fresh = await ledger.editNote(
      'n-note-eng-1',
      'Retimes delivered.',
      now: current.updatedAt + 60,
    );
    expect(fresh, isTrue);
    expect(
      (await backend.noteList(_board)).firstWhere((n) => n.id == current.id).text,
      'Retimes delivered.',
    );
  });

  testWidgets('notes survive a backend reload', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    await tester.enterText(find.byKey(const ValueKey('notes-ledger-field')),
        'Deliver the DCP by Friday.');
    await tester.tap(find.byKey(const ValueKey('notes-ledger-add')));
    await tester.pumpAndSettle();
    expect(find.text('Deliver the DCP by Friday.'), findsOneWidget);

    // Tear the whole face down and mount it again against the SAME engine —
    // a fresh ProviderScope, a fresh ledger controller, a fresh read. Nothing
    // in the widget tree remembers the note; only the engine can.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(find.byType(ParityNotesLedger), findsNothing);

    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    expect(find.text('Deliver the DCP by Friday.'), findsOneWidget);
    // The seeded rows came back too — the reload is a re-read of the ledger,
    // not a replay of what this session happened to do.
    expect(find.text(_ravisNote), findsOneWidget);
    expect(
      (await backend.noteList(_board)).map((n) => n.text),
      contains('Deliver the DCP by Friday.'),
    );
  });

  testWidgets('deleting a note removes it from the ledger', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    expect(find.text(_ravisNote), findsOneWidget);
    expect((await backend.noteList(_board)).map((n) => n.id),
        contains('n-note-eng-1'));

    await tester
        .tap(find.byKey(const ValueKey('notes-ledger-delete-n-note-eng-1')));
    await tester.pumpAndSettle();

    // Gone from the ledger the engine keeps…
    expect((await backend.noteList(_board)).map((n) => n.id),
        isNot(contains('n-note-eng-1')));
    // …and off the face, which reads the ledger back rather than hiding a row.
    expect(find.text(_ravisNote), findsNothing);
    expect(find.byKey(const ValueKey('notes-ledger-row-n-note-eng-1')),
        findsNothing);
    // The rest of the ledger is untouched — a delete removes ONE note.
    expect(find.text('Nothing ships outside the device before the review gate.'),
        findsOneWidget);
  });

  // ── C7: what the note is ABOUT and where it CAME FROM ────────────────────

  testWidgets('a row shows its anchor and its from-chat provenance',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    final decision =
        (await backend.noteList(_board)).firstWhere((n) => n.kind == 'decision');
    expect(decision.anchorKind, 'step');
    expect(decision.anchorId, 'step-audio-conform');
    expect(decision.originRef, 'chat:msg-eng-42');

    // It files under DECISIONS, with its kind chip…
    expect(find.text('DECISIONS'), findsOneWidget);
    expect(find.text('decision'), findsOneWidget);
    // …the human anchor label, truncated the way the reference truncates it…
    expect(
        tester
            .widget<Text>(find
                .byKey(ValueKey('notes-ledger-anchor-${decision.id}')))
            .data,
        'on step step-a');
    // …and the glyph that says a human did not type this here.
    expect(find.byKey(ValueKey('notes-ledger-fromchat-${decision.id}')),
        findsOneWidget);
    expect(find.text('from chat'), findsOneWidget);

    // A note with no anchor draws NEITHER — no placeholder, no "unanchored".
    expect(find.byKey(const ValueKey('notes-ledger-anchor-n-note-eng-1')),
        findsNothing);
    expect(find.byKey(const ValueKey('notes-ledger-fromchat-n-note-eng-1')),
        findsNothing);
  });

  test('an anchor kind this build does not know renders no label at all', () {
    // The four the reference knows.
    expect(
        const CyanNote(id: 'a', anchorKind: 'step', anchorId: 'step-titles')
            .anchorLabel,
        'on step step-t');
    expect(
        const CyanNote(id: 'a', anchorKind: 'board', anchorId: 'b-1')
            .anchorLabel,
        'board');
    expect(
        const CyanNote(id: 'a', anchorKind: 'run', anchorId: 'r-9').anchorLabel,
        'run r-9');
    expect(
        const CyanNote(id: 'a', anchorKind: 'frame', anchorId: '1020')
            .anchorLabel,
        'frame 1020');
    // A kind from a newer engine: an honest blank, never a confident mislabel.
    expect(
        const CyanNote(id: 'a', anchorKind: 'shot', anchorId: 's-4').anchorLabel,
        isNull);
    // A HALF anchor is no anchor — the engine coerces it that way too.
    expect(const CyanNote(id: 'a', anchorKind: 'step').anchorLabel, isNull);
    expect(const CyanNote(id: 'a', anchorId: 'step-x').anchorLabel, isNull);
    // Provenance is only chat provenance when it says so.
    expect(
        const CyanNote(id: 'a', originRef: 'chat:m1').isPromotedFromChat, isTrue);
    expect(
        const CyanNote(id: 'a', originRef: 'email:m1').isPromotedFromChat,
        isFalse);
    expect(const CyanNote(id: 'a').isPromotedFromChat, isFalse);
  });

  test('an anchored write carries the anchor and the provenance through the '
      'seam', () async {
    final backend = FakeCyanBackend();
    final queued = await backend.notePutAnchored(
      _board,
      'Lock the grade before the DCP.',
      kind: 'decision',
      anchorKind: 'step',
      anchorId: 'step-titles',
      originRef: 'chat:msg-eng-99',
      authorRole: 'colorist',
    );
    expect(queued, isTrue);

    final written = (await backend.noteList(_board))
        .firstWhere((n) => n.text == 'Lock the grade before the DCP.');
    expect(written.kind, 'decision');
    expect(written.anchorKind, 'step');
    expect(written.anchorId, 'step-titles');
    expect(written.originRef, 'chat:msg-eng-99');
    expect(written.authorRole, 'colorist');
    expect(written.anchorLabel, 'on step step-t');
    expect(written.isPromotedFromChat, isTrue);

    // A HALF anchor is stored as NO anchor rather than a dangling one.
    await backend.notePutAnchored(_board, 'Half-anchored.',
        anchorKind: 'step');
    final half = (await backend.noteList(_board))
        .firstWhere((n) => n.text == 'Half-anchored.');
    expect(half.anchorKind, isNull);
    expect(half.anchorId, isNull);
  });

  testWidgets('Copy notes puts the ENGINE\'s markdown on the clipboard',
      (tester) async {
    final backend = FakeCyanBackend();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpParity(tester, const ParityNotesView(boardId: _board),
        backend: backend, size: _face);

    await tester.tap(find.byKey(const ValueKey('notes-ledger-copy')));
    await tester.pumpAndSettle();

    // It is the engine's own rendering, verbatim — not a re-render of the rows.
    expect(copied, isNotNull, reason: 'nothing reached the clipboard');
    expect(copied, await backend.exportNotesMarkdown(_board));
    expect(find.text('Copied'), findsOneWidget);

    // The receipt is a beat, not a state: the button goes back to offering the
    // copy rather than reading "Copied" forever.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Copy notes'), findsOneWidget);
  });
}
