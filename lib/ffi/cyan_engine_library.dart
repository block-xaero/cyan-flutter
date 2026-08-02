// ffi/cyan_engine_library.dart
//
// Where the Cyan engine binary lives, per target. This is the ONE place that
// knows the engine's file name on each platform — `cyan_bindings.dart` asks it
// for a load plan, and the Windows CMake install rule names the same file
// (windows/CMakeLists.txt). If the two ever disagree the app would silently
// fall through to no-op bindings on Windows, so the windows_target test
// cross-checks them.
//
// The resolver is PURE: it takes the OS name, the home directory and the
// resolved executable path as arguments rather than reading `Platform`, so a
// widget test can ask for every target's plan from a Mac.
//
// It is also TOTAL. There is no `UnsupportedError`, no assertion and no
// unhandled OS: a target the engine has not shipped a binary to yet resolves
// to an empty candidate list plus the process-symbol fallback, which is the
// correct answer for a statically linked engine and a survivable one for a
// target with no engine at all (the bindings degrade to local-only
// fallbacks). Aborting the app because `Platform.operatingSystem` is a string
// this file has not seen would be a platform assertion; the app entrypoint
// must not have one.

/// The ordered attempt list for opening the engine on one target.
class CyanEngineLibraryPlan {
  const CyanEngineLibraryPlan({
    required this.operatingSystem,
    required this.fileName,
    required this.candidatePaths,
    this.processFallback = true,
  });

  /// The `Platform.operatingSystem` value this plan was built for.
  final String operatingSystem;

  /// The engine binary's name on this target, or `''` when the target links
  /// the engine statically and exposes its symbols through the process.
  final String fileName;

  /// Paths to try with `DynamicLibrary.open`, most specific first.
  final List<String> candidatePaths;

  /// Whether to fall back to the already-loaded process symbols once every
  /// candidate has failed. Always true — see the note above.
  final bool processFallback;
}

/// Engine binary naming and lookup, shared by the FFI loader and the tests
/// that keep the native build files honest.
abstract final class CyanEngineLibrary {
  /// macOS ships the engine as the Cyan core dylib, copied into the bundle's
  /// Frameworks directory by the Xcode build.
  static const String macosFileName = 'libcyan_core.dylib';

  /// Windows ships the `cyan-backend` crate's cdylib next to the executable.
  /// MSVC names it after the crate target: `cyan_backend.dll`.
  static const String windowsFileName = 'cyan_backend.dll';

  /// Linux and Android share the ELF name for the same crate target.
  static const String elfFileName = 'libcyan_backend.so';

  /// The engine binary's file name on [operatingSystem], or `''` when that
  /// target has no separate binary to open.
  static String fileNameFor(String operatingSystem) {
    switch (operatingSystem) {
      case 'macos':
        return macosFileName;
      case 'windows':
        return windowsFileName;
      case 'linux':
      case 'android':
        return elfFileName;
      default:
        // iOS links the static library into the app binary; an unrecognised
        // target gets the same treatment rather than an error.
        return '';
    }
  }

  /// The load plan for [operatingSystem].
  ///
  /// [home] is the user's home directory (`$HOME`) and [resolvedExecutable] the
  /// running binary's path — both are used to derive install-relative
  /// candidates. Either may be empty, in which case the candidates that need
  /// them are simply skipped.
  static CyanEngineLibraryPlan resolve(
    String operatingSystem, {
    String home = '',
    String resolvedExecutable = '',
  }) {
    final fileName = fileNameFor(operatingSystem);
    final paths = <String>[];

    switch (operatingSystem) {
      case 'macos':
        // exe is like .../cyan_flutter.app/Contents/MacOS/cyan_flutter
        final marker = resolvedExecutable.lastIndexOf('/MacOS/');
        if (marker > 0) {
          final appDir = resolvedExecutable.substring(0, marker);
          paths.add('$appDir/Frameworks/$fileName');
        }
        if (home.isNotEmpty) {
          paths.add('$home/cyan_flutter/macos/Libraries/$fileName');
        }
        // Static lib linked via the xcframework leaves nothing to open; the
        // process fallback covers that.
        break;

      case 'windows':
        // `flutter build windows` installs the engine beside the runner
        // executable (windows/CMakeLists.txt). Name that copy explicitly so
        // the load does not depend on the DLL search path, then let the plain
        // name catch a system-wide install.
        final exeDir = _parentDirectory(resolvedExecutable);
        if (exeDir.isNotEmpty) paths.add('$exeDir\\$fileName');
        paths.add(fileName);
        break;

      case 'linux':
        // The Linux bundle puts shared libraries in `lib/` next to the binary.
        final exeDir = _parentDirectory(resolvedExecutable);
        if (exeDir.isNotEmpty) {
          paths.add('$exeDir/lib/$fileName');
          paths.add('$exeDir/$fileName');
        }
        paths.add(fileName);
        break;

      case 'android':
        // The NDK loader resolves the plain soname out of the APK's lib dir.
        paths.add(fileName);
        break;

      default:
        // iOS and any target we have not shipped a binary to: process symbols.
        break;
    }

    return CyanEngineLibraryPlan(
      operatingSystem: operatingSystem,
      fileName: fileName,
      candidatePaths: List.unmodifiable(paths),
    );
  }

  /// The directory holding [path], using whichever separator [path] uses.
  /// Empty when [path] has no directory part.
  static String _parentDirectory(String path) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut > 0 ? path.substring(0, cut) : '';
  }
}
