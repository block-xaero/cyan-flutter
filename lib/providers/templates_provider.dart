// providers/templates_provider.dart
//
// The TEMPLATE PICKER's state, ported from `TemplatesViewModel`
// (ViewModels/TemplatesViewModel.swift). A template is a pre-written English
// workflow; cloning one materializes REAL authorable step cells on a board —
// the answer to a blank slate — and saving one carries the board's current
// steps (and its standing notes) back out for reuse.
//
// Every read and write goes through the `CyanBackend` seam (`templateList` /
// `workflowFromTemplate` / `templateCloneOutcome` / `templateSaveFromBoard`),
// so the whole face is Tier-1 drivable against FakeCyanBackend with no dylib.
//
// Three invariants carried over from the Swift view-model:
//
//   • The clone is FIRE-AND-FORGET. The seam acknowledges nothing, so the
//     outcome is POLLED (`templateCloneOutcome`) rather than returned — and an
//     engine that has not finished yet answers null, which is a reason to keep
//     polling, never a failure to report.
//   • A FAILED auto-install is never silent. The clone still succeeded and the
//     steps still landed, but the plugin that did not land is NAMED, with the
//     engine's own reason, because a step bound to a missing plugin only pends.
//   • The board is read at SAVE time, not at open time — edits made while the
//     picker is open still belong in the template being saved.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import '../models/default_plugins.dart';
import '../services/plugin_bundle_fetcher.dart';
import 'cyan_backend_provider.dart';
import 'marketplace_provider.dart';

/// The picker's scope: the board a clone lands on, and the tenant whose saves
/// are visible beside the global seeds. An empty [tenantId] is resolved off the
/// board's own group through the seam — the derivation the engine does.
typedef TemplatesScope = ({String boardId, String tenantId});

/// What a clone does to steps the board ALREADY has. A board with none never
/// sees this choice; a board with some is always asked (FABLE_FULL_AUDIT Area
/// B — cloning must never silently append onto somebody's authored workflow).
enum CloneMode { append, replace }

@immutable
class TemplatesState {
  final bool loading;

  /// The catalog could not be read, or a write was refused. Shown rather than
  /// swallowed: an empty list must never stand in for a broken read.
  final String? error;

  /// The tenant this picker is scoped to, once resolved. Empty means the board
  /// belongs to no group the seam knows — seeds list, saving is refused.
  final String tenantId;

  /// The tenant-agnostic seeds (`builtin`, `builtin:postprod`,
  /// `builtin:roletype`) — every tenant sees them.
  final List<CyanTemplate> builtins;

  /// This tenant's own save-as-template results.
  final List<CyanTemplate> userTemplates;

  /// The template a clone is in flight for; null when none is.
  final String? cloningId;

  /// The LAST clone's outcome, as the engine reported it. Null until one lands.
  final TemplateCloneOutcome? outcome;

  /// The name of the template that outcome belongs to, so the report reads as
  /// English rather than as an id.
  final String? clonedName;

  /// The confirmation line a save leaves behind.
  final String? saveConfirmation;

  const TemplatesState({
    this.loading = true,
    this.error,
    this.tenantId = '',
    this.builtins = const [],
    this.userTemplates = const [],
    this.cloningId,
    this.outcome,
    this.clonedName,
    this.saveConfirmation,
  });

  TemplatesState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    String? tenantId,
    List<CyanTemplate>? builtins,
    List<CyanTemplate>? userTemplates,
    String? cloningId,
    bool clearCloning = false,
    TemplateCloneOutcome? outcome,
    String? clonedName,
    String? saveConfirmation,
    bool clearSaveConfirmation = false,
  }) {
    return TemplatesState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      tenantId: tenantId ?? this.tenantId,
      builtins: builtins ?? this.builtins,
      userTemplates: userTemplates ?? this.userTemplates,
      cloningId: clearCloning ? null : (cloningId ?? this.cloningId),
      outcome: outcome ?? this.outcome,
      clonedName: clonedName ?? this.clonedName,
      saveConfirmation: clearSaveConfirmation
          ? null
          : (saveConfirmation ?? this.saveConfirmation),
    );
  }

  /// Every template the picker offers, seeds first — the order the keyboard
  /// selection walks and the order the sections render in.
  List<CyanTemplate> get all => [...builtins, ...userTemplates];

  bool get isEmpty => builtins.isEmpty && userTemplates.isEmpty;

  /// Saving is a TENANT-scoped write — a user template belongs to a group, so a
  /// board with no group has nowhere to put one.
  bool get canSave => tenantId.isNotEmpty;

  CyanTemplate? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// The picker for one board. Keyed by (board, tenant) because the catalog a
/// tenant sees and the board a clone lands on are two different addresses.
final templatesProvider = StateNotifierProvider.autoDispose
    .family<TemplatesController, TemplatesState, TemplatesScope>((ref, scope) {
  final controller = TemplatesController(
    backend: ref.watch(cyanBackendProvider),
    fetcher: ref.watch(pluginBundleFetcherProvider),
    boardId: scope.boardId,
    tenantId: scope.tenantId,
  );
  controller.load();
  return controller;
});

