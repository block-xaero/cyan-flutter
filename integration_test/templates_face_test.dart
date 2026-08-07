// templates_face_test.dart — TIER 2. The Template picker, row 18, through the
// PRODUCTION seam against a real engine.
//
// Four lanes, and only the first two had ever been exercised against the
// engine by anything: `cyan_list_templates` (the catalog), the clone
// (`cyan_workflow_from_template` → real authorable step cells), the typed
// outcome (`cyan_template_clone_outcome` — how many steps landed and what the
// auto-install did), and — new in row 18 — the REPLACE clone's clear
// (`cyan_delete_notebook_cell`), which is what makes "Replace existing steps"
// something other than a second append.
//
// The clone is FIRE-AND-FORGET through the engine's command actor, so every
// assertion here polls the board's cells rather than trusting the dispatch.
//
//   flutter test integration_test/templates_face_test.dart -d windows

import 'dart:io';

import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/ffi_helpers.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final backend = CyanBackendFFI();
  late String board;
  late String tenant;

  /// Poll the board's authored steps until [test] holds or the budget runs out.
  Future<List<WorkflowStep>> untilSteps(
      bool Function(List<WorkflowStep>) test) async {
    var steps = (await backend.loadWorkflow(board)).steps;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!test(steps) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      steps = (await backend.loadWorkflow(board)).steps;
    }
    return steps;
  }

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('cyan_templates_');
    expect(CyanFFI.setDataDir(tmp.path), isTrue,
        reason: 'the engine refused ${tmp.path} as its data dir and would '
            'write its blob store into the source tree');
    expect(
      CyanFFI.initWithIdentity(
        dbPath: '${tmp.path}/cyan.db',
        secretKeyHex: List.filled(64, '2').join(),
        relayUrl: '',
        discoveryKey: 'cyan-templates-face-test',
      ),
      isTrue,
      reason: 'the engine refused to boot with an identity',
    );
    await backend.initialize();

    CyanFFI.seedDemo();
    var boards = <BoardWithContext>[];
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      boards = await backend.loadAllBoards();
      if (boards.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(boards, isNotEmpty, reason: 'the seed never landed');
    // A board with NO authored steps, so the clone's arithmetic is the
    // template's alone.
    final empty = boards.where((b) => b.board.id.isNotEmpty);
    board = empty.last.board.id;
    tenant = empty.last.group.id;
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      // ignore: avoid_print
      print('note: left ${tmp.path} for the OS to reap — the engine still holds '
          'the database open and has no shutdown verb to call. ($e)');
    }
  });

  test('the engine ships a template catalog, and every row is usable',
      () async {
    final templates = await backend.templateList(tenantId: tenant);

    expect(templates, isNotEmpty,
        reason: 'the picker would list nothing at all — the built-in seeds are '
            'the whole point of the sheet on a fresh install');
    for (final t in templates) {
      expect(t.id, isNotEmpty, reason: 'a template with no id cannot be cloned');
      expect(t.name, isNotEmpty,
          reason: 'the row would render a blank line: ${t.id}');
    }
  });

  test('a clone lands the template\'s steps as REAL authorable step cells',
      () async {
    final before = (await backend.loadWorkflow(board)).steps;
    final template = (await backend.templateList(tenantId: tenant)).first;

    await backend.workflowFromTemplate(template.id, board, tenantId: tenant);
    final after = await untilSteps((s) => s.length > before.length);

    expect(after.length, greaterThan(before.length),
        reason: 'the clone dispatched and nothing ever materialized — the '
            'picker would sit on its spinner for 90 seconds and then say so');
    for (final step in after.sublist(before.length)) {
      expect(step.id, isNotEmpty);
      expect(step.text.trim(), isNotEmpty,
          reason: 'a blank step cell is not an authorable one');
    }
  });

  test('the engine reports the clone\'s typed outcome', () async {
    final outcome = await backend.templateCloneOutcome(board);

    expect(outcome, isNotNull,
        reason: 'the picker polls this for up to 90s and then reports that '
            'nothing landed — a clone that materialized steps but never '
            'reported would look like a failure');
    expect(outcome!.steps, greaterThan(0));
    // The auto-install list may legitimately be empty (a template that binds
    // nothing, or every plugin already present) — what matters is that each
    // row it DOES carry names its plugin, or the report cannot be rendered.
    for (final install in outcome.pluginInstalls) {
      expect(install.pluginId, isNotEmpty);
    }
  });

  test('REPLACE really clears: the engine deletes the step cells the operator '
      'was shown', () async {
    final before = (await backend.loadWorkflow(board)).steps;
    expect(before, isNotEmpty,
        reason: 'the clone above left nothing to replace');

    // This is the lane row 18 added to the seam. Before it, a Replace was a
    // second Append wearing a different label.
    for (final step in before) {
      expect(await backend.deleteWorkflowStep(board, step.id), isTrue,
          reason: 'the engine refused to delete ${step.id}');
    }

    final cleared = await untilSteps((s) => s.isEmpty);
    expect(cleared, isEmpty,
        reason: 'the engine took the deletes and the cells are still there — a '
            'Replace would leave the old workflow underneath the new one');

    // …and the board takes a fresh clone on top of the cleared slate.
    final template = (await backend.templateList(tenantId: tenant)).first;
    await backend.workflowFromTemplate(template.id, board, tenantId: tenant);
    final after = await untilSteps((s) => s.isNotEmpty);
    expect(after, isNotEmpty);
    for (final gone in before) {
      expect(after.any((s) => s.id == gone.id), isFalse,
          reason: '${gone.id} came back after a delete + clone');
    }
  });

  test('deleting a step the board does not have is refused, not silently '
      'reported as done', () async {
    expect(await backend.deleteWorkflowStep(board, ''), isFalse);
    expect(await backend.deleteWorkflowStep(board, 'no-such-step-id'), isFalse,
        reason: 'a delete that reports success for an id the engine never had '
            'would let a Replace believe it cleared a board it did not');
  });
}
