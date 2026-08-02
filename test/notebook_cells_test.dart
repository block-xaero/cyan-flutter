// test/notebook_cells_test.dart
//
// STAGE face_notebook_cells — the board's notebook DOCUMENT.
// Tier-1: drives `ParityNotebookView` through the `CyanBackend` seam
// (FakeCyanBackend) and asserts the four behaviours the face owns — step cells
// with the tool a compile BOUND to them, the `@`/`#` mention picker, the
// compiled DAG drawn as a diagram, and the code / image cells that carry the
// work's output.
//
// Behaviour spec: scripts/parity_faces/notebook_cells.txt.
//
// SwiftUI reference (read-only):
//   Views/Components/NotebookCellContainer.swift, MarkdownCellView.swift,
//   Views/Components/{CodeCellView,ImageCellView,MermaidCellView}.swift
//   ViewModels/NotebookViewModel.swift

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_notebook_view.dart';

import 'support/parity_test_harness.dart';

const Key _field = ValueKey('notebook.composer.field');
const Key _add = ValueKey('notebook.composer.add');
const Key _compile = ValueKey('notebook.compile');

Finder _row(String value) =>
    find.byKey(ValueKey('notebook.autocomplete.row.$value'));

Finder _node(String id) => find.byKey(ValueKey('notebook.dag.node.$id'));

/// What the composer currently holds — the draft is the operator's text, so it
/// is where an accepted suggestion has to land.
String _draftText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_field)).controller!.text;

/// Type [text] the way a person does, so the picker sees the caret land at the
/// end of what was typed.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_field), text);
  await tester.pumpAndSettle();
}

