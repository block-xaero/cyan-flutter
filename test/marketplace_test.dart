// test/marketplace_test.dart
//
// PARITY_TRACKER row 9 — Marketplace (face: marketplace). Tier-1: drives
// `ParityMarketplace` + `ParityMarketplaceDetail` through the `CyanBackend`
// seam (FakeCyanBackend) and the lens download seam (a fake bundle fetcher).
// No dylib, no lens.
//
// The install leg is the REAL one: the fetcher hands over bundle bytes, the
// FAKE ENGINE applies its admit gate (a `.cyanplugin` tar must carry
// `cyan-plugin.toml` at its root) and only then does the bundle land in the
// group's Plugins workspace — which is where "Installed" is read back from.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/providers/marketplace_provider.dart';
import 'package:cyan_flutter/services/plugin_bundle_fetcher.dart';
import 'package:cyan_flutter/widgets/parity/parity_marketplace.dart';
import 'package:cyan_flutter/widgets/parity/parity_marketplace_detail.dart';

import 'support/parity_test_harness.dart';

/// A group that exists in the seeded fake — an install into a group the engine
/// has no row for is foreign-key-rejected, exactly as in prod.
const String kGroup = 'g-eng';

/// Stands in for the lens download leg. Yields bytes that LOOK like a
/// `.cyanplugin` tar (the fake engine's admit gate reads the manifest name out
/// of them), so a passing install has actually cleared that gate.
class FakeBundleFetcher implements PluginBundleFetcher {
  /// Held open so a test can observe the in-flight ("Installing…") state
  /// before the terminal result lands.
  Completer<void>? gate;

  /// When set, the download itself fails — the storefront must still reach a
  /// terminal result.
  String? failWith;

  final List<String> requested = [];

  @override
  Future<String> fetchBundleB64(String bundleId) async {
    requested.add(bundleId);
    if (gate != null) await gate!.future;
    if (failWith != null) throw PluginBundleUnavailable(failWith!);
    return base64.encode(
        utf8.encode('./cyan-plugin.toml id = "$bundleId"\nversion = "1.0.0"\n'));
  }
}

Future<void> pumpMarketplace(
  WidgetTester tester, {
  PluginBundleFetcher? fetcher,
  String? groupId = kGroup,
  void Function(PluginCard)? onUse,
  String? sessionRole,
  VoidCallback? onBuildCustomTool,
}) async {
  await pumpParity(
    tester,
    ParityMarketplace(
      groupId: groupId,
      onUse: onUse,
      sessionRole: sessionRole,
      onBuildCustomTool: onBuildCustomTool,
    ),
    size: const Size(900, 800),
    overrides: [
      if (fetcher != null)
        pluginBundleFetcherProvider.overrideWithValue(fetcher),
    ],
  );
}

/// The forge entry, wherever the storefront is in its lifecycle.
final Finder forgeEntry = find.byKey(const ValueKey('marketplace.buildCustomTool'));

/// Open a listing's Get page by tapping its tile.
Future<void> openDetail(WidgetTester tester, String cardId) async {
  final tile = find.byKey(ValueKey('marketplace.card.$cardId')).first;
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile, warnIfMissed: false);
  await tester.pumpAndSettle();
  expect(find.byType(ParityMarketplaceDetail), findsOneWidget);
}

/// Tap a control on the open Get page. The page scrolls, so bring the control
/// into view first — the Get controls sit below the fold on a 520pt sheet.
Future<void> tapInDetail(WidgetTester tester, String label) async {
  final target = find.descendant(
      of: find.byType(ParityMarketplaceDetail), matching: find.text(label));
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
}