class TemplatesController extends StateNotifier<TemplatesState> {
  final CyanBackend _backend;
  final String boardId;

  /// The tenant as the CALLER gave it. Empty means "derive it from the board",
  /// which [load] does through the seam.
  final String tenantId;

  /// Where a step-bound plugin's bytes come from when the group does not hold
  /// it yet. Injected so a Tier-1 clone needs no network.
  final PluginBundleFetcher _fetcher;

  TemplatesController({
    required CyanBackend backend,
    required PluginBundleFetcher fetcher,
    required this.boardId,
    this.tenantId = '',
  })  : _backend = backend,
        _fetcher = fetcher,
        super(const TemplatesState());

  /// Install the plugins this template's STEPS bind, before the clone lands.
  ///
  /// The engine's own clone-path auto-install covers only the template's
  /// declared `auto_install_set`, and its DTO explicitly excludes step
  /// `@mentions`. In practice that set is EMPTY on the builtins whose steps bind
  /// `@cyan-media` / `@ae` / `@frameio`, and on every user-saved template — so
  /// the engine installs nothing, the bind then refuses any mention whose bundle
  /// is not in the group, and the same clone that is runnable on macOS lands
  /// unrunnable here with an empty install report. The Mac installs the UNION of
  /// every plugin the steps bind; so does this.
  ///
  /// BEST EFFORT by design. A clone that cannot reach the bundle host must still
  /// land its steps — the operator can install the tool afterwards, but they
  /// cannot re-run a clone that refused. So every failure is swallowed and the
  /// clone proceeds.
  ///
  /// Port of `TemplatesViewModel.autoInstallTemplatePlugins`.
  Future<void> _autoInstallTemplatePlugins(String templateId) async {
    final template = state.byId(templateId);
    if (template == null) return;

    final group = state.tenantId;
    if (group.isEmpty) return;

    // The union of what the steps bind, minus the defaults every group already
    // carries — `DefaultPlugins.ensure` has provisioned those from app-shipped
    // bytes, and re-fetching them over the network would undo the whole point
    // of shipping them.
    final required = <String>{
      for (final step in template.steps)
        if (step.plugin != null && step.plugin!.isNotEmpty) step.plugin!,
    }..removeAll(DefaultPlugins.ids);
    if (required.isEmpty) return;

    // What the group already holds — installing a bundle twice is wasted
    // bytes, not a failure, but the catalog read is cheap.
    Set<String> installed;
    try {
      installed = {for (final p in await _backend.pluginCatalog()) p.id};
    } catch (_) {
      installed = const {};
    }

    for (final pluginId in required) {
      if (installed.contains(pluginId)) continue;
      try {
        final bytes = await _fetcher.fetchBundleB64(pluginId);
        await _backend.installPluginBundle(group, pluginId, bytes);
      } catch (_) {
        // See the best-effort note above.
      }
    }
  }

