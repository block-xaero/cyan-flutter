// engine_roundtrip_test.dart — TIER 2, the half `real_engine_test.dart` parked.
//
// That file proves the engine LOADS and exposes all 155 verbs. Necessary, and
// not sufficient: a verb that resolves can still be a no-op. It said so itself —
//
//   "driving state through the engine (create a group, read it back) needs
//    identity/tenant setup that a bare cyan_init does not do"
//
// It does, and this file does it. `cyan_init_with_identity` boots the real
// engine — identity, command runtime, SQLite — and then we WRITE through FFI and
// READ BACK through FFI, asserting the value survived the round trip. That is
// the difference between "the port is wired" and "the port works", and it is the
// only evidence that answers "is Flutter at parity when you actually drive it".
//
// TWO INDEPENDENT READ PATHS, deliberately. The engine surfaces state two ways
// and this file uses both:
//
//   * `cyan_poll_events` — the event buffer the app drains to build its tree.
//     There is no verb that lists groups; this IS how the group list is
//     populated, so testing it tests the real path.
//   * `cyan_get_workspaces_for_group` — a direct `SELECT … FROM workspaces`.
//
// Asserting they AGREE is what makes this more than a self-consistency check: an
// engine that emitted events but never wrote, or wrote but never emitted, fails.
// (The first draft shelled out to the sqlite3 CLI as the second witness. The
// macOS app is sandboxed — Process.runSync gives "Operation not permitted" — and
// these two engine paths are a better witness anyway, because both are paths the
// product actually runs on.)
//
// SEPARATE FILE ON PURPOSE. `SYSTEM` in the engine is a OnceCell: the first init
// in a process wins and every later one silently returns true against the FIRST
// database. real_engine_test.dart calls `cyan_init`, so a round trip appended
// there would write to that test's db and read from this one's — passing or
// failing for reasons that have nothing to do with the engine. Flutter runs each
// integration_test file in its own process, so the isolation is real.
//
//   flutter test integration_test/engine_roundtrip_test.dart -d macos

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

typedef _InitIdN = Bool Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _InitIdD = bool Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Void3N = Void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Void3D = void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>);
typedef _Void2N = Void Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Void2D = void Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Str1N = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _Str1D = Pointer<Utf8> Function(Pointer<Utf8>);

late DynamicLibrary _lib;

/// Resolve the engine the way the APP does — the bundled artifact, not a
/// convenient one. See real_engine_test.dart for why the process fallback is a
/// hazard rather than a safety net.
DynamicLibrary _engine() {
  final exe = File(Platform.resolvedExecutable).parent; // …/Contents/MacOS
  final bundled = File('${exe.parent.path}/Frameworks/libcyan_core.dylib');
  if (bundled.existsSync()) return DynamicLibrary.open(bundled.path);
  fail('no engine at ${bundled.path} — the Embed Cyan Engine build phase did '
      'not run, and the app would degrade to no-ops.');
}

/// Every event the engine has emitted to the `file_tree` component so far.
///
/// The buffer is DESTRUCTIVE — `cyan_poll_events` pops — so a test that polled
/// directly would consume events a later test needs. Everything drained here is
/// kept, and callers filter this list instead of racing each other for it.
final List<Map<String, dynamic>> _seen = [];

void _drain() {
  final poll = _lib.lookupFunction<_Str1N, _Str1D>('cyan_poll_events');
  final comp = 'file_tree'.toNativeUtf8();
  while (true) {
    final p = poll(comp);
    if (p == nullptr) break;
    try {
      final ev = jsonDecode(p.toDartString()) as Map<String, dynamic>;
      final data = ev['data'];
      if (data is Map<String, dynamic>) _seen.add(data);
    } catch (_) {/* a malformed event is not what this file is testing */}
  }
  calloc.free(comp);
}

