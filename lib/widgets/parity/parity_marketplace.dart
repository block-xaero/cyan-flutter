// widgets/parity/parity_marketplace.dart
//
// PARITY port of the SwiftUI `MarketplaceView` (PARITY_TRACKER row 9): the
// plugin storefront. Header (title + search + Publish), a Featured rail, then
// the category AISLE rails in canonical order — the same shelves
// `MarketplaceViewModel.rebuildShelves()` lays out. Tapping a tile opens
// `ParityMarketplaceDetail` (the Get page).
//
// Driven ENTIRELY through the `CyanBackend` seam plus the lens download seam,
// via `marketplaceControllerProvider`. This widget never touches `CyanFFI`
// directly — that is the parity rule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/marketplace_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_marketplace_detail.dart';

/// The glyph a category band wears. Shared with the detail page so a listing
/// looks the same on the shelf and on its Get page.
IconData marketplaceCategoryGlyph(PluginCategory category) =>
    switch (category) {
      PluginCategory.editorial => Icons.movie_filter,
      PluginCategory.color => Icons.palette,
      PluginCategory.sound => Icons.graphic_eq,
      PluginCategory.review => Icons.rate_review,
      PluginCategory.delivery => Icons.local_shipping,
    };

/// The tint a category band wears.
Color marketplaceCategoryColor(PluginCategory category) => switch (category) {
      PluginCategory.editorial => MonokaiTheme.cyan,
      PluginCategory.color => MonokaiTheme.purple,
      PluginCategory.sound => MonokaiTheme.green,
      PluginCategory.review => MonokaiTheme.info,
      PluginCategory.delivery => MonokaiTheme.orange,
    };

class ParityMarketplace extends ConsumerWidget {
  /// "Use in a workflow" — queues a draft step for a board. Installs nothing.
  final void Function(PluginCard)? onUse;

  /// The group the operator is standing in; an install lands in ITS Plugins
  /// workspace. Null ⇒ the install refuses rather than guessing a group the
  /// engine would foreign-key-reject.
  final String? groupId;

  /// The signed-in membership role (`owner`/`admin`/`member`/…), threaded from
  /// the shell exactly as `MarketplaceView` resolves it from the restored SSO
  /// session. Null ⇒ no session, and the forge entry locks.
  final String? sessionRole;

  /// "Build a custom tool" — opens the forge intake. Only ever fired when the
  /// gate is UNLOCKED; the host wires the flow.
  final VoidCallback? onBuildCustomTool;

  const ParityMarketplace({
    super.key,
    this.onUse,
    this.groupId,
    this.sessionRole,
    this.onBuildCustomTool,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(marketplaceControllerProvider(groupId));

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            onSearch: (text) => ref
                .read(marketplaceControllerProvider(groupId).notifier)
                .search(text),
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          // W10 — the forge entry sits OUTSIDE `_body` on purpose. Every branch
          // below it (loading, browse failure, a search that matches nothing)
          // replaces the shelves, and the one thing this entry must never do is
          // disappear. Pinned here it survives all of them.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _BuildCustomToolEntry(
              gate: forgeEntryGate(sessionRole),
              onTap: onBuildCustomTool,
            ),
          ),
          Expanded(child: _body(state)),
        ],
      ),
    );
  }

  Widget _body(MarketplaceState state) {
    if (state.loading && state.cards.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: MonokaiTheme.cyan),
      );
    }
    if (state.error != null) {
      return Center(
        child: Text('Failed to load marketplace: ${state.error}',
            style: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
      );
    }
    if (state.visible.isEmpty) {
      return Center(
        child: Text(
          state.query.trim().isEmpty
              ? 'No plugins are published to this mesh yet.'
              : 'No plugins match “${state.query.trim()}”.',
          style: MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.comment),
        ),
      );
    }
    return _Storefront(state: state, onUse: onUse, groupId: groupId);
  }
}

class _Header extends StatelessWidget {
  final ValueChanged<String> onSearch;

