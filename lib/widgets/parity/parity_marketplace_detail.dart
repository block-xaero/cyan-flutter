// widgets/parity/parity_marketplace_detail.dart
//
// PARITY port of the SwiftUI `MarketplaceDetailView` (Views/
// MarketplaceDetailView.swift): the listing's detail / **Get** page.
//
// What it shows, and where each part comes from:
//   • overview + side effects  — the storefront listing (`PluginCard`)
//   • TOOLS                    — the DEVICE CATALOG (`CyanBackend.pluginCatalog`),
//                                i.e. the bundle's own manifest. A listing does
//                                not carry its tools, so they appear once the
//                                bundle has landed and not a moment before —
//                                the same honest gap the macOS peek states.
//   • Get                      — the real install: lens download → engine
//                                verify + unpack → catalog re-read.
//
// Untrusted (public-registry) listings warn before installing, exactly as
// MESH_HARDENING §13 has the macOS Get page do.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/marketplace_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_marketplace.dart' show marketplaceCategoryGlyph;

class ParityMarketplaceDetail extends ConsumerStatefulWidget {
  final PluginCard card;

  /// The group an install lands in — threaded from the shell, as the macOS
  /// storefront threads `targetGroupId`.
  final String? groupId;

  /// "Use in a workflow" — queues a draft step for a board. It installs
  /// NOTHING, and the copy says so.
  final void Function(PluginCard)? onUse;

  final VoidCallback? onClose;

  const ParityMarketplaceDetail({
    super.key,
    required this.card,
    this.groupId,
    this.onUse,
    this.onClose,
  });

  @override
  ConsumerState<ParityMarketplaceDetail> createState() =>
      _ParityMarketplaceDetailState();
}

