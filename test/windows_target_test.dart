// test/windows_target_test.dart
//
// STAGE face_windows_target — the Windows runner scaffold and the engine
// wiring behind it.
//
// Behaviour spec: scripts/parity_faces/windows_target.txt.
//
// This face has no SwiftUI counterpart to mirror — it is the Windows half of
// what macos/Runner + macos/Libraries/libcyan_core.dylib already give the Mac
// app: a runner that launches, and an engine binary staged where dart:ffi can
// open it. So the oracle is the build files themselves, read from disk, and
// cross-checked against the Dart loader that has to agree with them. A test
// that only asserted "the widget painted" would prove nothing here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/cyan_backend.dart';
import 'package:cyan_flutter/ffi/cyan_backend_ffi.dart';
import 'package:cyan_flutter/ffi/cyan_engine_library.dart';
import 'package:cyan_flutter/main.dart' as entrypoint;

/// A repo file, read relative to the package root (`flutter test`'s cwd).
File _repoFile(String relative) => File(relative);

String _read(String relative) {
  final f = _repoFile(relative);
  expect(f.existsSync(), isTrue, reason: 'missing repo file: $relative');
  return f.readAsStringSync();
}

/// Comment-stripped source, so an assertion about what a file DECLARES is not
/// satisfied by a file that merely mentions it in prose.
String _withoutComments(String source, {required String lineComment}) {
  return source
      .split('\n')
      .map((l) {
        final i = l.indexOf(lineComment);
        return i < 0 ? l : l.substring(0, i);
      })
      .join('\n');
}

