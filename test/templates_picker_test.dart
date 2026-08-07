// test/templates_picker_test.dart
//
// STAGE face_templates_picker — the Workflow face's template surface.
// Tier-1: drives `ParityTemplatePicker` through the `CyanBackend` seam
// (FakeCyanBackend) and asserts what actually LANDED — the step cells a clone
// materialized on the board, the outcome the engine reported for it, and the
// notes a save carried out with the template — not merely what got painted.
//
// Behaviour spec: scripts/parity_faces/templates_picker.txt.
//
// SwiftUI reference (read-only):
//   Views/TemplatePickerSheet.swift, ViewModels/TemplatesViewModel.swift

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_template_picker.dart';
import 'package:cyan_flutter/widgets/parity/parity_workflow_view.dart';

import 'support/parity_test_harness.dart';

Finder _clone(String templateId) =>
    find.byKey(ValueKey('templates.clone.$templateId'));

Finder _installRow(String pluginId) =>
    find.byKey(ValueKey('templates.outcome.plugin.$pluginId'));

/// Clone [templateId] onto a board that ALREADY has steps, choosing Append.
/// A non-empty board is always asked first (FABLE_FULL_AUDIT Area B), so a bare
/// tap on Clone is only half the gesture there.
Future<void> _cloneAppending(WidgetTester tester, String templateId) async {
  await tester.tap(_clone(templateId));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('templates.clone.decision')), findsOneWidget,
      reason: 'a board with steps must be ASKED, never silently appended to');
  await tester.tap(find.byKey(const ValueKey('templates.clone.append')));
  await tester.pumpAndSettle();
}

/// The template the tenant most recently saved, off the seam — the round trip
/// is the point: a save that only lived in widget state is not a save.
Future<CyanTemplate?> _lastUserTemplate(
    FakeCyanBackend backend, String tenantId) async {
  final rows = [
    for (final t in await backend.templateList(tenantId: tenantId))
      if (!t.isBuiltin) t,
  ];
  return rows.isEmpty ? null : rows.last;
}