  /// Read the catalog: the seeds plus this tenant's own saves, split by source.
  /// This is also the RELOAD a save ends with, so a saved template appears
  /// because the engine kept it, never because this object remembered it.
  Future<void> load() async {
    try {
      final tenant = tenantId.isNotEmpty ? tenantId : await _resolveTenant();
      final templates = await _backend.templateList(tenantId: tenant);
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        clearError: true,
        tenantId: tenant,
        builtins: [
          for (final t in templates)
            if (t.isBuiltin) t
        ],
        userTemplates: [
          for (final t in templates)
            if (!t.isBuiltin) t
        ],
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: 'Could not read the template catalog: $e',
      );
    }
  }

  /// The board's group, off the seam. The engine derives a clone's tenant the
  /// same way; deriving it here too keeps the LIST the picker shows and the
  /// tenant a clone runs under from disagreeing.
  Future<String> _resolveTenant() async {
    try {
      final boards = await _backend.loadAllBoards();
      for (final b in boards) {
        if (b.board.id == boardId) return b.group.id;
      }
    } catch (_) {
      // A tenant that cannot be resolved is not an error: the seeds are global,
      // so the picker still lists and clones — only saving is off.
    }
    return '';
  }

  /// Clone [templateId] onto this board as real step cells, then report what
  /// the engine did.
  ///
  /// [mode] is the decision a NON-EMPTY board forces (FABLE_FULL_AUDIT Area B):
  /// cloning never silently appends onto steps somebody already authored.
  /// [CloneMode.replace] clears exactly [replacingStepIds] — the ids the
  /// operator was shown — through the seam BEFORE the clone dispatches, and
  /// ABORTS if any of them refuses, because a half-cleared board is worse than
  /// an uncleared one.
  ///
  /// Returns whether an outcome landed.
  Future<bool> clone(
    String templateId, {
    CloneMode mode = CloneMode.append,
    List<String> replacingStepIds = const [],
    int attempts = 90,
    Duration interval = const Duration(seconds: 1),
  }) async {
    if (state.cloningId != null) return false;
    final name = state.byId(templateId)?.name;
    state = state.copyWith(cloningId: templateId, clearError: true);

    if (mode == CloneMode.replace && replacingStepIds.isNotEmpty) {
      var cleared = true;
      for (final id in replacingStepIds) {
        try {
          if (!await _backend.deleteWorkflowStep(boardId, id)) cleared = false;
        } catch (_) {
          cleared = false;
        }
        if (!cleared) break;
      }
      if (!cleared) {
        if (mounted) {
          state = state.copyWith(
            clearCloning: true,
            error: "Couldn't clear the existing steps before the clone.",
          );
        }
        return false;
      }
    }

    // The plugins the template's STEPS bind must be in the group BEFORE the
    // clone lands, or every one of those steps compiles to a mention the engine
    // refuses to bind.
    await _autoInstallTemplatePlugins(templateId);

    try {
      await _backend.workflowFromTemplate(templateId, boardId,
          tenantId: state.tenantId);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          clearCloning: true,
          error: 'Could not clone that template: $e',
        );
      }
      return false;
    }

    final outcome = await _pollOutcome(attempts: attempts, interval: interval);
    if (!mounted) return outcome != null;
    if (outcome == null) {
      state = state.copyWith(
        clearCloning: true,
        error: 'The clone did not report back — nothing landed on this board.',
      );
      return false;
    }
    state = state.copyWith(
      clearCloning: true,
      outcome: outcome,
      clonedName: name ?? templateId,
    );
    return true;
  }

  /// Poll the engine for THIS board's clone outcome. The first read happens
  /// immediately — an engine that already finished must not be made to wait —
  /// and null only means "not yet", so it is retried rather than reported.
  Future<TemplateCloneOutcome?> _pollOutcome({
    required int attempts,
    required Duration interval,
  }) async {
    for (var attempt = 0; attempt < (attempts < 1 ? 1 : attempts); attempt++) {
      if (attempt > 0) await Future<void>.delayed(interval);
      if (!mounted) return null;
      try {
        final outcome = await _backend.templateCloneOutcome(boardId);
        if (outcome != null) return outcome;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Save the board's CURRENT workflow as a reusable, tenant-scoped template.
  ///
  /// The steps are read off the board at save time (not when the picker
  /// opened), and the save goes through the FROM-BOARD verb so the board's
  /// standing notes — its constitution and preferences — travel with the
  /// template and a later clone lands them too.
  Future<bool> saveBoardAsTemplate(String name, String description) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(error: 'Give the template a name.');
      return false;
    }
    if (!state.canSave) {
      state = state.copyWith(
          error:
              'No group context — a template is saved to the board\'s group.');
      return false;
    }

    final TemplateSaveResult result;
    try {
      final workflow = await _backend.loadWorkflow(boardId);
      final steps = [
        for (final s in workflow.steps)
          TemplateStep(text: s.text, plugin: s.tool),
      ];
      if (steps.isEmpty) {
        if (mounted) {
          state = state.copyWith(error: 'This board has no steps to save.');
        }
        return false;
      }
      result = await _backend.templateSaveFromBoard(
          state.tenantId, trimmed, description.trim(), steps, boardId);
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Failed to save: $e');
      return false;
    }
    if (!mounted) return result.success;

    if (!result.success) {
      // The verb carries the ENGINE's own refusal; it is never re-worded into a
      // cause this side cannot know.
      state = state.copyWith(
        error: result.detail.isNotEmpty
            ? result.detail
            : 'The template was refused (${result.error ?? "no reason given"}).',
      );
      return false;
    }
    final saved = result.template!;
    state = state.copyWith(
      clearError: true,
      saveConfirmation: 'Saved “${saved.name}” with ${saved.steps.length} step'
          '${saved.steps.length == 1 ? "" : "s"}'
          '${saved.notes.isEmpty ? "" : " and ${saved.notes.length} standing note"
              "${saved.notes.length == 1 ? "" : "s"}"} — '
          'it is under Your templates.',
    );
    await load();
    return true;
  }

  /// Dismiss the error banner without re-reading anything.
  void clearError() => state = state.copyWith(clearError: true);
}

/// The one-line report a clone leaves: how many step cells landed, which
/// declared plugins are ready, and — LOUDLY — which ones failed, by name.
String cloneReportLine(String? templateName, TemplateCloneOutcome outcome) {
  final steps = outcome.steps;
  final bits = <String>['$steps step${steps == 1 ? "" : "s"} landed'];

  final ready = [
    for (final p in outcome.pluginInstalls)
      if (p.outcome != TemplatePluginInstallOutcome.failed) p.pluginId,
  ];
  if (ready.isNotEmpty) {
    bits.add('${ready.length} plugin${ready.length == 1 ? "" : "s"} ready '
        '(${ready.join(", ")})');
  }
  final failed = [
    for (final p in outcome.pluginInstalls)
      if (p.outcome == TemplatePluginInstallOutcome.failed) p.pluginId,
  ];
  if (failed.isNotEmpty) {
    bits.add('${failed.length} failed (${failed.join(", ")})');
  }
  final prefix =
      (templateName == null || templateName.isEmpty) ? '' : '$templateName: ';
  return prefix + bits.join(' · ');
}
