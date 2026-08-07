// engine_arity_drift_test.dart
//
// THE SECOND HALF OF THE LINKER.
//
// engine_symbol_drift_test.dart asks "does the engine export this NAME?" and a
// PE export table can answer that. It cannot answer "and does it take the
// arguments we are about to push", because a C export carries no signature. So
// the names all matched while SEVEN verbs were called with the wrong shape:
//
//   cyan_save_notebook_cell(cell_json)         called as (board_id, cell_json)
//   cyan_delete_notebook_cell(cell_id)         called as (board_id, cell_id)
//   cyan_save_whiteboard_element(element_json) called as (board_id, element_json)
//   cyan_delete_whiteboard_element(element_id) called as (board_id, element_id)
//   cyan_get_boards_metadata(scope_type, id)   called as (board_ids_json)
//   cyan_get_top_boards(group_id, limit)       called as (limit)
//   cyan_send_direct_chat(peer, ws, msg, parent) -> ()  called as (peer, msg) -> bool
//
// The notebook pair is why the Workflow author face could not author: the
// engine parsed the BOARD ID as the cell JSON, failed, and returned false —
// every step the operator wrote was dropped, silently, forever. The last two
// are worse than wrong: they hand the engine an integer to dereference as a
// string pointer and read a bool out of a function that returns nothing.
//
// Nothing catches this. Dart FFI resolves by name at runtime and trusts the
// declared signature completely; the C ABI lets a caller push too few arguments
// and the callee reads whatever was in the register. There is no linker. This
// test is the linker.
//
// It reads the ENGINE'S OWN SOURCE — the `pub extern "C" fn` signatures in
// cyan-backend — and compares them to the typedefs cyan_bindings.dart declares.
// Source, not binary, because the arity only exists in the source.
//
// WHAT IT DOES NOT CATCH, said plainly so nobody trusts it further than it
// goes: it compares the NUMBER of parameters and whether the verb returns
// anything. It does not compare parameter ORDER or types. `cyan_upload_file_to_group`
// was declared with its two pointers the wrong way round and the count matched
// perfectly — only its void return gave it away. A binding with the right
// count, the right return and the wrong order still gets through here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The engine's FFI source, checked out beside this repo (`C:\cyan\…`,
/// `~/cyan/…` — the layout both machines use).
Directory _engineFfiSources() {
  final here = Directory.current.path.replaceAll('\\', '/');
  final parent = here.substring(0, here.lastIndexOf('/'));
  return Directory('$parent/cyan-backend/src/ffi');
}

/// `name -> (params, returnsValue)` for every `pub extern "C" fn cyan_*`.
Map<String, ({int params, bool returnsValue})> _engineSignatures(Directory dir) {
  final out = <String, ({int params, bool returnsValue})>{};
  final re = RegExp(
      r'pub extern "C" fn (cyan_[a-z0-9_]+)\s*\(([^)]*)\)\s*(->\s*[^{]+?)?\s*\{',
      dotAll: true);
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.rs')) continue;
    for (final m in re.allMatches(f.readAsStringSync())) {
      out[m.group(1)!] = (
        params: _count(m.group(2)!),
        returnsValue: (m.group(3) ?? '').trim().isNotEmpty,
      );
    }
  }
  return out;
}

/// `symbol -> (params, returnsValue)` as the binder DECLARES them: the native
/// typedef named in each `lookupFunction`, not a list kept beside it.
Map<String, ({int params, bool returnsValue})> _binderSignatures() {
  final src = File('${Directory.current.path}/lib/ffi/cyan_bindings.dart')
      .readAsStringSync();

  final typedefs = <String, ({int params, bool returnsValue})>{};
  final tRe = RegExp(
      r'typedef\s+(\w+Native)\s*=\s*([\w<>]+)\s+Function\(([^;]*?)\)\s*;',
      dotAll: true);
  for (final m in tRe.allMatches(src)) {
    typedefs[m.group(1)!] = (
      params: _count(m.group(3)!),
      returnsValue: m.group(2)!.trim() != 'Void',
    );
  }

  final out = <String, ({int params, bool returnsValue})>{};
  final bRe =
      RegExp(r"lookupFunction<\s*(\w+)\s*,\s*\w+\s*>\('(cyan_[a-z0-9_]+)'\)");
  for (final m in bRe.allMatches(src)) {
    final t = typedefs[m.group(1)!];
    if (t != null) out[m.group(2)!] = t;
  }
  return out;
}

/// Parameters in a comma-separated list, tolerating a trailing comma (Rust
/// writes one on every wrapped signature, and counting it as an argument is how
/// a naive scan invents forty false mismatches).
int _count(String args) {
  final trimmed = args.trim().replaceAll(RegExp(r',\s*$'), '');
  if (trimmed.isEmpty) return 0;
  return trimmed.split(',').where((a) => a.trim().isNotEmpty).length;
}

void main() {
  group('engine arity drift', () {
    final dir = _engineFfiSources();

    test('every bound verb is called with the arguments the engine declares',
        () {
      if (!dir.existsSync()) {
        // Loud, like the platform-specific goldens: a machine without the
        // engine source beside this repo cannot run the check, and must say so
        // rather than report a pass it did not earn.
        markTestSkipped(
            'no engine source at ${dir.path} — check out cyan-backend beside '
            'cyan_flutter to run the arity check. NOTHING was verified here.');
        return;
      }

      final engine = _engineSignatures(dir);
      expect(engine, isNotEmpty,
          reason: 'parsed no `pub extern "C" fn cyan_*` out of ${dir.path}');

      final binder = _binderSignatures();
      expect(binder, isNotEmpty,
          reason: 'parsed no lookupFunction bindings out of cyan_bindings.dart '
              '— the scan is broken, not the binder');

      final drift = <String>[];
      for (final entry in binder.entries) {
        final want = engine[entry.key];
        // A symbol the engine does not export at all is the OTHER test's job
        // (engine_symbol_drift_test.dart reads the shipped binary); skipping it
        // here keeps one failure from being reported as two.
        if (want == null) continue;
        if (want.params != entry.value.params) {
          drift.add('${entry.key}: the binder declares ${entry.value.params} '
              'argument(s), the engine takes ${want.params}');
        }
        if (want.returnsValue != entry.value.returnsValue) {
          drift.add('${entry.key}: the binder declares '
              '${entry.value.returnsValue ? "a return value" : "void"}, the '
              'engine returns ${want.returnsValue ? "a value" : "nothing"}');
        }
      }

      expect(
        drift..sort(),
        isEmpty,
        reason: 'the binder and the engine disagree about how these verbs are '
            'called:\n  ${drift.join('\n  ')}\n'
            'Dart FFI resolves by NAME and trusts the declared signature, and '
            'the C ABI lets a caller push too few arguments — so nothing else '
            'catches this. Too few and the engine reads uninitialised '
            'registers; wrong order and it parses a board id as JSON and '
            'refuses every write while the UI reports success.',
      );
    });

    test('the scan itself still finds both sides', () {
      if (!dir.existsSync()) {
        markTestSkipped('no engine source at ${dir.path}');
        return;
      }
      // A regex that silently stops matching would turn this whole file into a
      // test that passes by finding nothing. Anchor both counts.
      expect(_engineSignatures(dir).length, greaterThanOrEqualTo(150),
          reason: 'the engine exports ~157 verbs; parsing far fewer means the '
              'signature regex has drifted, not the engine');
      expect(_binderSignatures().length, greaterThanOrEqualTo(150),
          reason: 'the binder looks up ~155 verbs; parsing far fewer means the '
              'typedef/lookup regex has drifted');
    });
  });
}