  const _Header({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.storefront, size: 18, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Text('Marketplace', style: MonokaiTheme.titleSmall),
          const SizedBox(width: 20),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: MonokaiTheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search,
                      size: 13, color: MonokaiTheme.comment),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('marketplace.search'),
                      onChanged: onSearch,
                      style: MonokaiTheme.labelMedium,
                      cursorColor: MonokaiTheme.cyan,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search plugins',
                        hintStyle: MonokaiTheme.labelMedium,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: MonokaiTheme.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: MonokaiTheme.cyan.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.upload, size: 13, color: MonokaiTheme.cyan),
                const SizedBox(width: 6),
                Text('Publish',
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.cyan)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// W10 — the "Build a custom tool" lead entry. The port of
/// `MarketplaceView.buildCustomToolBanner`: ALWAYS rendered, and locked (lock
/// glyph + the reason in plain language) for a role that may not forge, rather
/// than hidden. A locked entry is inert — it opens nothing — so the honest
/// affordance and the real gate never disagree.
class _BuildCustomToolEntry extends StatelessWidget {
  final ForgeEntryGate gate;
  final VoidCallback? onTap;

  const _BuildCustomToolEntry({required this.gate, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tint = gate.locked ? MonokaiTheme.comment : MonokaiTheme.cyan;
    return GestureDetector(
      key: const ValueKey('marketplace.buildCustomTool'),
      behavior: HitTestBehavior.opaque,
      onTap: gate.locked ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MonokaiTheme.cyan.withValues(alpha: gate.locked ? 0.04 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: MonokaiTheme.cyan
                  .withValues(alpha: gate.locked ? 0.18 : 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.handyman,
                  size: 16, color: MonokaiTheme.background),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Build a custom tool', style: MonokaiTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    'Can’t find it? Describe an API and Cyan forges a signed '
                    'plugin for your team.',
                    style: MonokaiTheme.bodySmall
                        .copyWith(color: MonokaiTheme.textSecondary),
                  ),
                  // The lock says WHY. Without it the entry is present but
                  // mute, which is its own kind of hidden.
                  if (gate.locked) ...[
                    const SizedBox(height: 4),
                    Text(gate.reason,
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: MonokaiTheme.orange)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(gate.locked ? Icons.lock : Icons.chevron_right,
                size: 14, color: MonokaiTheme.comment),
          ],
        ),
      ),
    );
  }
}

class _Storefront extends ConsumerWidget {
  final MarketplaceState state;
  final void Function(PluginCard)? onUse;
  final String? groupId;

  const _Storefront({required this.state, this.onUse, this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = state.featured;
    // Non-lazy on purpose (as the SwiftUI `ScrollView { VStack }` is): every
    // shelf is built, so a rail below the fold is a rendered shelf and not a
    // hole the operator has to discover by scrolling blind.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // An install started from a shelf tile has no Get page open to
          // report into — it lands here, success or failure alike.
          if (state.lastOutcome != null) ...[
            _outcomeBanner(ref, state.lastOutcome!),
            const SizedBox(height: 16),
          ],
          if (featured.isNotEmpty) ...[
            _railHeader(
                Icons.star, 'Featured', featured.length, MonokaiTheme.yellow),
            const SizedBox(height: 10),
            _rail(featured),
            const SizedBox(height: 24),
          ],
          for (final aisle in state.aisles) ...[
            _railHeader(marketplaceCategoryGlyph(aisle.category), aisle.label,
                aisle.cards.length, marketplaceCategoryColor(aisle.category)),
            const SizedBox(height: 10),
            _rail(aisle.cards),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _outcomeBanner(WidgetRef ref, PluginInstallOutcome outcome) {
    final color = outcome.ok ? MonokaiTheme.green : MonokaiTheme.orange;
    return Container(
      key: const ValueKey('marketplace.installBanner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surfaceLighter,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(outcome.ok ? Icons.check_circle : Icons.error_outline,
              size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(outcome.message,
                style: MonokaiTheme.bodySmall
                    .copyWith(color: MonokaiTheme.textSecondary)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => ref
                .read(marketplaceControllerProvider(groupId).notifier)
                .dismissLastOutcome(),
            child:
                const Icon(Icons.close, size: 13, color: MonokaiTheme.comment),
          ),
        ],
      ),
    );
  }

  Widget _railHeader(IconData icon, String label, int count, Color tint) {
    return Row(
      children: [
        Icon(icon, size: 14, color: tint),
        const SizedBox(width: 8),
        Text(label, style: MonokaiTheme.labelLarge),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: MonokaiTheme.surfaceLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count',
              style: MonokaiTheme.labelSmall
                  .copyWith(color: MonokaiTheme.comment)),
        ),
      ],
    );
  }