class _ParityMarketplaceDetailState
    extends ConsumerState<ParityMarketplaceDetail> {
  /// §13: an install held back pending confirmation because the plugin is
  /// untrusted (it lands sandboxed and removable).
  bool _pendingUntrustedConfirm = false;

  /// #26 — the queued-for-a-board confirmation. Queuing is not installing.
  bool _queuedForWorkflow = false;

  PluginCard get card => widget.card;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(marketplaceControllerProvider(widget.groupId));
    final installed = state.isInstalled(card);
    final installing = state.isInstalling(card);
    final outcome = state.outcomeFor(card);
    final bundle = state.bundleFor(card);

    return Material(
      color: MonokaiTheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _titleBar(),
            const Divider(height: 1, color: MonokaiTheme.divider),
            // Non-lazy (as the SwiftUI `ScrollView { VStack }` is): the Get
            // controls and the install result below the fold are BUILT, so
            // nothing about this page's state depends on having scrolled to it.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _overview(),
                    const SizedBox(height: 18),
                    _toolsSection(bundle),
                    const SizedBox(height: 18),
                    _sideEffectsSection(bundle),
                    const SizedBox(height: 18),
                    _useInWorkflowRow(),
                    const SizedBox(height: 18),
                    const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, color: MonokaiTheme.divider),
                    ),
                    const SizedBox(height: 14),
                    _getSection(installed: installed, installing: installing),
                    if (_pendingUntrustedConfirm) ...[
                      const SizedBox(height: 12),
                      _untrustedConfirmRow(),
                    ],
                    if (outcome != null) ...[
                      const SizedBox(height: 12),
                      _resultRow(outcome),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- title bar ----------------------------------------------------------

  Widget _titleBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: MonokaiTheme.surfaceLighter,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MonokaiTheme.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(marketplaceCategoryGlyph(card.category),
                size: 18, color: MonokaiTheme.cyan),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.name,
                    style: MonokaiTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('Publisher: ${card.publisher}',
                    style: MonokaiTheme.labelSmall),
              ],
            ),
          ),
          _trustBadge(),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: widget.onClose ?? () => Navigator.of(context).maybePop(),
            child:
                const Icon(Icons.close, size: 14, color: MonokaiTheme.comment),
          ),
        ],
      ),
    );
  }

  Widget _trustBadge() {
    final trusted = card.isTrusted;
    final color = trusted ? MonokaiTheme.green : MonokaiTheme.orange;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(trusted ? Icons.verified : Icons.gpp_maybe, size: 12, color: color),
        const SizedBox(width: 4),
        Text(trusted ? 'trusted' : 'untrusted',
            style: MonokaiTheme.labelSmall.copyWith(color: color)),
      ],
    );
  }

  // ---- overview -----------------------------------------------------------

  Widget _overview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('“${card.summary}”',
            style: MonokaiTheme.bodyMedium
                .copyWith(color: MonokaiTheme.textSecondary)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 22,
          runSpacing: 10,
          children: [
            _metaItem('Aisle', card.category.label),
            _metaItem('Stage', card.stage),
            _metaItem('Runs on', card.placement),
            _metaItem('Rating',
                card.rating > 0 ? '${card.rating.toStringAsFixed(0)} / 5' : '—'),
          ],
        ),
      ],
    );
  }

  Widget _metaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style:
                MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.comment)),
        const SizedBox(height: 2),
        Text(value, style: MonokaiTheme.labelMedium),
      ],
    );
  }

  // ---- tools --------------------------------------------------------------

  /// The bundle's tools, read straight off the device catalog. A listing that
  /// has not landed has NO tool list to show — saying so is the honest state,
  /// and it resolves the moment the install below succeeds.
  Widget _toolsSection(InstalledPlugin? bundle) {
    final tools = bundle?.tools ?? const <InstalledPluginTool>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Tools', Icons.handyman),
        const SizedBox(height: 8),
        if (bundle == null)
          Text(
            'Tools are declared by the bundle’s manifest, not by this listing — '
            'they are read from the device catalog once “${card.name}” is '
            'installed below.',
            style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment),
          )
        else if (tools.isEmpty)
          Text('${bundle.id} ${bundle.version} declares no tools.',
              style:
                  MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final tool in tools) _toolRow(bundle, tool)],
          ),
      ],
    );
  }

  Widget _toolRow(InstalledPlugin bundle, InstalledPluginTool tool) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: MonokaiTheme.surfaceLighter,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.chevron_right, size: 13, color: MonokaiTheme.cyan),
            const SizedBox(width: 6),
            Expanded(
              child: Text('@${bundle.id}.${tool.name}',
                  style: MonokaiTheme.codeSmall
                      .copyWith(color: MonokaiTheme.foreground)),
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (tool.sideEffects.isEmpty)
                  _effectChip('no side effects', MonokaiTheme.green)
                else
                  for (final effect in tool.sideEffects)
                    _effectChip(effect, MonokaiTheme.orange),
                if (tool.requiresApproval)
                  _effectChip('needs approval', MonokaiTheme.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _effectChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: MonokaiTheme.labelSmall.copyWith(color: color)),
    );
  }

  // ---- side effects -------------------------------------------------------

  Widget _sideEffectsSection(InstalledPlugin? bundle) {
    final outward = card.sideEffect == PluginSideEffect.externalSend;
    // Every gated label the landed bundle actually declares, deduped — the
    // engine owns this vocabulary, so it is carried, never re-judged.
    final declared = <String>{
      for (final t in bundle?.tools ?? const <InstalledPluginTool>[])
        ...t.sideEffects,
    }.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Side effects', Icons.warning_amber),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (outward ? MonokaiTheme.orange : MonokaiTheme.green)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(outward ? Icons.outbound : Icons.visibility,
                  size: 13,
                  color: outward ? MonokaiTheme.orange : MonokaiTheme.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  outward
                      ? 'sends out — this plugin sends your material to a '
                          'service outside the mesh. A run pauses for approval '
                          'before it does.'
                      : 'read-only — this plugin reads your material and '
                          'writes back into the mesh; nothing leaves it.',
                  style: MonokaiTheme.bodySmall
                      .copyWith(color: MonokaiTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
        if (declared.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Text('declared by the bundle:',
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.comment)),
              for (final effect in declared)
                _effectChip(effect, MonokaiTheme.orange),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 13, color: MonokaiTheme.cyan),
        const SizedBox(width: 6),
        Text(title, style: MonokaiTheme.labelLarge),
      ],
    );
  }

  // ---- use in a workflow --------------------------------------------------

  Widget _useInWorkflowRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _actionButton(
          label: _queuedForWorkflow
              ? 'Queued for a board’s Workflow'
              : 'Use in a workflow',
          icon: _queuedForWorkflow ? Icons.move_to_inbox : Icons.playlist_add,
          tint: MonokaiTheme.purple,
          enabled: true,
          onTap: () {
            widget.onUse?.call(card);
            setState(() => _queuedForWorkflow = true);
          },
        ),
        const SizedBox(height: 6),
        Text(
          _queuedForWorkflow
              ? 'Open a board’s Workflow to drop in this step. Queuing isn’t '
                  'installing.'
              : 'Adds “@${card.bundleId}” as a step in a board’s workflow — '
                  'this doesn’t install it.',
          style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.comment),
        ),
      ],
    );
  }

  // ---- get ----------------------------------------------------------------

  Widget _getSection({required bool installed, required bool installing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Get', style: MonokaiTheme.labelLarge),
        const SizedBox(height: 10),
        if (installed)
          _installedRow()
        else if (installing)
          _installingRow()
        else
          _actionButton(
            label: 'Install on this device',
            icon: Icons.laptop_mac,
            tint: MonokaiTheme.green,
            enabled: true,
            onTap: _startInstall,
          ),
        const SizedBox(height: 6),
        Text(
          installed
              ? 'The bundle is in this group’s Plugins workspace — '
                  '@${card.bundleId} resolves offline.'
              : 'Lands in this group’s Plugins workspace and runs on this '
                  'machine.',
          style: MonokaiTheme.labelSmall.copyWith(color: MonokaiTheme.comment),
        ),
      ],
    );
  }

  Widget _installedRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: MonokaiTheme.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.green.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 13, color: MonokaiTheme.green),
          const SizedBox(width: 6),
          Text('Installed',
              style:
                  MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.green)),
        ],
      ),
    );
  }

  Widget _installingRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: MonokaiTheme.cyan),
        ),
        const SizedBox(width: 8),
        Text('Installing…',
            style: MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.cyan)),
      ],
    );
  }

  void _startInstall() {
    // §13: an untrusted (public-registry) plugin warns first.
    if (!card.isTrusted) {
      setState(() => _pendingUntrustedConfirm = true);
      return;
    }
    _doInstall();
  }

  void _doInstall() {
    ref
        .read(marketplaceControllerProvider(widget.groupId).notifier)
        .install(card);
  }

  Widget _untrustedConfirmRow() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MonokaiTheme.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.gpp_maybe, size: 13, color: MonokaiTheme.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '“${card.name}” comes from the public registry and isn’t '
                  'curated by Lens. It will be installed sandboxed and '
                  'isolated, and you can remove it anytime.',
                  style: MonokaiTheme.bodySmall
                      .copyWith(color: MonokaiTheme.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => setState(() => _pendingUntrustedConfirm = false),
                child: Text('Cancel',
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.comment)),
              ),
              const SizedBox(width: 12),
              _actionButton(
                label: 'Install anyway',
                icon: Icons.gpp_maybe,
                tint: MonokaiTheme.orange,
                enabled: true,
                onTap: () {
                  setState(() => _pendingUntrustedConfirm = false);
                  _doInstall();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultRow(PluginInstallOutcome outcome) {
    final color = outcome.ok ? MonokaiTheme.green : MonokaiTheme.orange;
    return Container(
      padding: const EdgeInsets.all(10),
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
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color tint,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? tint : MonokaiTheme.border,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 13,
                  color: enabled
                      ? MonokaiTheme.background
                      : MonokaiTheme.textDisabled),
              const SizedBox(width: 6),
              Text(label,
                  style: MonokaiTheme.labelMedium.copyWith(
                      color: enabled
                          ? MonokaiTheme.background
                          : MonokaiTheme.textDisabled)),
            ],
          ),
        ),
      ),
    );
  }
}