void main() {
  testWidgets('the storefront renders featured plugins and stage aisles',
      (tester) async {
    await pumpMarketplace(tester);

    expect(find.text('Marketplace'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);

    // The curated Featured rail leads…
    expect(find.text('Featured'), findsOneWidget);
    // …then every non-empty stage aisle, in canonical storefront order.
    for (final aisle in const [
      'Editorial',
      'Color',
      'Sound',
      'Review',
      'Delivery',
    ]) {
      expect(find.text(aisle), findsWidgets, reason: 'aisle $aisle is missing');
    }

    // Seeded listings (a featured one appears on both its rails).
    expect(find.text('FFmpeg Transcode'), findsWidgets);
    expect(find.text('Resolve Color Match'), findsWidgets);
    expect(find.text('Loudness Normalize'), findsWidgets);
    expect(find.text('Frame.io Review'), findsWidgets);
    expect(find.text('Spec Delivery'), findsWidgets);

    // TRUST rides on the tile — the lens serves it, and it is the one safety
    // signal a not-yet-installed listing can honestly carry.
    expect(find.text('untrusted'), findsWidgets); // Frame.io is untrusted

    // SIDE EFFECTS do NOT, and that is the finding of moving this face onto the
    // live lane (row 20): the lens's browse shape carries plugin_id / name /
    // description / tool_summary / trust / source / featured / stage and
    // nothing else. It cannot say whether a plugin sends data out — only the
    // ENGINE's catalog knows that, from the installed bundle's manifest, which
    // is also the thing that actually gates a run. So no tile claims
    // "sends out" off a listing, and the claim appears on the detail page for a
    // bundle the device actually holds. A badge sourced from nowhere is worse
    // than no badge on exactly the axis where being wrong is dangerous.
    expect(find.text('sends out'), findsNothing);

    // Footer CTA.
    expect(find.text('Use in a workflow'), findsWidgets);
  });

  testWidgets('searching filters the catalogue', (tester) async {
    await pumpMarketplace(tester);

    expect(find.text('Loudness Normalize'), findsWidgets);
    expect(find.text('Frame.io Review'), findsWidgets);

    await tester.enterText(
        find.byKey(const ValueKey('marketplace.search')), 'loudness');
    await tester.pumpAndSettle();

    // Only the match survives — and only its own aisle is shelved.
    expect(find.text('Loudness Normalize'), findsWidgets);
    expect(find.text('Frame.io Review'), findsNothing);
    expect(find.text('FFmpeg Transcode'), findsNothing);
    expect(find.text('Sound'), findsWidgets);
    expect(find.text('Review'), findsNothing);

    // A query that matches nothing says so rather than showing empty shelves.
    await tester.enterText(
        find.byKey(const ValueKey('marketplace.search')), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No plugins match'), findsOneWidget);

    // Clearing it brings the whole catalogue back.
    await tester.enterText(
        find.byKey(const ValueKey('marketplace.search')), '');
    await tester.pumpAndSettle();
    expect(find.text('Frame.io Review'), findsWidgets);
  });

  testWidgets('opening a plugin shows its detail with tools and side effects',
      (tester) async {
    await pumpMarketplace(tester);
    // FFmpeg Transcode's bundle is already in the device catalog, so its Get
    // page can list the bundle's own tools.
    await openDetail(tester, 'ffmpeg');

    final detail = find.byType(ParityMarketplaceDetail);

    // Identity + overview.
    expect(find.descendant(of: detail, matching: find.text('FFmpeg Transcode')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detail, matching: find.text('Publisher: Curated')),
        findsOneWidget);
    expect(find.descendant(of: detail, matching: find.text('Tools')),
        findsOneWidget);

    // The bundle's tools, straight off `pluginCatalog()` — name-qualified.
    expect(find.descendant(of: detail, matching: find.text('@ffmpeg.probe')),
        findsOneWidget);
    expect(
        find.descendant(of: detail, matching: find.text('@ffmpeg.transcode')),
        findsOneWidget);

    // Side effects: the per-tool labels the manifest declares, the engine's
    // approval verdict on them, and the listing's own read-only/sends-out note.
    expect(find.descendant(of: detail, matching: find.text('Side effects')),
        findsOneWidget);
    expect(find.descendant(of: detail, matching: find.text('mutate_local')),
        findsWidgets);
    expect(find.descendant(of: detail, matching: find.text('needs approval')),
        findsWidgets);
    expect(find.descendant(of: detail, matching: find.text('no side effects')),
        findsWidgets); // `probe` is a sensor
    expect(
        find.descendant(
            of: detail, matching: find.textContaining('nothing leaves it')),
        findsOneWidget);
  });

  testWidgets('installing a plugin reports progress and a terminal result',
      (tester) async {
    final fetcher = FakeBundleFetcher()..gate = Completer<void>();
    await pumpMarketplace(tester, fetcher: fetcher);

    // Loudness Normalize is trusted and NOT installed — it offers a Get.
    await openDetail(tester, 'pl-loudness');
    final detail = find.byType(ParityMarketplaceDetail);

    expect(
        find.descendant(
            of: detail, matching: find.text('Install on this device')),
        findsOneWidget);
    await tapInDetail(tester, 'Install on this device');
    await tester.pump();

    // PROGRESS — the download is still in flight.
    expect(find.descendant(of: detail, matching: find.text('Installing…')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detail, matching: find.byType(CircularProgressIndicator)),
        findsWidgets);

    // Let the download complete; the engine's admit gate then runs for real.
    fetcher.gate!.complete();
    await tester.pumpAndSettle();

    // TERMINAL RESULT — named landing spot, and the spinner is gone.
    expect(find.descendant(of: detail, matching: find.text('Installing…')),
        findsNothing);
    expect(
        find.descendant(
            of: detail,
            matching: find.textContaining('Installed “Loudness Normalize”')),
        findsOneWidget);
    expect(fetcher.requested, ['pl-loudness']);

    // The bundle really landed: the Get page now lists the tools the ENGINE
    // reports for it, and offers no second install.
    expect(find.descendant(of: detail, matching: find.text('Installed')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detail, matching: find.text('Install on this device')),
        findsNothing);
    expect(
        find.descendant(
            of: detail, matching: find.text('@pl-loudness.loudness_run')),
        findsOneWidget);
  });

  testWidgets(
      'an already installed plugin is shown as installed not installable',
      (tester) async {
    await pumpMarketplace(tester);

    // `pl-ffmpeg` lists the `ffmpeg` bundle, which the device catalog already
    // holds — the tile is a marker, not an affordance. It is shelved twice
    // (Featured + Editorial), and BOTH tiles must say the same thing.
    final ffmpegTiles =
        find.byKey(const ValueKey('marketplace.card.ffmpeg'));
    expect(ffmpegTiles, findsNWidgets(2));
    expect(find.descendant(of: ffmpegTiles, matching: find.text('Installed')),
        findsNWidgets(2));
    expect(find.descendant(of: ffmpegTiles, matching: find.text('Install')),
        findsNothing);

    // A listing whose bundle has NOT landed still offers one.
    final loudnessTile =
        find.byKey(const ValueKey('marketplace.card.pl-loudness'));
    expect(find.descendant(of: loudnessTile, matching: find.text('Install')),
        findsOneWidget);
    expect(find.descendant(of: loudnessTile, matching: find.text('Installed')),
        findsNothing);

    // And the Get page agrees — no install control for the landed bundle.
    await openDetail(tester, 'ffmpeg');
    final detail = find.byType(ParityMarketplaceDetail);
    expect(find.descendant(of: detail, matching: find.text('Installed')),
        findsOneWidget);
    expect(
        find.descendant(
            of: detail, matching: find.text('Install on this device')),
        findsNothing);
  });

  testWidgets('a refused install reports its terminal failure', (tester) async {
    final fetcher = FakeBundleFetcher()..failWith = 'the lens is unreachable';
    await pumpMarketplace(tester, fetcher: fetcher);

    await openDetail(tester, 'pl-loudness');
    final detail = find.byType(ParityMarketplaceDetail);

    await tapInDetail(tester, 'Install on this device');
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: detail,
            matching: find.textContaining('the lens is unreachable')),
        findsOneWidget);
    // A failed install never claims the bundle landed.
    expect(find.descendant(of: detail, matching: find.text('Installed')),
        findsNothing);
    expect(
        find.descendant(
            of: detail, matching: find.text('Install on this device')),
        findsOneWidget);
  });

  testWidgets('with no group selected an install refuses instead of guessing',
      (tester) async {
    final fetcher = FakeBundleFetcher();
    await pumpMarketplace(tester, fetcher: fetcher, groupId: null);

    await openDetail(tester, 'pl-loudness');
    final detail = find.byType(ParityMarketplaceDetail);

    await tapInDetail(tester, 'Install on this device');
    await tester.pumpAndSettle();

    expect(
        find.descendant(
            of: detail, matching: find.textContaining('Select a group first')),
        findsOneWidget);
    // It never even reached for the bytes.
    expect(fetcher.requested, isEmpty);
  });

  testWidgets('a shelf-tile install reports into the storefront banner',
      (tester) async {
    final fetcher = FakeBundleFetcher()..failWith = 'the lens is unreachable';
    await pumpMarketplace(tester, fetcher: fetcher);

    // Installing straight off the tile — no Get page open to report into.
    final pill = find.descendant(
        of: find.byKey(const ValueKey('marketplace.card.pl-loudness')),
        matching: find.text('Install'));
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pumpAndSettle();

    final banner = find.byKey(const ValueKey('marketplace.installBanner'));
    expect(banner, findsOneWidget);
    expect(
        find.descendant(
            of: banner, matching: find.textContaining('the lens is unreachable')),
        findsOneWidget);
    // The tile went back to offering the install rather than claiming one.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('marketplace.card.pl-loudness')),
            matching: find.text('Install')),
        findsOneWidget);

    // Dismissing clears it.
    final dismiss =
        find.descendant(of: banner, matching: find.byIcon(Icons.close));
    await tester.ensureVisible(dismiss);
    await tester.pumpAndSettle();
    await tester.tap(dismiss);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('marketplace.installBanner')), findsNothing);
  });

  testWidgets('an untrusted plugin warns before it is installed',
      (tester) async {
    final fetcher = FakeBundleFetcher();
    await pumpMarketplace(tester, fetcher: fetcher);

    await openDetail(tester, 'pl-frameio');
    final detail = find.byType(ParityMarketplaceDetail);

    await tapInDetail(tester, 'Install on this device');
    await tester.pumpAndSettle();

    // The warning stands between the tap and the bytes.
    expect(
        find.descendant(
            of: detail,
            matching: find.textContaining('comes from the public registry')),
        findsOneWidget);
    expect(fetcher.requested, isEmpty);

    await tapInDetail(tester, 'Install anyway');
    await tester.pumpAndSettle();

    expect(fetcher.requested, ['pl-frameio']);
    expect(
        find.descendant(
            of: detail,
            matching: find.textContaining('Installed “Frame.io Review”')),
        findsOneWidget);
  });

  testWidgets('Use in a workflow fires onUse', (tester) async {
    PluginCard? used;
    await pumpMarketplace(tester, onUse: (c) => used = c);

    await tester.tap(find.text('Use in a workflow').first);
    await tester.pump();

    expect(used, isNotNull);
  });

  testWidgets(
      'the build a custom tool entry is always present and locked rather than hidden',
      (tester) async {
    // ADMIN — the entry is live: chevron, no lock, and the tap opens the forge.
    var opened = 0;
    await pumpMarketplace(tester,
        sessionRole: 'admin', onBuildCustomTool: () => opened++);

    expect(forgeEntry, findsOneWidget);
    expect(find.text('Build a custom tool'), findsOneWidget);
    expect(find.descendant(of: forgeEntry, matching: find.byIcon(Icons.lock)),
        findsNothing);
    expect(
        find.descendant(
            of: forgeEntry, matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget);
    await tester.tap(forgeEntry);
    await tester.pump();
    expect(opened, 1);

    // MEMBER — still there, now locked: the lock glyph, the reason in plain
    // language, and a tap that opens nothing.
    opened = 0;
    await pumpMarketplace(tester,
        sessionRole: 'member', onBuildCustomTool: () => opened++);

    expect(forgeEntry, findsOneWidget);
    expect(find.text('Build a custom tool'), findsOneWidget);
    expect(find.descendant(of: forgeEntry, matching: find.byIcon(Icons.lock)),
        findsOneWidget);
    expect(
        find.descendant(
            of: forgeEntry, matching: find.byIcon(Icons.chevron_right)),
        findsNothing);
    expect(find.textContaining('Only an admin can build a custom tool'),
        findsOneWidget);
    await tester.tap(forgeEntry);
    await tester.pump();
    expect(opened, 0, reason: 'a locked entry must open nothing');

    // NO SESSION — the deny-by-default case. Present and locked, never absent.
    await pumpMarketplace(tester, sessionRole: null);
    expect(forgeEntry, findsOneWidget);
    expect(find.descendant(of: forgeEntry, matching: find.byIcon(Icons.lock)),
        findsOneWidget);

    // …and a role the engine's vocabulary does not admit denies rather than
    // being read as "not a member, so probably fine".
    await pumpMarketplace(tester, sessionRole: 'superuser');
    expect(forgeEntry, findsOneWidget);
    expect(find.descendant(of: forgeEntry, matching: find.byIcon(Icons.lock)),
        findsOneWidget);

    // ALWAYS PRESENT means through the states that replace the shelves too: a
    // search that matches nothing wipes the rails but not the entry.
    await pumpMarketplace(tester, sessionRole: 'owner');
    expect(forgeEntry, findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('marketplace.search')), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No plugins match'), findsOneWidget);
    expect(find.text('FFmpeg Transcode'), findsNothing);
    expect(forgeEntry, findsOneWidget,
        reason: 'the entry outlives the shelves it leads');
  });

  testWidgets('golden: marketplace', (tester) async {
    await pumpMarketplace(tester);
    await expectLater(
      find.byType(ParityMarketplace),
      matchesGoldenFile('golden/marketplace.png'),
    );
  }, tags: 'golden');
}