/// The engine's writes are ASYNCHRONOUS: `cyan_create_group` returns void and
/// hands a `CommandMsg` to the runtime. A fixed sleep would be either flaky or
/// slow, so poll for the effect and name what never arrived when it times out.
Map<String, dynamic> _awaitEvent(
  String describe,
  bool Function(Map<String, dynamic>) matches, {
  Duration limit = const Duration(seconds: 20),
}) {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    _drain();
    for (final e in _seen) {
      if (matches(e)) return e;
    }
    sleep(const Duration(milliseconds: 100));
  }
  fail('$describe never arrived within ${limit.inSeconds}s. The FFI call '
      'returned, but the engine emitted nothing — that is a no-op wearing a '
      'void return. Events seen: ${_seen.map((e) => e['type']).toSet()}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  String? groupId;

  setUpAll(() {
    _lib = _engine();
    tmp = Directory.systemTemp.createTempSync('cyan_roundtrip_');

    // A throwaway identity in a throwaway directory. Nothing here touches the
    // developer's real ~/.cyan data — this suite must never be able to damage
    // a working install.
    final p = '${tmp.path}/cyan.db'.toNativeUtf8();
    final key = List.filled(64, 'a').join().toNativeUtf8();
    final relay = ''.toNativeUtf8();
    final disco = 'cyan-roundtrip-test'.toNativeUtf8();
    final ok = _lib.lookupFunction<_InitIdN, _InitIdD>('cyan_init_with_identity')(
        p, key, relay, disco);
    calloc.free(p);
    calloc.free(key);
    calloc.free(relay);
    calloc.free(disco);

    expect(ok, isTrue, reason: 'the engine refused to boot with an identity');
    expect(File('${tmp.path}/cyan.db').existsSync(), isTrue,
        reason: 'boot returned true but wrote no database');
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {/* the engine may still hold the WAL; the temp dir is disposable */}
  });

  // ── behaviour: creating a group through the engine changes persisted state ──
  test('creating a group through the engine changes persisted state', () {
    const name = 'RoundTripGroup';

    final n = name.toNativeUtf8();
    final i = 'folder.fill'.toNativeUtf8();
    final c = '#00AEEF'.toNativeUtf8();
    _lib.lookupFunction<_Void3N, _Void3D>('cyan_create_group')(n, i, c);
    calloc.free(n);
    calloc.free(i);
    calloc.free(c);

    final ev = _awaitEvent('GroupCreated for "$name"',
        (e) => e['type'] == 'GroupCreated' && e['name'] == name);

    groupId = ev['id'] as String;

    // A real content-addressed id, not a placeholder the UI invented.
    expect(groupId, hasLength(64),
        reason: 'expected a 64-char engine-generated id, got "$groupId"');
    // The engine echoed back what we wrote rather than defaulting it away.
    expect(ev['color'], '#00AEEF');
    expect(ev['icon'], 'folder.fill');
  });

  // ── behaviour: reading the tree back returns what was written ───────────────
  test('reading the tree back returns what was written', () {
    final gid = groupId;
    expect(gid, isNotNull,
        reason: 'the group step did not run or did not produce an id');

    const ws = 'RoundTripWorkspace';
    final g = gid!.toNativeUtf8();
    final w = ws.toNativeUtf8();
    _lib.lookupFunction<_Void2N, _Void2D>('cyan_create_workspace')(g, w);
    calloc.free(w);

    final ev = _awaitEvent('WorkspaceCreated for "$ws"',
        (e) => e['type'] == 'WorkspaceCreated' && e['name'] == ws);
    final wsId = ev['id'] as String;
    expect(ev['group_id'], gid,
        reason: 'the workspace was filed under the wrong group');

    // Now the read that matters: ask the ENGINE, through FFI, what this group
    // holds. This is the exact call the Flutter tree view makes, and it is a
    // SELECT against SQLite — a different path from the event buffer above.
    final read = _lib.lookupFunction<_Str1N, _Str1D>('cyan_get_workspaces_for_group');
    final ids = (jsonDecode(read(g).toDartString()) as List).cast<String>();
    calloc.free(g);

    expect(ids, contains(wsId),
        reason: 'the engine announced workspace $wsId but does not return it '
            'from cyan_get_workspaces_for_group — the read path is broken, and '
            'the tree would render empty over a database that has the data');

    // THE CROSS-CHECK. Creating a group provisions General and Plugins
    // alongside it, so this group holds three workspaces, not one. Comparing
    // the FULL set the SQL read returns against the full set the event bus
    // announced is what catches one path silently losing or inventing a row —
    // "mine is in there" would not.
    final announced = _seen
        .where((e) => e['type'] == 'WorkspaceCreated' && e['group_id'] == gid)
        .map((e) => e['id'] as String)
        .toSet();
    expect(ids.toSet(), equals(announced),
        reason: 'the two read paths disagree: SQL returned ${ids.length} '
            'workspaces, the event bus announced ${announced.length}. One of '
            'them is lying about what the engine stored.');
  });
}
