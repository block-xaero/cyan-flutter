// engine_unavailable_screen.dart
//
// What the app shows INSTEAD of itself when the Cyan engine could not be loaded.
//
// The alternative — the one that shipped for six months on macOS — is to start
// normally with every engine verb replaced by a no-op. That app renders every
// screen, accepts every click, and silently discards everything. A person cannot
// tell it apart from a working build until their work is gone.
//
// A blocking screen is not a nicety here. It is the difference between "this
// build is broken" and "your work vanished and nobody knows why".
//
// It is a screen rather than a hard exit deliberately: a process that dies at
// launch tells the person nothing, and on Windows it dies before any console
// exists to read. This states the fault and the fix, on screen, where whoever is
// holding the broken build will actually see it.

import 'package:flutter/material.dart';

class EngineUnavailableApp extends StatelessWidget {
  const EngineUnavailableApp({
    super.key,
    required this.reason,
    required this.triedPaths,
  });

  /// What the loader reported — a missing library, or a symbol that would not bind.
  final String reason;

  /// Every location the resolver looked, in order. "Could not load the engine"
  /// is unactionable; the list of paths is the actual diagnostic.
  final List<String> triedPaths;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cyan — engine unavailable',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1B1D1E),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cyan cannot start',
                    key: Key('engine_unavailable_title'),
                    style: TextStyle(
                      color: Color(0xFFF92672),
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'The Cyan engine could not be loaded. The app has stopped '
                    'rather than opening, because without the engine every '
                    'action would appear to succeed and nothing would be saved.',
                    style: TextStyle(
                        color: Color(0xFFCFD0C2), fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  _Label('What went wrong'),
                  _Mono(reason, key: const Key('engine_unavailable_reason')),
                  const SizedBox(height: 22),
                  _Label('Where it looked'),
                  if (triedPaths.isEmpty)
                    _Mono('No candidate paths for this platform.')
                  else
                    ...triedPaths.map((p) => _Mono(p)),
                  const SizedBox(height: 22),
                  _Label('How to fix it'),
                  _Mono('macOS    cargo build --release --lib\n'
                      '         → macos/Libraries/libcyan_core.dylib'),
                  const SizedBox(height: 8),
                  _Mono('Windows  cargo build --release '
                      '--target x86_64-pc-windows-gnu --lib\n'
                      '         → windows/Libraries/cyan_backend.dll'),
                  const SizedBox(height: 8),
                  const Text(
                    'Then rebuild the app. Both platforms fail the build when '
                    'the engine is missing, so a build that produced this screen '
                    'was made before that guard existed.',
                    style: TextStyle(
                        color: Color(0xFF75715E), fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF66D9EF),
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _Mono extends StatelessWidget {
  const _Mono(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF232526),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(
          text,
          style: const TextStyle(
            color: Color(0xFFE6DB74),
            fontFamily: 'monospace',
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
      );
}
