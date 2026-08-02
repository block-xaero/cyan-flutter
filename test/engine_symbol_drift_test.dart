// engine_symbol_drift_test.dart
//
// THE TEST THAT SHOULD HAVE EXISTED SIX MONTHS AGO.
//
// What happened: cyan-backend removed the `cyan_integration_*` FFI symbols when
// integrations moved to MCP servers. iOS deleted its declarations in the same
// change — it had to, "or the app won't link". Flutter's binder is resolved at
// RUNTIME, so nothing forced the same cleanup, and five dead names sat in
// cyan_bindings.dart. `_bindAllUnsafe` binds all 155 verbs inside one try block,
// so the first dead lookup threw and every verb fell back to a no-op.
//
// The result: the Flutter app ran COMPLETELY INERT against a perfectly healthy
// engine. Every screen rendered. Every button responded. Nothing was written.
// And 296 widget tests stayed green throughout, because they drive
// FakeCyanBackend and never touch this file.
//
// A static drift check is what catches this. It needs no app, no engine boot and
// no device — just the binder's own list and the symbols in the staged library.
// Runtime FFI has no linker; this test is the linker.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The library the app actually opens on this platform.
File _stagedEngine() {
  final root = Directory.current.path;
  if (Platform.isMacOS) return File('$root/macos/Libraries/libcyan_core.dylib');
  if (Platform.isWindows) return File('$root/windows/Libraries/cyan_backend.dll');
  return File('$root/linux/Libraries/libcyan_backend.so');
}

/// Symbols the engine exports, read from the binary rather than from a list
/// somebody maintains by hand — a hand-maintained list is the bug being tested.
Set<String> _exported(File lib) {
  final tools = Platform.isMacOS
      ? [
          ['nm', ['-gU', lib.path]],
        ]
      : [
          ['llvm-nm', ['--extern-only', '--defined-only', lib.path]],
          ['nm', ['--extern-only', '--defined-only', lib.path]],
        ];
  for (final t in tools) {
    try {
      final r = Process.runSync(t[0] as String, t[1] as List<String>);
      if (r.exitCode == 0) {
        return RegExp(r'cyan_[a-z0-9_]+')
            .allMatches(r.stdout.toString())
            .map((m) => m.group(0)!)
            .toSet();
      }
    } catch (_) {/* try the next tool */}
  }
  fail('could not read symbols from ${lib.path} — no working nm on this host');
}

/// The names the binder looks up, parsed from the binder itself. Reading the
/// source rather than importing it keeps this honest: the const list inside
/// cyan_bindings.dart is only trustworthy if it matches the real lookups, and
/// this checks both against the binary.
({Set<String> lookups, Set<String> declared}) _binder() {
  final src = File('${Directory.current.path}/lib/ffi/cyan_bindings.dart')
      .readAsStringSync();
  final lookups = RegExp(r"lookupFunction<[^>]*>\('(cyan_[a-z0-9_]+)'\)")
      .allMatches(src)
      .map((m) => m.group(1)!)
      .toSet();
  final listBody =
      RegExp(r'const List<String> _requiredSymbols = <String>\[(.*?)\];', dotAll: true)
          .firstMatch(src);
  final declared = listBody == null
      ? <String>{}
      : RegExp(r"'(cyan_[a-z0-9_]+)'")
          .allMatches(listBody.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
  return (lookups: lookups, declared: declared);
}

void main() {
  group('engine symbol drift', () {
    test('every symbol the binder looks up exists in the staged engine', () {
      final lib = _stagedEngine();
      expect(lib.existsSync(), isTrue,
          reason: 'no engine staged at ${lib.path}. The app cannot be built '
              'without it either — both platforms now fail the build — so build '
              'it: cargo build --release --lib (macOS) or --target '
              'x86_64-pc-windows-gnu (Windows).');

      final exported = _exported(lib);
      expect(exported, isNotEmpty, reason: 'read no cyan_* symbols from ${lib.path}');

      final wanted = _binder().lookups;
      final phantom = wanted.difference(exported).toList()..sort();

      expect(
        phantom,
        isEmpty,
        reason: 'the binder looks up ${phantom.length} symbol(s) the engine does '
            'not export: ${phantom.join(', ')}.\n'
            'Runtime FFI has no linker, so nothing else catches this — the first '
            'missing lookup throws inside _bindAllUnsafe and EVERY verb becomes a '
            'no-op. The app then renders normally and does nothing at all.\n'
            'Either delete them from cyan_bindings.dart (as iOS did when the '
            'engine dropped cyan_integration_*) or add them to the engine.',
      );
    });

    test('the pre-flight list matches what the binder actually looks up', () {
      final b = _binder();
      expect(b.declared, isNotEmpty,
          reason: '_requiredSymbols is missing or empty — the pre-flight check '
              'in _bindFunctions would then verify nothing');
      expect(
        b.declared,
        equals(b.lookups),
        reason: 'the pre-flight list and the real lookups have diverged. The '
            'pre-flight exists to report EVERY missing symbol instead of dying '
            'on the first one; a stale list quietly stops covering the gap.',
      );
    });

    // A guard on the guard. If the engine ever stops exporting most of its
    // surface the test above still passes when the binder shrank in step, so
    // anchor the absolute number too — a stale February dylib had 88.
    test('the staged engine exposes the full verb surface', () {
      final exported = _exported(_stagedEngine())
          .where((s) => s != 'cyan_backend') // PE export tables name the module
          .toSet();
      expect(exported.length, greaterThanOrEqualTo(150),
          reason: 'the staged engine exports only ${exported.length} verbs. It '
              'is stale — rebuild it from cyan-backend.');
    });
  });
}
