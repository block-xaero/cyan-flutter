// real_engine_test.dart — TIER 2. The REAL engine, not FakeCyanBackend.
//
// Every one of the 296 widget tests drives FakeCyanBackend. That proves the UI
// wiring and says NOTHING about whether the engine is reached. Worse, the binder
// degrades silently: `_lookupInit` returns null on a failed lookup and the app
// "falls back to no-ops when the symbols are absent" — so a customer with a
// missing or mismatched dylib gets an app that LOOKS like it works and does
// nothing at all.
//
// This tier loads the real libcyan_backend, initialises a real SQLite database in
// a temp dir, and asserts STATE ACTUALLY CHANGED. It is the difference between
// "the port is wired" and "the port works".
//
//   flutter test integration_test/real_engine_test.dart

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

typedef _InitN = Bool Function(Pointer<Utf8>);
typedef _InitD = bool Function(Pointer<Utf8>);
typedef _StrRetN = Pointer<Utf8> Function();
typedef _StrRetD = Pointer<Utf8> Function();
typedef _Str1N = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _Str1D = Pointer<Utf8> Function(Pointer<Utf8>);

/// Resolve the engine the way the APP does, not the way a test wishes it would.
/// macOS ships libcyan_core.dylib in Contents/Frameworks and OPENS it; the
/// process fallback is only for a statically linked build and is exactly the
/// path that silently degrades to no-ops when the dylib is missing. Asserting
/// against the real bundled artifact is the whole point of this tier.
DynamicLibrary _engine() {
  if (Platform.isWindows) {
    // Windows: the runner ships the DLL beside the exe; in `flutter test -d
    // windows` the staged copy under windows/Libraries is the build input.
    final exeDir = File(Platform.resolvedExecutable).parent;
    for (final candidate in [
      File('${exeDir.path}/cyan_backend.dll'),
      File('${Directory.current.path}/windows/Libraries/cyan_backend.dll'),
    ]) {
      if (candidate.existsSync()) return DynamicLibrary.open(candidate.path);
    }
    fail('no cyan_backend.dll beside the runner or under windows/Libraries — '
        'the app would fall back to process symbols and silently no-op.');
  }
  final exe = File(Platform.resolvedExecutable).parent; // …/Contents/MacOS
  final bundled =
      File('${exe.parent.path}/Frameworks/libcyan_core.dylib');
  if (bundled.existsSync()) return DynamicLibrary.open(bundled.path);
  fail('no engine at ${bundled.path} — the app would fall back to process '
      'symbols and silently no-op. The Embed Cyan Engine build phase did not run.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late DynamicLibrary lib;
  late Directory tmp;

  setUpAll(() {
    lib = _engine();
    tmp = Directory.systemTemp.createTempSync('cyan_tier2_');
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  // THE POINT OF THIS FILE. A silent no-op fallback is the production hazard:
  // the app must reach a REAL symbol, not a null-degraded stub.
  test('the real engine symbols resolve — no silent no-op fallback', () {
    for (final sym in [
      'cyan_init',
      'cyan_create_group',
      'cyan_get_workspaces_for_group',
      'cyan_pipeline_compile',
      'cyan_run_pipeline',
    ]) {
      expect(
        () => lib.lookup<NativeFunction<Void Function()>>(sym),
        returnsNormally,
        reason: 'engine symbol $sym did not resolve — the app would degrade to '
            'no-ops and appear to work while doing nothing',
      );
    }
  });

  test('cyan_init opens a real database on disk', () {
    final init = lib.lookupFunction<_InitN, _InitD>('cyan_init');
    final dbPath = '${tmp.path}/cyan.db';
    final p = dbPath.toNativeUtf8();
    final ok = init(p);
    calloc.free(p);
    expect(ok, isTrue, reason: 'cyan_init refused to open $dbPath');
    expect(File(dbPath).existsSync(), isTrue,
        reason: 'cyan_init returned true but wrote no database — that is a '
            'no-op masquerading as success');
  });

  // THE REGRESSION GUARD. The app shipped a SIX-MONTH-OLD engine for months:
  // libcyan_core.dylib was hand-placed into build/ once in February and nothing
  // in the build ever refreshed it, so 72 of 155 verbs — the whole pipeline and
  // notes clusters — were absent and every call silently no-opped. Counting the
  // verbs in the BUNDLED artifact is what makes that impossible to repeat.
  //
  // NOTE: driving state through the engine (create a group, read it back) needs
  // identity/tenant setup that a bare cyan_init does not do — calling it on an
  // uninitialised engine hard-crashes the process. That is engine behaviour and
  // belongs in its own test, not here.
  test('the bundled engine exposes the FULL verb surface, not a stale subset', () {
    const expectedAtLeast = 150; // engine ships 155; a stale build had 88
    var found = 0;
    for (final v in _knownVerbs) {
      try {
        lib.lookup<NativeFunction<Void Function()>>(v);
        found++;
      } catch (_) {}
    }
    expect(found, greaterThanOrEqualTo(expectedAtLeast),
        reason: 'only $found of ${_knownVerbs.length} engine verbs resolved in the '
            'bundled dylib — it is STALE. Rebuild macos/Libraries/libcyan_core.dylib '
            'from cyan-backend and confirm the Embed Cyan Engine phase ran.');
  });
}

/// The engine's exported verb surface, captured from the built dylib.
/// If the engine gains verbs this list is stale — regenerate with:
///   nm -gU <libcyan_backend.dylib> | grep -oE '_cyan_[a-z0-9_]+' | sed 's/^_//' | sort -u
const _knownVerbs = <String>[
  'cyan_act_on_timecode_note',
  'cyan_add_board_label',
  'cyan_ai_command',
  'cyan_autocomplete_path',
  'cyan_board_review_assignee',
  'cyan_board_set_review_assignee',
  'cyan_board_video_media',
  'cyan_board_workflow_state',
  'cyan_build_commit',
  'cyan_bundle_pubkey',
  'cyan_changelist_command',
  'cyan_clear_whiteboard',
  'cyan_constitution_effective',
  'cyan_constitution_resolved',
  'cyan_create_anonymous_session',
  'cyan_create_board',
  'cyan_create_group',
  'cyan_create_workspace',
  'cyan_delete_board',
  'cyan_delete_chat',
  'cyan_delete_file',
  'cyan_delete_group',
  'cyan_delete_identity',
  'cyan_delete_notebook_cell',
  'cyan_delete_whiteboard_element',
  'cyan_delete_workspace',
  'cyan_exit_anonymous_mode',
  'cyan_export_group',
  'cyan_export_notes_markdown',
  'cyan_extract_file_text',
  'cyan_free_string',
  'cyan_friendly_node_id',
  'cyan_get_all_boards',
  'cyan_get_all_peers',
  'cyan_get_anonymous_status',
  'cyan_get_board_link',
  'cyan_get_board_metadata',
  'cyan_get_board_mode',
  'cyan_get_boards_for_group',
  'cyan_get_boards_for_workspace',
  'cyan_get_boards_metadata',
  'cyan_get_file_local_path',
  'cyan_get_file_status',
  'cyan_get_files',
  'cyan_get_group_members',
  'cyan_get_group_peer_count',
  'cyan_get_group_peers',
  'cyan_get_my_node_id',
  'cyan_get_my_profile',
  'cyan_get_node_id',
  'cyan_get_object_count',
  'cyan_get_production_role',
  'cyan_get_profiles_batch',
  'cyan_get_top_boards',
  'cyan_get_total_peer_count',
  'cyan_get_user_profile',
  'cyan_get_whiteboard_element_count',
  'cyan_get_workspaces_for_group',
  'cyan_get_xaero_id',
  'cyan_import_group',
  'cyan_ingest_command',
  'cyan_init',
  'cyan_init_with_identity',
  'cyan_install_plugin_bundle',
  'cyan_is_board_owner',
  'cyan_is_board_pinned',
  'cyan_is_group_owner',
  'cyan_is_ready',
  'cyan_is_workspace_owner',
  'cyan_issue_grant_qr',
  'cyan_leave_board',
  'cyan_leave_group',
  'cyan_leave_workspace',
  'cyan_load_cell_elements',
  'cyan_load_chat_history',
  'cyan_load_notebook_cells',
  'cyan_load_timecode_notes',
  'cyan_load_whiteboard_elements',
  'cyan_mark_read',
  'cyan_note_delete',
  'cyan_note_list',
  'cyan_note_list_scoped',
  'cyan_note_put',
  'cyan_note_put_scoped',
  'cyan_parse_lens_command',
  'cyan_pin_board',
  'cyan_pin_set',
  'cyan_pin_summary_as_board',
  'cyan_pipeline_approve',
  'cyan_pipeline_approve_as',
  'cyan_pipeline_compile',
  'cyan_pipeline_reject',
  'cyan_pipeline_reject_as',
  'cyan_pipeline_reset',
  'cyan_pipeline_reset_step',
  'cyan_pipeline_retry',
  'cyan_pipeline_run_step_local',
  'cyan_pipeline_status',
  'cyan_plugin_catalog',
  'cyan_plugin_config_get',
  'cyan_plugin_config_set',
  'cyan_poll_ai_insights',
  'cyan_poll_ai_response',
  'cyan_poll_events',
  'cyan_rate_board',
  'cyan_record_board_view',
  'cyan_remove_board_label',
  'cyan_rename_board',
  'cyan_rename_group',
  'cyan_rename_workspace',
  'cyan_reorder_notebook_cells',
  'cyan_request_file_download',
  'cyan_resolve_file_handle',
  'cyan_reveal_anonymous_identity',
  'cyan_review_add_comment',
  'cyan_review_command',
  'cyan_run_pipeline',
  'cyan_save_notebook_cell',
  'cyan_save_timecode_note',
  'cyan_save_whiteboard_element',
  'cyan_scan_grant_qr',
  'cyan_search_boards_by_label',
  'cyan_seed_demo',
  'cyan_seed_demo_if_empty',
  'cyan_seed_personas',
  'cyan_selector_resolve',
  'cyan_send_chat',
  'cyan_send_command',
  'cyan_send_direct_chat',
  'cyan_set_board_labels',
  'cyan_set_board_mode',
  'cyan_set_board_model',
  'cyan_set_board_skills',
  'cyan_set_data_dir',
  'cyan_set_discovery_key',
  'cyan_set_my_profile',
  'cyan_set_production_role',
  'cyan_set_xaero_id',
  'cyan_sso_install_grant',
  'cyan_sso_sign_out',
  'cyan_start_direct_chat',
  'cyan_step_edit_travel',
  'cyan_template_clone_outcome',
  'cyan_template_list',
  'cyan_template_save',
  'cyan_template_save_from_board',
  'cyan_template_save_v2',
  'cyan_unpin_board',
  'cyan_unread_counts',
  'cyan_update_peer_status',
  'cyan_upload_file',
  'cyan_upload_file_to_group',
  'cyan_upload_file_to_workspace',
  'cyan_workflow_autocomplete',
  'cyan_workflow_from_template',
];