/// Bring [target] on screen — the document is a lazy list, so a cell below the
/// fold has not been built yet.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(
    target,
    find.byType(ListView),
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ---- scripts/parity_faces/notebook_cells.txt, line 1 ----------------------

  testWidgets('a step cell renders its authored text and its bound tool',
      (tester) async {
    // A step cell is the authored English PLUS the tool the compile resolved
    // for it (`mcp_tool` in the cell's metadata). The flagship board is
    // compiled, so its steps carry binds.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotebookView(boardId: 'b-eng-1'),
        backend: backend, size: const Size(900, 1400));

    // The document reads the SAME ledger the Workflow face does: every authored
    // step is a step cell, in order.
    final cells = await backend.notebookCells('b-eng-1');
    final steps =
        cells.where((c) => c.kind == NotebookCellKind.step).toList();
    expect(steps.map((c) => c.id), ['ws1', 'ws2', 'ws3', 'ws4']);
    expect((await backend.loadWorkflow('b-eng-1')).steps.map((s) => s.id),
        steps.map((c) => c.id));

    // The authored text, on the cell. (Asserted through the cell's own key: the
    // compiled diagram further down labels its nodes with the same English, and
    // that is the diagram's copy, not this cell's.)
    String cellText(String id) =>
        tester.widget<Text>(find.byKey(ValueKey('notebook.step.text.$id'))).data!;
    expect(cellText('ws1'), 'Ingest the master from #shotlist');
    expect(cellText('ws2'), 'Transcode proxies with @ffmpeg');
    expect(cellText('ws4'), 'Publish the cut, send to /review');

    // …and the tool that step is BOUND to, on the cell.
    expect(find.byKey(const ValueKey('notebook.step.tool.ws1')), findsOneWidget);
    expect(find.text('asset-ingest'), findsOneWidget);
    expect(find.text('ffmpeg'), findsOneWidget);

    // A step the compile bound NOTHING to says so rather than borrowing a tool
    // from the step beside it: the human gate is not routed to a plugin.
    expect(steps.firstWhere((c) => c.id == 'ws3').tool, isNull);
    expect(find.byKey(const ValueKey('notebook.step.tool.ws3')), findsNothing);
    expect(
        find.byKey(const ValueKey('notebook.step.unbound.ws3')), findsOneWidget);

    // Step cells are NUMBERED in the document; the prose between them is not.
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Step 4'), findsOneWidget);
    expect(find.text('Markdown'), findsOneWidget);
  });

  // ---- scripts/parity_faces/notebook_cells.txt, line 2 ----------------------

  testWidgets('the mention picker offers plugins on at and artifacts on hash',
      (tester) async {
    // Two vocabularies, one per trigger, both the ENGINE's
    // (`cyan_workflow_autocomplete`): `@` is the group's installed plugins and
    // their manifest tools, `#` is this board's own artifacts. Neither lane
    // ever answers with the other's entries.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotebookView(boardId: 'b-eng-1'),
        backend: backend, size: const Size(900, 1000));

    await _type(tester, 'Transcode the master with @ffmpeg');
    expect(_row('ffmpeg'), findsOneWidget, reason: 'the plugin itself');
    expect(_row('ffmpeg.transcode'), findsOneWidget, reason: 'and its tools');
    expect(_row('shotlist.csv'), findsNothing, reason: '@ is not the file lane');

    // Accepting splices the mention over the token at the caret and closes the
    // picker — the draft is what gets authored, so that is where it lands.
    await tester.tap(_row('ffmpeg.transcode'));
    await tester.pumpAndSettle();
    expect(_draftText(tester), 'Transcode the master with @ffmpeg.transcode ');
    expect(_row('ffmpeg.transcode'), findsNothing);

    // `#` is the OTHER lane: the board's files and its prior-step outputs.
    await _type(tester, 'Re-cut from #shot');
    expect(_row('shotlist.csv'), findsOneWidget);
    expect(_row('ffmpeg'), findsNothing, reason: '# is not the plugin lane');

    await tester.tap(_row('shotlist.csv'));
    await tester.pumpAndSettle();
    expect(_draftText(tester), 'Re-cut from #shotlist.csv ');

    // A trigger with nothing behind it SAYS so rather than rendering an empty
    // popover — a dead index must not look like broken autocomplete.
    await _type(tester, 'Re-cut from #nothing-matches-this');
    expect(find.byKey(const ValueKey('notebook.autocomplete.empty')),
        findsOneWidget);

    // And the mention survives into the cell the composer files: one ledger, so
    // the document and the workflow both hold it.
    await _type(tester, 'Publish with @frameio.publish');
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();
    final filed = (await backend.notebookCells('b-eng-1'))
        .where((c) => c.kind == NotebookCellKind.step)
        .last;
    expect(filed.content, 'Publish with @frameio.publish');
    expect((await backend.loadWorkflow('b-eng-1')).steps.last.id, filed.id);
  });

  // ---- scripts/parity_faces/notebook_cells.txt, line 3 ----------------------

  testWidgets('a compiled DAG renders as a diagram', (tester) async {
    // The diagram is OUTPUT: it exists only once a compile has run, it is drawn
    // from the plan the ENGINE kept, and it is drawn as a DIAGRAM — nodes in
    // dependency layers with edges between them, never as its mermaid source.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotebookView(boardId: 'b-eng-2'),
        backend: backend, size: const Size(900, 1000));

    // Nothing is drawn before the compile.
    expect(_node('ws1'), findsNothing);
    expect(
      (await backend.notebookCells('b-eng-2'))
          .where((c) => c.kind == NotebookCellKind.mermaid),
      isEmpty,
    );

    await tester.tap(find.byKey(_compile));
    await tester.pumpAndSettle();

    // The cell the compile produced is marked as generated, not authored.
    final diagram = (await backend.notebookCells('b-eng-2'))
        .firstWhere((c) => c.kind == NotebookCellKind.mermaid);
    expect(diagram.generatedFrom, 'pipeline');
    expect(diagram.content, startsWith('graph TD'));

    await _reveal(tester, _node('ws3'));

    // Every compiled step became a node…
    for (final id in ['ws1', 'ws2', 'ws3']) {
      expect(_node(id), findsOneWidget, reason: '$id is in the diagram');
    }
    // …laid out as a DAG: layer 0 is what starts the run, and each later layer
    // waits on the one before it.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('notebook.dag.layer.0')),
        matching: _node('ws1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('notebook.dag.layer.2')),
        matching: _node('ws3'),
      ),
      findsOneWidget,
    );
    // Nodes carry the step's label, and the mermaid SOURCE never reaches the
    // screen — a diagram, not a code listing.
    expect(find.text('Design the schema'), findsWidgets);
    expect(find.textContaining('graph TD'), findsNothing);
    expect(find.textContaining('-->'), findsNothing);

    // The picture is the engine's plan, not a client-side redraw: the seam
    // reports the same three steps, wired the same way.
    final plan = await backend.pipelineStatus('b-eng-2');
    expect(plan.steps.map((s) => s.stepId), ['ws1', 'ws2', 'ws3']);
    expect(plan.steps.last.dependsOn, ['ws2']);
  });

  // ---- scripts/parity_faces/notebook_cells.txt, line 4 ----------------------

  testWidgets('a code or image cell renders its content', (tester) async {
    // A code cell shows its SOURCE and what the last run printed; an image cell
    // shows its PIXELS. Neither is a placeholder that names a file it never
    // draws.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotebookView(boardId: 'b-eng-1'),
        backend: backend, size: const Size(900, 1400));

    final cells = await backend.notebookCells('b-eng-1');
    final code =
        cells.firstWhere((c) => c.kind == NotebookCellKind.code);
    final image =
        cells.firstWhere((c) => c.kind == NotebookCellKind.image);

    await _reveal(tester, find.byKey(ValueKey('notebook.code.${code.id}')));

    // The source, verbatim, and the output the run produced.
    expect(find.byKey(ValueKey('notebook.code.${code.id}')), findsOneWidget);
    expect(find.textContaining('ffmpeg.probe("reel_master_v4.mov")'),
        findsOneWidget);
    expect(find.byKey(ValueKey('notebook.code.output.${code.id}')),
        findsOneWidget);
    expect(find.text('3840'), findsOneWidget);
    expect(code.language, 'python');

    await _reveal(tester, find.byKey(ValueKey('notebook.image.${image.id}')));

    // The image cell draws BYTES, not a reference tile: the content decodes to
    // a real PNG and that is what the widget is handed.
    final bytes = image.inlineImageBytes;
    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47],
        reason: 'a PNG signature');
    final widget =
        tester.widget<Image>(find.byKey(ValueKey('notebook.image.${image.id}')));
    expect((widget.image as MemoryImage).bytes, bytes);
    expect(find.byKey(ValueKey('notebook.image.reference.${image.id}')),
        findsNothing);
    expect(find.text('Frame 0412 — grade reference'), findsOneWidget);
  });

  // ---- the document around the four behaviours -------------------------------

  testWidgets('the document renders every cell the board holds, in order',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotebookView(boardId: 'b-eng-1'),
        backend: backend, size: const Size(900, 1400));

    final cells = await backend.notebookCells('b-eng-1');
    expect(cells.map((c) => c.kind), [
      NotebookCellKind.markdown,
      NotebookCellKind.step,
      NotebookCellKind.step,
      NotebookCellKind.step,
      NotebookCellKind.step,
      NotebookCellKind.code,
      NotebookCellKind.image,
      NotebookCellKind.mermaid,
    ]);
    // `cell_order` is the DOCUMENT's, so it is dense and ascending whatever the
    // seed said.
    expect(cells.map((c) => c.order), [0, 1, 2, 3, 4, 5, 6, 7]);

    expect(find.text('8 cells · 4 steps'), findsOneWidget);
    // The markdown cell is RENDERED, not shown as source: the heading's `#`
    // and the checkbox's `- [x]` never reach the screen.
    expect(find.text('Reel cut — v4'), findsOneWidget);
    expect(find.textContaining('# Reel cut'), findsNothing);
    expect(find.text('Shot list locked'), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
  });

  testWidgets('a cell can be folded away and back', (tester) async {
    await pumpParity(tester, const ParityNotebookView(boardId: 'b-eng-1'),
        size: const Size(900, 1400));

    expect(find.byKey(const ValueKey('notebook.step.text.ws1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notebook.collapse.ws1')));
    await tester.pumpAndSettle();

    // The BODY goes; the cell itself stays, so the document keeps its shape.
    expect(find.byKey(const ValueKey('notebook.step.text.ws1')), findsNothing);
    expect(find.byKey(const ValueKey('notebook.cell.ws1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notebook.collapse.ws1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notebook.step.text.ws1')), findsOneWidget);
  });

  testWidgets('a blank cell is refused rather than filed', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotebookView(boardId: 'b-eng-2'),
        backend: backend, size: const Size(900, 900));

    expect(await backend.notebookCells('b-eng-2'), hasLength(3));
    await _type(tester, '   ');
    await tester.tap(find.byKey(_add));
    await tester.pumpAndSettle();

    expect(await backend.notebookCells('b-eng-2'), hasLength(3));
    expect(find.textContaining('Nothing to add'), findsOneWidget);
  });

  testWidgets('a board nobody has written in has an empty document',
      (tester) async {
    // No seeded starter cell: the document is the operator's, and inventing a
    // first cell for them would be a write this side never made.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityNotebookView(boardId: 'b-des-3'),
        backend: backend);

    expect(await backend.notebookCells('b-des-3'), isEmpty);
    expect(find.text('This notebook is empty'), findsOneWidget);
  });

  testWidgets('golden: notebook document', (tester) async {
    await pumpParity(tester, const ParityNotebookView(boardId: 'b-eng-1'));
    await expectLater(
      find.byType(ParityNotebookView),
      matchesGoldenFile('golden/notebook_cells.png'),
    );
  }, tags: 'golden');
}
