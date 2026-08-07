// workflow_face_test.dart — TIER 2. The Workflow (author) face, row 3, driven
// through the PRODUCTION seam against a real seeded engine.
//
// `loadWorkflow` was already written against the engine — the authored steps are
// a board's notebook cells and the compile stamps its plan into each cell's
// `metadata_json` — but "written against the engine" is a claim until something
// runs it. The 302 widget tests drive FakeCyanBackend and would not notice if
// every cell came back unreadable.
//
// So this asserts the face's actual contents against the ENGINE's own seed
// constants (cyan-backend/src/seed.rs): the step texts in `cell_order`, the
// dependency chain the compile wrote, the executor each step routes to, the
// approval gate, and the board's deploy lock. Then it WRITES a step through the
// seam and reads it back, because an author face that cannot author is not a
// face.
//
// SEEDING — `cyan_seed_demo`, never `cyan_seed_demo_if_empty` (inert no-op in
// this engine). See tree_hydration_test.dart for the full note.
//
//   flutter test integration_test/workflow_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// A silent board: no audio track, so the seed lays down four steps and skips
/// the transcribe pass.
const _silentBoard = 'pp-sintel-finish';

/// A board WITH audio — the same spine plus `transcribe`, which is what makes
/// the dependency chain worth asserting: `package` hangs off a different step
/// on this board than on the silent one.
const _audioBoard = 'pp-bbb-master';

