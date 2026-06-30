// test/marketplace_test.dart
//
// PARITY_TRACKER row 9 — Marketplace. Tier-1: drives `ParityMarketplace`
// through the `CyanBackend` seam (FakeCyanBackend) and asserts the header, the
// Featured + All plugins aisles, the category-band cards (trust + side-effect
// badges), and that "Use in a workflow" fires. Plus a golden (tagged `golden`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_marketplace.dart';

import 'support/parity_test_harness.dart';

void main() {
  testWidgets('renders the storefront with featured + all plugins',
      (tester) async {
    await pumpParity(tester, const ParityMarketplace(),
        size: const Size(900, 800));

    expect(find.text('Marketplace'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('All plugins'), findsOneWidget);

    // Seeded plugins (appear in featured and/or all aisles).
    expect(find.text('FFmpeg Transcode'), findsWidgets);
    expect(find.text('Frame.io Review'), findsWidgets);

    // Category-band + trust/side-effect badges.
    expect(find.text('Editorial'), findsWidgets);
    expect(find.text('untrusted'), findsWidgets); // Frame.io is untrusted
    expect(find.text('sends out'), findsWidgets); // external_send side effect

    // Footer CTA.
    expect(find.text('Use in a workflow'), findsWidgets);
  });

  testWidgets('Use in a workflow fires onUse', (tester) async {
    PluginCard? used;
    await pumpParity(
      tester,
      ParityMarketplace(onUse: (c) => used = c),
      size: const Size(900, 800),
    );

    await tester.tap(find.text('Use in a workflow').first);
    await tester.pump();

    expect(used, isNotNull);
  });

  testWidgets('golden: marketplace', (tester) async {
    await pumpParity(tester, const ParityMarketplace(),
        size: const Size(900, 800));
    await expectLater(
      find.byType(ParityMarketplace),
      matchesGoldenFile('golden/marketplace.png'),
    );
  }, tags: 'golden');
}
