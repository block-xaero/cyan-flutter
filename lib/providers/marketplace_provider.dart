// providers/marketplace_provider.dart
//
// The storefront's state, ported from `MarketplaceViewModel` (ViewModels/
// MarketplaceViewModel.swift): browse → featured row + aisle shelves + search,
// and the real install (fetch bundle → engine verifies + lands it → re-read the
// device catalog).
//
// Two seams, mirroring the macOS split:
//   • `CyanBackend` — `loadMarketplace()` (what COULD be installed),
//     `pluginCatalog()` (what IS installed), `installPluginBundle()` (the land).
//   • `PluginBundleFetcher` — the lens download leg.
//
// "Installed" is never a client-side claim: it is read back out of
// `pluginCatalog()` after the engine admits the bundle, so the chip cannot say
// Installed while the Plugins workspace is empty.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/cyan_backend.dart';
import '../ffi/parity_models.dart';
import '../services/plugin_bundle_fetcher.dart';
import 'cyan_backend_provider.dart';

/// The lens download leg. Overridden in tests with a fetcher that yields bundle
/// bytes, so the install flow runs with no lens and no dylib.
final pluginBundleFetcherProvider =
    Provider<PluginBundleFetcher>((ref) => LensPluginBundleFetcher());

/// The membership roles the engine's `Role::parse` admits, most to least
/// capable. Rank IS the position, mirroring `Role.rank` on the Swift side; the
/// engine owns the vocabulary and re-checks it at every door, so this list only
/// decides what the UI *shows*, never what the server allows.
const List<String> kMeshRoles = ['owner', 'admin', 'member', 'viewer', 'guest'];

/// The verdict the storefront's "Build a custom tool" (forge) entry renders.
/// [locked] never means "hidden" — see [forgeEntryGate].
@immutable
class ForgeEntryGate {
  final bool locked;

  /// Plain-language line the locked entry shows, so the lock is honest about
  /// WHY rather than just being inert. Empty when unlocked.
  final String reason;

  const ForgeEntryGate({required this.locked, required this.reason});

  static const ForgeEntryGate unlocked =
      ForgeEntryGate(locked: false, reason: '');
}

/// The forge gate for [sessionRole] — the port of
/// `MarketplaceViewModel.canBuildCustomTool` (`authorize(.codegenPlugin)`,
/// Admin+).
///
/// Two rules, both deliberate:
///   • no session, or a role outside the engine's vocabulary, DENIES. The
///     client never widens a gate the server owns.
///   • a denial LOCKS the entry, it does not remove it. The entry kept
///     vanishing when a cached-admin session re-verified into a lesser role,
///     and a missing entry reads as "Cyan cannot do this" rather than "you
///     personally may not". The real gate stays server-side.
ForgeEntryGate forgeEntryGate(String? sessionRole) {
  final role = (sessionRole ?? '').trim().toLowerCase();
  final rank = kMeshRoles.indexOf(role);
  if (rank >= 0 && rank <= kMeshRoles.indexOf('admin')) {
    return ForgeEntryGate.unlocked;
  }
  return ForgeEntryGate(
    locked: true,
    reason: role.isEmpty
        ? 'Sign in with an admin session to build a custom tool.'
        : 'Only an admin can build a custom tool — ask your admin.',
  );
}

/// The TERMINAL result of one install attempt — what the banner says once the
/// spinner is gone. There is always exactly one of these per finished attempt:
/// an install never ends silently.
@immutable
class PluginInstallOutcome {
  final String cardId;
  final bool ok;
  final String message;

  const PluginInstallOutcome({
    required this.cardId,
    required this.ok,
    required this.message,
  });
}

/// One aisle shelf on the storefront: a category band and the cards in it, in
/// the catalogue's own order.
@immutable
class MarketplaceAisle {
  final PluginCategory category;
  final List<PluginCard> cards;

  const MarketplaceAisle({required this.category, required this.cards});

  String get label => category.label;
}

@immutable
class MarketplaceState {
  final bool loading;

