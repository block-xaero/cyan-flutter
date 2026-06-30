// test/support/parity_test_harness.dart
//
// Tier-1 test harness: pumps a parity widget wrapped in the Monokai theme with
// the `CyanBackend` seam overridden to a `FakeCyanBackend`. NO native library,
// NO real engine. Used by every widget + golden test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/cyan_backend.dart';
import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/providers/cyan_backend_provider.dart';
import 'package:cyan_flutter/theme/monokai_theme.dart';

/// Wrap [child] in a ProviderScope (fake backend), MaterialApp (Monokai theme)
/// and a fixed-size surface so goldens are deterministic.
Widget parityHarness(
  Widget child, {
  CyanBackend? backend,
  Size size = const Size(900, 700),
}) {
  return ProviderScope(
    overrides: [
      cyanBackendProvider.overrideWithValue(backend ?? FakeCyanBackend()),
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
  Size size = const Size(900, 700),
}) async {
  // Resize the actual test surface to [size] so the centered SizedBox isn't
  // clamped to the default 800x600 window. Without this, tall scrollable
  // content (lazily-built ListViews) is truncated and off-screen widgets never
  // build, which would hide rows the tests legitimately assert on.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(parityHarness(child, backend: backend, size: size));
  // Resolve FutureProviders + animations.
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
}
