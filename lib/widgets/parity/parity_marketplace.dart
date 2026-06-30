// widgets/parity/parity_marketplace.dart
//
// PARITY port of the SwiftUI `MarketplaceView` (PARITY_TRACKER row 9): a plugin
// storefront with a header (title + search + Publish), a Featured aisle, and a
// masonry grid of category-band cards. Each card has a category-tinted header
// band with a centered glyph + category badge, a body (name · publisher ·
// summary · stage/placement chips), a trust badge + side-effect badge, and a
// "Use in a workflow" footer button.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `marketplaceProvider`).
// This widget never touches `CyanFFI` directly — that is the parity rule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityMarketplace extends ConsumerWidget {
  /// "Use in a workflow" / open detail — UI-only here.
  final void Function(PluginCard)? onUse;

  const ParityMarketplace({super.key, this.onUse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(marketplaceProvider);

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: cardsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: MonokaiTheme.cyan),
              ),
              error: (e, _) => Center(
                child: Text('Failed to load marketplace: $e',
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.red)),
              ),
              data: (cards) => _Storefront(cards: cards, onUse: onUse),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: MonokaiTheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 13, color: MonokaiTheme.comment),
                  const SizedBox(width: 6),
                  Text('Search plugins', style: MonokaiTheme.labelMedium),
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
              border: Border.all(color: MonokaiTheme.cyan.withValues(alpha: 0.4)),
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

class _Storefront extends StatelessWidget {
  final List<PluginCard> cards;
  final void Function(PluginCard)? onUse;

  const _Storefront({required this.cards, this.onUse});

  @override
  Widget build(BuildContext context) {
    final featured = cards.where((c) => c.isFeatured).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (featured.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.star, size: 14, color: MonokaiTheme.yellow),
              const SizedBox(width: 8),
              Text('Featured', style: MonokaiTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featured.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(
                width: 240,
                child: _Card(card: featured[i], onUse: onUse),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            const Icon(Icons.apps, size: 14, color: MonokaiTheme.cyan),
            const SizedBox(width: 8),
            Text('All plugins', style: MonokaiTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards
              .map((c) => SizedBox(
                    width: 240,
                    child: _Card(card: c, onUse: onUse),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final PluginCard card;
  final void Function(PluginCard)? onUse;

  const _Card({required this.card, this.onUse});

  Color get _categoryColor => switch (card.category) {
        PluginCategory.editorial => MonokaiTheme.cyan,
        PluginCategory.color => MonokaiTheme.purple,
        PluginCategory.sound => MonokaiTheme.green,
        PluginCategory.review => MonokaiTheme.info,
        PluginCategory.delivery => MonokaiTheme.orange,
      };

  IconData get _categoryGlyph => switch (card.category) {
        PluginCategory.editorial => Icons.movie_filter,
        PluginCategory.color => Icons.palette,
        PluginCategory.sound => Icons.graphic_eq,
        PluginCategory.review => Icons.rate_review,
        PluginCategory.delivery => Icons.local_shipping,
      };

  @override
  Widget build(BuildContext context) {
    final cat = _categoryColor;
    return Container(
      decoration: BoxDecoration(
        color: MonokaiTheme.surfaceLighter,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MonokaiTheme.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Category-band header (80px).
          SizedBox(
            height: 80,
            child: Stack(
              children: [
                Positioned.fill(
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
                    child: Center(child: Icon(_categoryGlyph, size: 30, color: cat)),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
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
          Padding(
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
                  children: [
                    _chip(card.stage),
                    _chip(card.placement),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Trust + side-effect badges wrap within the available
                    // width so the card never overflows on a long combination.
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
                const SizedBox(height: 10),
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
        Icon(trusted ? Icons.verified : Icons.gpp_maybe,
            size: 11, color: color),
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