  /// The browse failed — the storefront says so instead of showing an empty
  /// shelf that reads like "no plugins exist".
  final String? error;

  /// The whole browsed catalogue, in the order the source returned it.
  final List<PluginCard> cards;

  /// What the search box holds. Filtering is client-side because
  /// `loadMarketplace()` takes no query; ranking mirrors the macOS
  /// `rankedForQuery` so an exact hit is never below the fold.
  final String query;

  /// The device catalog keyed by bundle id — the ONLY door to "Installed".
  final Map<String, InstalledPlugin> installed;

  /// Card ids with an install in flight (drives "Installing…").
  final Set<String> installing;

  /// The last terminal result per card id.
  final Map<String, PluginInstallOutcome> outcomes;

  /// The most recent terminal result, whichever listing it belongs to. The
  /// storefront banners it: an install started from a shelf tile has nowhere
  /// else to report, and a failure there must never be silent.
  final PluginInstallOutcome? lastOutcome;

  const MarketplaceState({
    this.loading = true,
    this.error,
    this.cards = const [],
    this.query = '',
    this.installed = const {},
    this.installing = const {},
    this.outcomes = const {},
    this.lastOutcome,
  });

  MarketplaceState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<PluginCard>? cards,
    String? query,
    Map<String, InstalledPlugin>? installed,
    Set<String>? installing,
    Map<String, PluginInstallOutcome>? outcomes,
    PluginInstallOutcome? lastOutcome,
    bool clearLastOutcome = false,
  }) {
    return MarketplaceState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      cards: cards ?? this.cards,
      query: query ?? this.query,
      installed: installed ?? this.installed,
      installing: installing ?? this.installing,
      outcomes: outcomes ?? this.outcomes,
      lastOutcome: clearLastOutcome ? null : (lastOutcome ?? this.lastOutcome),
    );
  }

  /// The catalogue the shelves are built from: filtered by the search text,
  /// then ranked so an exact id/name match leads, prefix matches follow, and
  /// everything else keeps the source's order.
  List<PluginCard> get visible {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return cards;
    final hits = cards.where((c) => _matches(c, q)).toList();
    final ranked = hits.asMap().entries.toList()
      ..sort((a, b) {
        final r = _rank(a.value, q).compareTo(_rank(b.value, q));
        return r != 0 ? r : a.key.compareTo(b.key);
      });
    return [for (final e in ranked) e.value];
  }

  static bool _matches(PluginCard c, String q) =>
      c.id.toLowerCase().contains(q) ||
      c.bundleId.toLowerCase().contains(q) ||
      c.name.toLowerCase().contains(q) ||
      c.publisher.toLowerCase().contains(q) ||
      c.summary.toLowerCase().contains(q) ||
      c.category.label.toLowerCase().contains(q) ||
      c.stage.toLowerCase().contains(q);

  static int _rank(PluginCard c, String q) {
    final id = c.id.toLowerCase();
    final name = c.name.toLowerCase();
    if (id == q || name == q) return 0;
    if (id.startsWith(q) || name.startsWith(q)) return 1;
    return 2;
  }

  /// The source's DELIBERATE curation flags, in source order. No flags ⇒ no
  /// Featured row (never a derived "top 3", which surfaced arbitrary cards).
  List<PluginCard> get featured =>
      [for (final c in visible) if (c.isFeatured) c];

  /// The category aisles in canonical storefront order, empty shelves dropped.
  List<MarketplaceAisle> get aisles {
    final out = <MarketplaceAisle>[];
    for (final category in PluginCategory.values) {
      final shelf = [for (final c in visible) if (c.category == category) c];
      if (shelf.isEmpty) continue;
      out.add(MarketplaceAisle(category: category, cards: shelf));
    }
    return out;
  }

  /// Whether this listing's bundle is in the device catalog.
  bool isInstalled(PluginCard card) => installed.containsKey(card.bundleId);

  /// The landed bundle for a listing — the source of its tool list.
  InstalledPlugin? bundleFor(PluginCard card) => installed[card.bundleId];

  bool isInstalling(PluginCard card) => installing.contains(card.id);

  PluginInstallOutcome? outcomeFor(PluginCard card) => outcomes[card.id];
}