/// The board the write test authors onto, so no read assertion above it is
/// standing on a board this file mutated.
const _writeBoard = 'pr-jelly-broll';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_workflow_');
    // BEFORE the boot — see tree_hydration_test.dart: the engine's data dir
    // defaults to "." and its blob store would land in the repository.
    expect(CyanFFI.setDataDir(tmp.path), isTrue,
        reason: 'the engine refused ${tmp.path} as its data dir');
    final ok = CyanFFI.initWithIdentity(
      dbPath: '${tmp.path}/cyan.db',
      secretKeyHex: List.filled(64, 'c').join(),
      relayUrl: '',
      discoveryKey: 'cyan-workflow-face-test',
    );
    expect(ok, isTrue, reason: 'the engine refused to boot with an identity');
    await backend.initialize();

    // Fire-and-forget; poll the seam for the result rather than sleeping a
    // guessed interval.
    CyanFFI.seedDemo();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if ((await backend.loadWorkflow(_silentBoard)).steps.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  });

  // The engine holds the database open for the life of the process and exports
  // no shutdown verb; on Windows the unlink cannot succeed. Named, not hidden.
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      // ignore: avoid_print
      print('note: left ${tmp.path} for the OS to reap — the engine still holds '
          'the database open and has no shutdown verb to call. ($e)');
    }
  });

  test('the face reads the board\'s authored steps in cell order', () async {
    final wf = await backend.loadWorkflow(_silentBoard);

    expect(wf.steps, hasLength(4),
        reason: 'the seed writes four steps onto a silent board (ingest, '
            'qc-probe, qc-findings, package) — got ${wf.steps.length}. Zero '
            'means the cells never decoded and the face would render its empty '
            'state over a board that has a workflow.');
    expect(wf.boardId, _silentBoard);

    // Order is `cell_order`, not insertion luck: the face numbers these 1..4.
    expect(wf.steps[0].text, startsWith('Ingest the broadcast master'));
    expect(wf.steps[1].text, startsWith('QC / probe'));
    expect(wf.steps[2].text, startsWith('QC findings'));
    expect(wf.steps[3].text, startsWith('Package'));

    // The cell ids are the engine's (`<board>-<step_id>`), not ids this side
    // invented — everything the face does to a step is addressed by them.
    expect(wf.steps.map((s) => s.id).toList(),
        ['ingest', 'qc-probe', 'qc-findings', 'package']
            .map((s) => '$_silentBoard-$s')
            .toList());
  });

  test('the compile chips are the plan the engine stamped, not a guess',
      () async {
    final wf = await backend.loadWorkflow(_silentBoard);

    // The executor each step routes to — the "send-to" chip.
    expect(wf.steps.map((s) => s.destination).toList(),
        ['AI (Lens)', 'AI (Lens)', 'AI (Lens)', 'Manual']);

    // `depends_on` — the bound-input chips, and the DAG the dashboard draws.
    expect(wf.steps[0].boundInputs, isEmpty);
    expect(wf.steps[1].boundInputs, ['ingest']);
    expect(wf.steps[2].boundInputs, ['qc-probe']);
    expect(wf.steps[3].boundInputs, ['qc-findings']);

    // `auto_advance: false` on every seeded step ⇒ every step holds a gate.
    for (final s in wf.steps) {
      expect(s.gate, StepGate.needsApproval,
          reason: 'step ${s.id} lost its approval gate — a gate that reads as '
              '"no approval needed" is an unattended run nobody agreed to');
    }

    // The seed binds no MCP tool and the pipeline's `model` is the `cyan-lens`
    // PLACEHOLDER, which the seam deliberately refuses to render as a tool
    // (every step would read "routes to cyan-lens"). So nothing is bound, and
    // the face says the step is ambiguous — which is the truth.
    for (final s in wf.steps) {
      expect(s.tool, isNull,
          reason: 'step ${s.id} claims a bound tool the compile never wrote');
      expect(s.isAmbiguous, isTrue);
    }

    expect(wf.isCompiled, isTrue,
        reason: 'every step carries a pipeline plan, so the board is compiled');
    expect(wf.isDeployed, isTrue,
        reason: 'the seed marks every board deployed — the face must show the '
            'deployed-and-locked banner, not an editable composer');
  });

  test('a board with audio carries the transcribe pass and rehangs package',
      () async {
    final wf = await backend.loadWorkflow(_audioBoard);
    expect(wf.steps, hasLength(5));
    expect(wf.steps[3].id, '$_audioBoard-transcribe');
    expect(wf.steps[3].destination, 'AI (Lens)');
    // The chain differs from the silent board's — proof the dependency edges
    // are read per board rather than assumed from a template.
    expect(wf.steps[4].boundInputs, ['transcribe']);
  });

  test('the notebook DOCUMENT returns every cell, not just the steps',
      () async {
    final cells = await backend.notebookCells(_silentBoard);
    expect(cells, hasLength(4),
        reason: 'the seed writes its steps as markdown cells carrying a '
            'pipeline plan; the document read returns them unfiltered');
    expect(cells.map((c) => c.order).toList(), [0, 1, 2, 3],
        reason: 'the document is ordered by cell_order');
    for (final c in cells) {
      expect(c.boardId, _silentBoard);
      expect(c.content, isNotEmpty);
    }
  });

  test('authoring a step writes through the engine and reads back', () async {
    final before = await backend.loadWorkflow(_writeBoard);
    const text = 'Deliver the graded master to the broadcast bucket.';

    final step = await backend.addWorkflowStep(_writeBoard, text);
    expect(step, isNotNull,
        reason: 'the engine refused the write — an author face that cannot '
            'author is not a face');

    final after = await backend.loadWorkflow(_writeBoard);
    expect(after.steps, hasLength(before.steps.length + 1),
        reason: 'the step was accepted but did not come back: it never reached '
            'the notebook_cells table, or the read filters it out');
    expect(after.steps.last.id, step!.id,
        reason: 'the new step must land LAST — it was filed at the end of the '
            'board and cell_order is what the face numbers by');
    expect(after.steps.last.text, text);
    // Authored but not compiled: nothing has tried to resolve it yet, so it
    // carries no chips and no ambiguity verdict either.
    expect(after.steps.last.tool, isNull);
    expect(after.steps.last.destination, isNull);
    expect(after.steps.last.gate, isNull);
    expect(after.steps.last.isAmbiguous, isFalse);

    // Whitespace is refused at the seam rather than persisted as a blank step.
    expect(await backend.addWorkflowStep(_writeBoard, '   '), isNull);
    expect((await backend.loadWorkflow(_writeBoard)).steps,
        hasLength(after.steps.length));
  });

  test('editing a step rewrites it in place, keeping its id and position',
      () async {
    final wf = await backend.loadWorkflow(_writeBoard);
    final target = wf.steps.last;
    const rewritten = 'Deliver the graded master to the archive bucket.';

    expect(await backend.updateWorkflowStep(_writeBoard, target.id, rewritten),
        isTrue);

    final after = await backend.loadWorkflow(_writeBoard);
    expect(after.steps, hasLength(wf.steps.length),
        reason: 'an edit must not add a step');
    expect(after.steps.last.id, target.id,
        reason: 'the edit minted a new id — the step moved instead of changing');
    expect(after.steps.last.text, rewritten);

    // A step id the board does not hold is refused, not silently appended.
    expect(await backend.updateWorkflowStep(_writeBoard, 'no-such-step', 'x'),
        isFalse);
  });
}