  Widget _rail(List<PluginCard> cards) {
    return SizedBox(
      height: 300,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 240,
                  height: 300,
                  child: _Card(
                    card: card,
                    installed: state.isInstalled(card),
                    installing: state.isInstalling(card),
                    onUse: onUse,
                    groupId: groupId,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  final PluginCard card;
  final bool installed;
  final bool installing;
  final void Function(PluginCard)? onUse;
  final String? groupId;

  const _Card({
    required this.card,
    required this.installed,
    required this.installing,
    this.onUse,
    this.groupId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = marketplaceCategoryColor(card.category);
    return Container(
      key: ValueKey('marketplace.card.${card.id}'),
      decoration: BoxDecoration(
        color: MonokaiTheme.surfaceLighter,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MonokaiTheme.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Category-band header (80px) — the install control sits top-leading,
          // the category badge top-trailing.
          SizedBox(
            height: 80,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => _openDetail(context),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cat.withValues(alpha: 0.35),
                            cat.withValues(alpha: 0.12),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(9)),
                      ),
                      child: Center(
                          child: Icon(marketplaceCategoryGlyph(card.category),
                              size: 30, color: cat)),
                    ),
                  ),
                ),
                Positioned(top: 8, left: 8, child: _installControl(ref)),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: MonokaiTheme.background.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(card.category.label,
                        style: MonokaiTheme.labelSmall.copyWith(color: cat)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _openDetail(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.name,
                        style: MonokaiTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(card.publisher, style: MonokaiTheme.labelSmall),
                    const SizedBox(height: 6),
                    Text(card.summary,
                        style: MonokaiTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [_chip(card.stage), _chip(card.placement)],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Trust + side-effect badges wrap within the available
                        // width so the card never overflows on a long
                        // combination.
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [_trustBadge(), _sideEffectBadge()],
                          ),
                        ),
                        if (card.rating > 0) ...[
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star,
                                  size: 9, color: MonokaiTheme.yellow),
                              const SizedBox(width: 2),
                              Text(card.rating.toStringAsFixed(0),
                                  style: MonokaiTheme.labelSmall),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => onUse?.call(card),
                      child: Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: MonokaiTheme.cyan,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Use in a workflow',
                            style: MonokaiTheme.labelMedium
                                .copyWith(color: MonokaiTheme.background)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ParityMarketplaceDetail(
          card: card,
          groupId: groupId,
          onUse: onUse,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  /// Installed ⇒ a marker, never an affordance. In flight ⇒ the spinner. Only
  /// an un-landed bundle offers Install.
  Widget _installControl(WidgetRef ref) {
    if (installed) {
      return _bandPill(
          icon: Icons.check_circle,
          label: 'Installed',
          color: MonokaiTheme.green);
    }
    if (installing) {
      return _bandPill(
        icon: null,
        label: 'Installing…',
        color: MonokaiTheme.cyan,
        leading: const SizedBox(
          width: 9,
          height: 9,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: MonokaiTheme.cyan),
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        // An untrusted listing must WARN before it lands (§13). The Get page
        // owns that confirmation, so the shelf routes there rather than
        // installing behind the warning's back.
        if (!card.isTrusted) {
          _openDetail(ref.context);
          return;
        }
        ref.read(marketplaceControllerProvider(groupId).notifier).install(card);
      },
      child: _bandPill(
          icon: Icons.download, label: 'Install', color: MonokaiTheme.cyan),
    );
  }

  Widget _bandPill({
    required IconData? icon,
    required String label,
    required Color color,
    Widget? leading,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: MonokaiTheme.background.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) leading,
          if (icon != null) Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label, style: MonokaiTheme.labelSmall.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MonokaiTheme.surfaceLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.comment)),
    );
  }

  Widget _trustBadge() {
    final trusted = card.isTrusted;
    final color = trusted ? MonokaiTheme.green : MonokaiTheme.orange;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(trusted ? Icons.verified : Icons.gpp_maybe, size: 11, color: color),
        const SizedBox(width: 3),
        Text(trusted ? 'trusted' : 'untrusted',
            style: MonokaiTheme.labelSmall.copyWith(color: color)),
      ],
    );
  }

  Widget _sideEffectBadge() {
    final outward = card.sideEffect == PluginSideEffect.externalSend;
    final color = outward ? MonokaiTheme.orange : MonokaiTheme.green;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(outward ? Icons.outbound : Icons.visibility,
            size: 11, color: color),
        const SizedBox(width: 3),
        Text(outward ? 'sends out' : 'read-only',
            style: MonokaiTheme.labelSmall.copyWith(color: color)),
      ],
    );
  }
}