/// The storefront controller for the group the operator is standing in. Keyed
/// by group id because an install lands in THAT group's Plugins workspace —
/// a client-global "installed" flag lied across groups in the macOS app.
final marketplaceControllerProvider = StateNotifierProvider.autoDispose
    .family<MarketplaceController, MarketplaceState, String?>((ref, groupId) {
  final controller = MarketplaceController(
    backend: ref.watch(cyanBackendProvider),
    fetcher: ref.watch(pluginBundleFetcherProvider),
    groupId: groupId,
  );
  controller.load();
  return controller;
});

class MarketplaceController extends StateNotifier<MarketplaceState> {
  final CyanBackend _backend;
  final PluginBundleFetcher _fetcher;

  /// The group an install lands in. Null ⇒ the operator is standing nowhere;
  /// the install refuses rather than inventing a group the engine would
  /// foreign-key-reject.
  final String? _groupId;

  MarketplaceController({
    required CyanBackend backend,
    required PluginBundleFetcher fetcher,
    String? groupId,
  })  : _backend = backend,
        _fetcher = fetcher,
        _groupId = groupId,
        super(const MarketplaceState());

  /// Browse the storefront and read the device catalog behind it.
  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _backend.initialize();
      final cards = await _backend.loadMarketplace();
      final catalog = await _backend.pluginCatalog();
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        cards: cards,
        installed: {for (final p in catalog) p.id: p},
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  /// Re-filter for [text]. The catalogue is already in hand, so this is
  /// synchronous — no re-browse, no debounce needed.
  void search(String text) => state = state.copyWith(query: text);

  /// Fetch the signed bundle, hand it to the engine to verify + unpack into the
  /// group's Plugins workspace, then re-read the catalog so the Installed state
  /// reflects what actually landed. No-throw: every failure becomes a terminal
  /// [PluginInstallOutcome], never a crash.
  Future<void> install(PluginCard card) async {
    if (state.isInstalling(card) || state.isInstalled(card)) return;

    final group = _groupId ?? '';
    if (group.isEmpty) {
      _finish(card,
          ok: false,
          message: 'Select a group first — plugins install into the current '
              "group's Plugins workspace.");
      return;
    }

    state = state.copyWith(
      installing: {...state.installing, card.id},
      outcomes: {...state.outcomes}..remove(card.id),
    );

    final String bundleB64;
    try {
      bundleB64 = await _fetcher.fetchBundleB64(card.bundleId);
    } catch (e) {
      _finish(card, ok: false, message: 'Couldn’t download “${card.name}” — $e');
      return;
    }

    final result =
        await _backend.installPluginBundle(group, card.bundleId, bundleB64);
    if (!result.success) {
      _finish(card,
          ok: false,
          message: result.error ?? 'Installing “${card.name}” failed.');
      return;
    }

    // The engine admitted it — re-read the catalog so "Installed" is its
    // answer, not ours, and the detail can list the bundle's tools.
    final catalog = await _backend.pluginCatalog();
    if (!mounted) return;
    state = state.copyWith(installed: {for (final p in catalog) p.id: p});
    _finish(card,
        ok: true,
        message: 'Installed “${card.name}” into this group’s Plugins '
            'workspace — type @${card.bundleId} in a board’s Workflow to '
            'use it (works offline).');
  }

  /// Clear the storefront banner once the operator has read it.
  void dismissLastOutcome() => state = state.copyWith(clearLastOutcome: true);

  void _finish(PluginCard card, {required bool ok, required String message}) {
    if (!mounted) return;
    final outcome =
        PluginInstallOutcome(cardId: card.id, ok: ok, message: message);
    state = state.copyWith(
      installing: {...state.installing}..remove(card.id),
      outcomes: {...state.outcomes, card.id: outcome},
      lastOutcome: outcome,
    );
  }
}