void main() {
  group('windows target', () {
    // ---- behaviour 1 --------------------------------------------------------
    test('the windows runner scaffold is present and analyze clean', () {
      // Every file `flutter build windows` needs to configure and link the
      // runner. A missing one is a build that only fails on a Windows box.
      const scaffold = <String>[
        'windows/CMakeLists.txt',
        'windows/flutter/CMakeLists.txt',
        'windows/flutter/generated_plugin_registrant.cc',
        'windows/flutter/generated_plugin_registrant.h',
        'windows/flutter/generated_plugins.cmake',
        'windows/runner/CMakeLists.txt',
        'windows/runner/main.cpp',
        'windows/runner/flutter_window.cpp',
        'windows/runner/flutter_window.h',
        'windows/runner/win32_window.cpp',
        'windows/runner/win32_window.h',
        'windows/runner/utils.cpp',
        'windows/runner/utils.h',
        'windows/runner/resource.h',
        'windows/runner/Runner.rc',
        'windows/runner/runner.exe.manifest',
        'windows/runner/resources/app_icon.ico',
      ];
      for (final path in scaffold) {
        expect(_repoFile(path).existsSync(), isTrue,
            reason: 'windows runner scaffold is missing $path');
      }

      // The runner target must actually compile every source sitting in
      // windows/runner — an orphaned .cpp is an unresolved-symbol link error.
      final runnerCMake = _read('windows/runner/CMakeLists.txt');
      final sources = Directory('windows/runner')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.cpp'))
          .toList();
      expect(sources, isNotEmpty);
      for (final src in sources) {
        expect(runnerCMake, contains('"$src"'),
            reason: '$src is not listed in the runner target');
      }
      // The generated registrant is compiled from the managed dir, not copied.
      expect(runnerCMake,
          contains(r'"${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"'));
      expect(runnerCMake, contains('add_executable(\${BINARY_NAME} WIN32'));

      // Entry point: a WIN32 subsystem executable needs wWinMain, not main.
      expect(_read('windows/runner/main.cpp'), contains('wWinMain'));

      // Every plugin the build links must also be registered at runtime, or
      // the channels silently go dead on Windows only.
      final pluginsCMake = _read('windows/flutter/generated_plugins.cmake');
      final registrant = _read('windows/flutter/generated_plugin_registrant.cc');
      final listed = RegExp(r'FLUTTER_PLUGIN_LIST\s*([^)]*)\)')
              .firstMatch(pluginsCMake)
              ?.group(1)
              ?.split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty && !l.startsWith('#'))
              .toList() ??
          const <String>[];
      expect(listed, isNotEmpty,
          reason: 'no windows plugins listed — the registrant would be empty');
      for (final plugin in listed) {
        expect(registrant, contains('$plugin/'),
            reason: '$plugin is linked but never registered');
      }

      // "analyze clean" means clean, not silenced: the Dart this face owns
      // carries no analyzer suppressions, and nothing hides it from the
      // analyzer either.
      const faceDart = <String>[
        'lib/main.dart',
        'lib/ffi/cyan_engine_library.dart',
        'lib/ffi/cyan_bindings.dart',
      ];
      for (final path in faceDart) {
        final source = _read(path);
        expect(source, isNot(contains('// ignore:')),
            reason: '$path silences an analyzer diagnostic instead of fixing it');
        expect(source, isNot(contains('// ignore_for_file:')),
            reason: '$path silences analyzer diagnostics file-wide');
      }
      expect(_read('analysis_options.yaml'), isNot(contains('exclude:')),
          reason: 'analyze must cover the whole tree, including the ffi loader');
    });

    // ---- behaviour 2 --------------------------------------------------------
    test('the windows CMake configuration names the cyan engine library', () {
      final cmake = _withoutComments(_read('windows/CMakeLists.txt'),
          lineComment: '#');
      final expectedName = CyanEngineLibrary.fileNameFor('windows');
      expect(expectedName, 'cyan_backend.dll');

      // The build names the SAME binary the Dart loader opens. If either side
      // is renamed alone, Windows silently boots into no-op bindings.
      expect(cmake, contains('CYAN_ENGINE_LIBRARY_NAME "$expectedName"'),
          reason: 'windows/CMakeLists.txt must name $expectedName');

      // …and stages it beside the executable, which is where the resolved
      // candidate path points.
      expect(cmake, contains(r'install(FILES "${CYAN_ENGINE_LIBRARY}"'));
      expect(cmake, contains(r'DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"'));
      expect(cmake, contains(r'set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")'),
          reason: 'the lib dir must be the executable dir, not data/');

      final plan = CyanEngineLibrary.resolve('windows',
          resolvedExecutable: r'C:\cyan\cyan_flutter.exe');
      expect(plan.fileName, expectedName);
      expect(plan.candidatePaths.first, r'C:\cyan\cyan_backend.dll',
          reason: 'the loader must look beside the exe, where CMake installs it');
      expect(plan.candidatePaths, contains(expectedName),
          reason: 'a system-wide install must still resolve');

      // A missing engine FAILS THE BUILD. This assertion used to require the
      // opposite — a warning, "same as the Mac, which runs local-only when no
      // dylib is staged" — and that is exactly the reasoning that let macOS ship
      // a six-month-old engine undetected: the binder degrades to no-ops, every
      // screen renders, nothing happens, and the widget suite stays green
      // because it drives FakeCyanBackend.
      //
      // The behaviour this stage owes is "a missing windows dll produces a NAMED
      // ERROR, not a silent no-op". A warning scrolls past in a build log; a
      // customer-facing build with no engine is not shippable.
      expect(cmake, contains('message(FATAL_ERROR'),
          reason: 'a missing engine must fail the Windows build, not warn');
      expect(cmake, contains('cargo build --release --target x86_64-pc-windows-gnu'),
          reason: 'the error must name the command that produces the DLL');
    });

    // ---- behaviour 3 --------------------------------------------------------
    test('the app entrypoint selects a backend without a platform assertion',
        () {
      // The entrypoint HAS a selection seam, and it yields the real adapter.
      final backend = entrypoint.selectCyanBackend();
      expect(backend, isA<CyanBackend>());
      expect(backend, isA<CyanBackendFFI>());

      // …and it is unconditional. A Platform gate or an assert here is exactly
      // what would abort the Windows runner at startup.
      final mainSource =
          _withoutComments(_read('lib/main.dart'), lineComment: '//');
      expect(mainSource, isNot(contains('Platform.is')));
      expect(mainSource, isNot(contains('Platform.operatingSystem')));
      expect(mainSource, isNot(contains('assert(')));
      expect(mainSource, isNot(contains('UnsupportedError')));
      // The selection is what the whole app reads, not a value on the floor.
      expect(mainSource, contains('cyanBackendProvider.overrideWithValue('));

      // The load plan behind it is TOTAL: every target resolves, none throws.
      const targets = <String>[
        'macos',
        'windows',
        'linux',
        'android',
        'ios',
        'fuchsia',
        'some-future-target',
      ];
      for (final os in targets) {
        final plan = CyanEngineLibrary.resolve(os,
            home: '/Users/rick',
            resolvedExecutable: '/Users/rick/app/cyan_flutter');
        expect(plan.operatingSystem, os);
        expect(plan.processFallback, isTrue,
            reason: '$os must degrade to process symbols, not abort');
      }

      // Targets that ship a binary name one; the rest fall straight through to
      // the process symbols rather than erroring.
      expect(CyanEngineLibrary.resolve('windows').fileName, 'cyan_backend.dll');
      expect(CyanEngineLibrary.resolve('linux').fileName, 'libcyan_backend.so');
      expect(CyanEngineLibrary.resolve('macos').fileName, 'libcyan_core.dylib');
      expect(CyanEngineLibrary.resolve('ios').candidatePaths, isEmpty);
      expect(CyanEngineLibrary.resolve('some-future-target').candidatePaths,
          isEmpty);

      // The loader itself no longer carries the unsupported-platform throw the
      // old macOS-first branch ended in.
      final bindings = _withoutComments(_read('lib/ffi/cyan_bindings.dart'),
          lineComment: '//');
      expect(bindings, isNot(contains('UnsupportedError')),
          reason: 'an unknown OS must not abort the engine load');
      expect(bindings, contains('CyanEngineLibrary.resolve('));

      // macOS keeps the bundle-then-source lookup it had before this face.
      final macPlan = CyanEngineLibrary.resolve('macos',
          home: '/Users/rick',
          resolvedExecutable:
              '/Apps/cyan_flutter.app/Contents/MacOS/cyan_flutter');
      expect(macPlan.candidatePaths, [
        '/Apps/cyan_flutter.app/Contents/Frameworks/libcyan_core.dylib',
        '/Users/rick/cyan_flutter/macos/Libraries/libcyan_core.dylib',
      ]);
    });
  });
}