void main() {
  // ---- scripts/parity_faces/templates_picker.txt, line 1 --------------------

  testWidgets('the template picker lists available workflow templates',
      (tester) async {
    // Both of the engine's sources, sectioned: the tenant-agnostic seeds and
    // (once there are any) this tenant's own saves. Each row previews the
    // pre-written English rather than just naming the template.
    final backend = FakeCyanBackend();
    await pumpParity(tester,
        const ParityTemplatePicker(boardId: 'b-eng-2'),
        backend: backend);

    // The seam's catalog for this board's tenant, and the face shows all of it.
    final catalog = await backend.templateList(tenantId: 'g-eng');
    expect(catalog.map((t) => t.id),
        containsAll(['tpl-dailies', 'tpl-finishing', 'tpl-promo']));

    expect(find.byKey(const ValueKey('templates.section.builtin')),
        findsOneWidget);
    for (final id in ['tpl-dailies', 'tpl-finishing', 'tpl-promo']) {
      expect(find.byKey(ValueKey('templates.row.$id')), findsOneWidget);
      expect(_clone(id), findsOneWidget);
    }
    expect(find.text('Dailies turnaround'), findsOneWidget);
    expect(find.text('Finishing + delivery'), findsOneWidget);
    expect(find.text('Promo cutdown'), findsOneWidget);

    // The rows carry what the choice is actually made on: how long the workflow
    // is, where it came from, and the first of its steps.
    expect(find.text('4 steps'), findsWidgets);
    expect(find.text('builtin'), findsWidgets);
    expect(find.text("Ingest today's cards"), findsOneWidget);
    expect(find.text('@asset-ingest'), findsOneWidget);
    expect(find.text('+ 1 more'), findsWidgets,
        reason: 'a four-step template previews three and counts the rest');

    // A roadmap tool is shown as visibly inactive — it is named, never offered.
    expect(
        find.byKey(
            const ValueKey('templates.roadmap.tpl-finishing.spec-deliver')),
        findsOneWidget);

    // Nothing has been cloned or saved just by listing.
    expect(find.byKey(const ValueKey('templates.outcome')), findsNothing);
    expect(find.byKey(const ValueKey('templates.section.user')), findsNothing);
  });

  // ---- scripts/parity_faces/templates_picker.txt, line 2 --------------------

  testWidgets('choosing a template clones its steps onto the board',
      (tester) async {
    // The clone materializes REAL authorable step cells on the board through
    // the seam — verbatim, in order, appended after what was already authored.
    final backend = FakeCyanBackend();
    var cloned = false;
    await pumpParity(
      tester,
      ParityTemplatePicker(boardId: 'b-eng-2', onCloned: () => cloned = true),
      backend: backend,
    );

    expect((await backend.loadWorkflow('b-eng-2')).steps, hasLength(3));

    await _cloneAppending(tester, 'tpl-dailies');

    final steps = (await backend.loadWorkflow('b-eng-2')).steps;
    expect(steps, hasLength(7), reason: 'four template steps landed');
    expect(steps.map((s) => s.text).toList().sublist(3), [
      "Ingest today's cards",
      'Transcode viewing proxies',
      'Wait for the editor to sign off',
      'Publish the dailies to review',
    ]);
    // The step's bound plugin travels with it; an unbound step stays unbound
    // rather than having a tool invented onto it.
    expect(steps[3].tool, 'asset-ingest');
    expect(steps[5].tool, isNull);
    // The board that was already authored is untouched.
    expect(steps.first.text, 'Design the schema');

    // The host is told, so the Workflow face re-reads its cells.
    expect(cloned, isTrue);
  });

  // ---- scripts/parity_faces/templates_picker.txt, line 3 --------------------

  testWidgets(
      'the clone reports how many steps landed and which plugins are ready',
      (tester) async {
    // The clone verb is fire-and-forget, so the face POLLS the engine's own
    // outcome and reports it: the count of cells that landed, and the declared
    // plugins that are ready to run them.
    final backend = FakeCyanBackend();
    await pumpParity(tester,
        const ParityTemplatePicker(boardId: 'b-eng-2'),
        backend: backend);

    await _cloneAppending(tester, 'tpl-finishing');

    expect(find.byKey(const ValueKey('templates.outcome')), findsOneWidget);
    expect(find.textContaining('3 steps landed'), findsOneWidget);
    expect(find.textContaining('1 plugin ready (loudness)'), findsOneWidget);

    // The report is the ENGINE's, not a client-side count: the same numbers
    // come back off the seam.
    final outcome = await backend.templateCloneOutcome('b-eng-2');
    expect(outcome!.steps, 3);
    expect((await backend.loadWorkflow('b-eng-2')).steps, hasLength(6));
    expect(
      [
        for (final p in outcome.pluginInstalls)
          if (p.outcome != TemplatePluginInstallOutcome.failed) p.pluginId,
      ],
      ['loudness'],
    );
  });

  // ---- scripts/parity_faces/templates_picker.txt, line 4 --------------------

  testWidgets('a template clone failure names the plugin that failed',
      (tester) async {
    // A plugin that could not be fetched is NEVER a silent skip: the steps
    // bound to it will only pend, so the picker names it and quotes the
    // engine's reason. The clone itself still succeeded.
    final backend = FakeCyanBackend();
    await pumpParity(tester,
        const ParityTemplatePicker(boardId: 'b-eng-2'),
        backend: backend);

    await _cloneAppending(tester, 'tpl-finishing');

    // Named in the summary…
    expect(find.textContaining('1 failed (spec-deliver)'), findsOneWidget);
    // …and on its own row, with the reason the engine gave.
    expect(_installRow('spec-deliver'), findsOneWidget);
    expect(find.text('@spec-deliver'), findsOneWidget);
    expect(
      find.textContaining('no bundle for spec-deliver in the plugin source'),
      findsOneWidget,
    );

    // The failure did not swallow the clone: the steps are on the board and the
    // plugin that DID land is not reported as failed.
    expect((await backend.loadWorkflow('b-eng-2')).steps, hasLength(6));
    final outcome = await backend.templateCloneOutcome('b-eng-2');
    expect(outcome!.hasFailedInstall, isTrue);
    expect(
      [
        for (final p in outcome.pluginInstalls)
          if (p.outcome == TemplatePluginInstallOutcome.failed) p.pluginId,
      ],
      ['spec-deliver'],
    );
  });

  // ---- scripts/parity_faces/templates_picker.txt, line 5 --------------------

  testWidgets('save as template carries the board standing notes',
      (tester) async {
    // Save-as-template goes through the FROM-BOARD verb, so the board's
    // STANDING guidance (its constitution and preferences) travels with the
    // template — a clone of it is not a blank slate. A run's working notes stay
    // behind, because they belong to that run and not to the workflow.
    final backend = FakeCyanBackend();
    await pumpParity(tester,
        const ParityTemplatePicker(boardId: 'b-eng-1'),
        backend: backend);

    expect(await _lastUserTemplate(backend, 'g-eng'), isNull);

    await tester.enterText(
        find.byKey(const ValueKey('templates.save.name')), 'House delivery');
    await tester.enterText(
        find.byKey(const ValueKey('templates.save.description')),
        'The way this group finishes a cut.');
    await tester.tap(find.byKey(const ValueKey('templates.save.confirm')));
    await tester.pumpAndSettle();

    // It reached the ENGINE, owned by this board's tenant, with the board's
    // current steps.
    final saved = await _lastUserTemplate(backend, 'g-eng');
    expect(saved, isNotNull);
    expect(saved!.name, 'House delivery');
    expect(saved.tenantId, 'g-eng');
    expect(saved.steps.map((s) => s.text),
        (await backend.loadWorkflow('b-eng-1')).steps.map((s) => s.text));

    // The standing notes rode along…
    expect(saved.notes.map((n) => n.kind), ['constitution', 'preference']);
    expect(saved.notes.first.text,
        'Nothing ships outside the device before the review gate.');
    expect(saved.notes.last.text,
        'Cut proxies at 1080p; keep the masters untouched.');
    // …and the working note did not.
    expect(
      saved.notes.map((n) => n.text),
      isNot(contains(contains('Conformed the offline'))),
    );

    // The face read it back rather than remembering it: it is under the
    // tenant's own section now, and the confirmation says what was carried.
    // (The seeds fill the viewport, so the new section is scrolled to — the
    // list is the engine's answer, not a truncated copy of it.)
    await tester.drag(
        find.byKey(const ValueKey('templates.list')), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('templates.section.user')), findsOneWidget);
    expect(find.byKey(ValueKey('templates.row.${saved.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('templates.save.confirmation')),
        findsOneWidget);
    expect(find.textContaining('2 standing notes'), findsOneWidget);
    expect(find.text('yours'), findsOneWidget);
  });

  // ---- scripts/parity_faces/templates_picker.txt, line 6 --------------------

  testWidgets('the clone reports its plugin auto install outcome',
      (tester) async {
    // Per declared plugin, what the clone-time auto-install actually did —
    // fetched and landed, or already here. The two are different facts and the
    // report keeps them apart.
    final backend = FakeCyanBackend();
    await pumpParity(tester,
        const ParityTemplatePicker(boardId: 'b-eng-2'),
        backend: backend);

    // `loudness` is declared auto-install and is not on this device yet.
    expect((await backend.pluginCatalog()).map((p) => p.id),
        isNot(contains('loudness')));

    await _cloneAppending(tester, 'tpl-finishing');

    expect(find.text('Plugin auto install'), findsOneWidget);
    expect(_installRow('loudness'), findsOneWidget);
    expect(
      find.descendant(of: _installRow('loudness'), matching: find.text('Installed')),
      findsOneWidget,
    );
    // It really landed — the device's catalog carries it now.
    expect((await backend.pluginCatalog()).map((p) => p.id),
        contains('loudness'));

    // Cloning again reports the SECOND truth: already present, not re-fetched.
    await _cloneAppending(tester, 'tpl-finishing');

    expect(
      find.descendant(
          of: _installRow('loudness'), matching: find.text('Already installed')),
      findsOneWidget,
    );
    expect(
      (await backend.templateCloneOutcome('b-eng-2'))!
          .pluginInstalls
          .firstWhere((p) => p.pluginId == 'loudness')
          .outcome,
      TemplatePluginInstallOutcome.alreadyPresent,
    );
  });

  // ---- the picker on the face that presents it ------------------------------

  testWidgets('the Workflow face opens the picker and takes the clone',
      (tester) async {
    // The picker is a sheet on the Workflow face (Swift presents
    // `TemplatePickerSheet` from `WorkflowView`), and the face re-reads its
    // cells after a clone rather than showing a stale list.
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityWorkflowView(boardId: 'b-des-3'),
        backend: backend);

    expect(find.text('No steps yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('workflow.templates')));
    await tester.pumpAndSettle();
    expect(find.byType(ParityTemplatePicker), findsOneWidget);

    await tester.tap(_clone('tpl-dailies'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('templates.done')));
    await tester.pumpAndSettle();

    expect(find.byType(ParityTemplatePicker), findsNothing);
    expect(find.text('No steps yet'), findsNothing);
    expect(find.text("Ingest today's cards"), findsOneWidget);
    expect((await backend.loadWorkflow('b-des-3')).steps, hasLength(4));
  });

  // ---- FABLE_FULL_AUDIT Area B: a non-empty board is ASKED ------------------

  testWidgets('cloning onto a board that has steps ASKS before it does '
      'anything, and Cancel does nothing at all', (tester) async {
    final backend = FakeCyanBackend();
    var cloned = false;
    await pumpParity(
      tester,
      ParityTemplatePicker(boardId: 'b-eng-2', onCloned: () => cloned = true),
      backend: backend,
    );

    final before = (await backend.loadWorkflow('b-eng-2')).steps;
    expect(before, hasLength(3));

    await tester.tap(_clone('tpl-dailies'));
    await tester.pumpAndSettle();

    // The decision, with the count it is about — nothing has been written yet.
    expect(find.byKey(const ValueKey('templates.clone.decision')),
        findsOneWidget);
    expect(find.text('This board already has 3 workflow steps.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('templates.clone.replace')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('templates.clone.append')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('templates.clone.cancel')), findsOneWidget);
    expect((await backend.loadWorkflow('b-eng-2')).steps, hasLength(3),
        reason: 'the clone dispatched before the human decided anything');

    await tester.tap(find.byKey(const ValueKey('templates.clone.cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('templates.clone.decision')), findsNothing);
    expect((await backend.loadWorkflow('b-eng-2')).steps.map((s) => s.text),
        before.map((s) => s.text));
    expect(cloned, isFalse, reason: 'a cancelled clone told the host it cloned');
  });

  testWidgets('Replace clears exactly the steps the operator was shown, then '
      'clones', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityTemplatePicker(boardId: 'b-eng-2'),
        backend: backend);

    final before = (await backend.loadWorkflow('b-eng-2')).steps;
    expect(before, hasLength(3));

    await tester.tap(_clone('tpl-dailies'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('templates.clone.replace')));
    await tester.pumpAndSettle();

    final after = (await backend.loadWorkflow('b-eng-2')).steps;
    // The template's four steps and NOTHING else — the board's own three are
    // gone from the engine, not merely hidden.
    expect(after, hasLength(4));
    expect(after.map((s) => s.text), [
      "Ingest today's cards",
      'Transcode viewing proxies',
      'Wait for the editor to sign off',
      'Publish the dailies to review',
    ]);
    for (final gone in before) {
      expect(after.any((s) => s.id == gone.id), isFalse,
          reason: '${gone.id} survived a Replace');
    }
  });

  testWidgets('a Replace that cannot clear the board does NOT clone over it',
      (tester) async {
    // A half-cleared board is worse than an uncleared one: the operator asked
    // for the old steps to go and the new ones to arrive, and getting neither
    // is recoverable while getting half of each is not.
    final backend = _RefusingDeleteBackend();
    await pumpParity(tester, const ParityTemplatePicker(boardId: 'b-eng-2'),
        backend: backend);

    final before = (await backend.loadWorkflow('b-eng-2')).steps;

    await tester.tap(_clone('tpl-dailies'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('templates.clone.replace')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('templates.error')), findsOneWidget);
    expect(find.textContaining("Couldn't clear the existing steps"),
        findsOneWidget);
    final after = (await backend.loadWorkflow('b-eng-2')).steps;
    expect(after.map((s) => s.text), before.map((s) => s.text),
        reason: 'the board changed even though the clear failed');
  });

  testWidgets('a board with NO steps clones without being asked',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityTemplatePicker(boardId: 'b-des-3'),
        backend: backend);

    expect((await backend.loadWorkflow('b-des-3')).steps, isEmpty);

    await tester.tap(_clone('tpl-dailies'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('templates.clone.decision')), findsNothing,
        reason: 'there is nothing to decide about on an empty board');
    expect((await backend.loadWorkflow('b-des-3')).steps, hasLength(4));
  });

  testWidgets('golden: template picker', (tester) async {
    await pumpParity(
        tester, const ParityTemplatePicker(boardId: 'b-eng-2'));
    await expectLater(
      find.byType(ParityTemplatePicker),
      matchesGoldenFile('golden/template_picker.png'),
    );
  }, tags: 'golden');
}

/// A backend whose step delete always refuses — the "the engine would not let
/// go of the old steps" case a Replace has to survive without half-doing it.
class _RefusingDeleteBackend extends FakeCyanBackend {
  @override
  Future<bool> deleteWorkflowStep(String boardId, String stepId) async => false;
}
