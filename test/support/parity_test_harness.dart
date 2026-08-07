// test/support/parity_test_harness.dart
//
// Tier-1 test harness: pumps a parity widget wrapped in the Monokai theme with
// BOTH seams overridden to their fakes — `CyanBackend` → `FakeCyanBackend`
// (D4's FFI seam) and `LensApi` → `FakeLensApi` (D4's HTTP seam). NO native
// library, NO real engine, NO network. Used by every widget + golden test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/cyan_backend.dart';
import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/lens/fake_lens_api.dart';
import 'package:cyan_flutter/lens/lens_api.dart';
import 'package:cyan_flutter/providers/cyan_backend_provider.dart';
import 'package:cyan_flutter/providers/lens_console_provider.dart';
import 'package:cyan_flutter/theme/monokai_theme.dart';

/// Wrap [child] in a ProviderScope (both seams faked), MaterialApp (Monokai
/// theme) and a fixed-size surface so goldens are deterministic.
Widget parityHarness(
  Widget child, {
  CyanBackend? backend,
  LensApi? lens,
  Size size = const Size(900, 700),
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      cyanBackendProvider.overrideWithValue(backend ?? FakeCyanBackend()),
      // The lens lane is defaulted, never left live: without this override a
      // face on the D3 lane would try to reach `http://localhost:8080` from a
      // unit test.
      lensApiProvider.overrideWithValue(lens ?? FakeLensApi()),
      // Faces with a further seam beside these two (e.g. the marketplace's
      // lens bundle download) pass it here.
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MonokaiTheme.darkTheme,
      home: Scaffold(
        backgroundColor: MonokaiTheme.background,
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Pump [child] and settle async providers (FutureProvider resolution).
Future<void> pumpParity(
  WidgetTester tester,
  Widget child, {
  CyanBackend? backend,
  LensApi? lens,
  Size size = const Size(900, 700),
  List<Override> overrides = const [],
}) async {
  // Resize the actual test surface to [size] so the centered SizedBox isn't
  // clamped to the default 800x600 window. Without this, tall scrollable
  // content (lazily-built ListViews) is truncated and off-screen widgets never
  // build, which would hide rows the tests legitimately assert on.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(parityHarness(child,
      backend: backend, lens: lens, size: size, overrides: overrides));
  // Resolve FutureProviders + animations.
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
}
