// widgets/parity/parity_plugins_workspace.dart
//
// PARITY face: the Plugins workspace — what a group has INSTALLED, and how each
// bundle is configured. This is stage D of the engine's
// PLUGIN_CREDENTIAL_ONBOARDING design: "a plugin-settings sheet writing
// `plugin_config` rows", the UI the stage-A/C FFI was built for.
//
// There is no SwiftUI counterpart to mirror — the shipping macOS app binds
// `cyan_plugin_catalog` and stops there. The BEHAVIOUR reference is therefore
// the engine itself: `cyan-backend/src/plugin_config.rs` plus that design doc.
//
// The load-bearing split this face exists to make visible:
//
//   CONFIG      non-secret targets (account_id, folder_id, a C2C project).
//               Scoped group -> board, stored as plain rows in `plugin_config`,
//               resolved into tool ARGS at bind time. Editable here.
//
//   CREDENTIAL  the client's own token / API key. Belongs to the DEVICE VAULT,
//               injected as spawn ENV, read fresh at every spawn. It never
//               becomes a config row — the engine's write API refuses a
//               secret-looking key outright.
//
// So the composer watches the key as it is typed: the moment it looks like
// credential material the value becomes a SECURE field and the face says where
// that value actually belongs. The write still goes to the engine — this widget
// never pre-empts the engine's judgement — and the refusal is rendered
// verbatim, then the secret is cleared from the field rather than left sitting
// in a text box.
//
// Driven ENTIRELY through the `CyanBackend` seam (`pluginCatalogProvider` /
// `pluginConfigProvider`). This widget never touches `CyanFFI` directly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityPluginsWorkspace extends ConsumerStatefulWidget {
  /// The group whose config rows are read/written. Null = the first group the
  /// engine reports, which is what the workspace opens on.
  final String? groupId;

  const ParityPluginsWorkspace({super.key, this.groupId});

  @override
  ConsumerState<ParityPluginsWorkspace> createState() =>
      _ParityPluginsWorkspaceState();
}

class _ParityPluginsWorkspaceState
    extends ConsumerState<ParityPluginsWorkspace> {
  String? _selectedPluginId;
  String? _selectedGroupId;

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);
    final catalogAsync = ref.watch(pluginCatalogProvider);

    final groups = groupsAsync.asData?.value ?? const <CyanGroup>[];
    final groupId = _selectedGroupId ??
        widget.groupId ??
        (groups.isNotEmpty ? groups.first.id : '');

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            groups: groups,
            selectedGroupId: groupId,
            onSelectGroup: (id) => setState(() {
              _selectedGroupId = id;
              _selectedPluginId = null;
            }),
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: catalogAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: MonokaiTheme.cyan),
              ),
              error: (e, _) => Center(
                child: Text('Failed to load plugins: $e',
                    style: MonokaiTheme.bodyMedium
                        .copyWith(color: MonokaiTheme.red)),
              ),
              data: (bundles) {
                if (bundles.isEmpty) return const _NoBundles();
                final selected = bundles.firstWhere(
                  (b) => b.id == _selectedPluginId,
                  orElse: () => bundles.first,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 240,
                      child: _BundleRail(
                        bundles: bundles,
                        selectedId: selected.id,
                        onSelect: (id) =>
                            setState(() => _selectedPluginId = id),
                      ),
                    ),
                    const VerticalDivider(
                        width: 1, color: MonokaiTheme.divider),
                    Expanded(
                      child: _BundleDetail(
                        key: ValueKey('${groupId}_${selected.id}'),
                        groupId: groupId,
                        bundle: selected,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final List<CyanGroup> groups;
  final String selectedGroupId;
  final void Function(String) onSelectGroup;

  const _Header({
    required this.groups,
    required this.selectedGroupId,
    required this.onSelectGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.extension, size: 18, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Text('Plugins', style: MonokaiTheme.titleSmall),
          const SizedBox(width: 20),
          // The group IS the engine's tenant: every config row on this face is
          // scoped to it, so it is named, not implied.
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in groups)
                  _GroupChip(
                    group: g,
                    selected: g.id == selectedGroupId,
                    onTap: () => onSelectGroup(g.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final CyanGroup group;
  final bool selected;
  final VoidCallback onTap;

  const _GroupChip(
      {required this.group, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? MonokaiTheme.cyan.withValues(alpha: 0.15)
              : MonokaiTheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? MonokaiTheme.cyan.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Text(
          group.name,
          style: MonokaiTheme.labelMedium.copyWith(
            color: selected ? MonokaiTheme.cyan : MonokaiTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// No bundle is installed. An honest empty state — not a spinner, and not an
/// invented catalog: a device with no plugins root reads back exactly this.
class _NoBundles extends StatelessWidget {
  const _NoBundles();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_off, size: 28, color: MonokaiTheme.comment),
          const SizedBox(height: 10),
          Text('No plugin bundles installed',
              style: MonokaiTheme.bodyMedium
                  .copyWith(color: MonokaiTheme.textSecondary)),
          const SizedBox(height: 4),
          Text('Install one from the Marketplace to configure it here.',
              style: MonokaiTheme.labelSmall),
        ],
      ),
    );
  }
}

class _BundleRail extends StatelessWidget {
  final List<InstalledPlugin> bundles;
  final String selectedId;
  final void Function(String) onSelect;

  const _BundleRail({
    required this.bundles,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MonokaiTheme.surfaceLighter,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Text('Installed bundles',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.comment)),
          ),
          for (final b in bundles)
            _BundleRow(
              bundle: b,
              selected: b.id == selectedId,
              onTap: () => onSelect(b.id),
            ),
        ],
      ),
    );
  }
}

class _BundleRow extends StatelessWidget {
  final InstalledPlugin bundle;
  final bool selected;
  final VoidCallback onTap;

  const _BundleRow(
      {required this.bundle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // A bundle that carries a gated tool is the one that will stop a run for a
    // human; the rail says so before it is opened.
    final gated = bundle.tools.any((t) => t.requiresApproval);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        color: selected ? MonokaiTheme.selection : Colors.transparent,
        child: Row(
          children: [
            Icon(Icons.widgets,
                size: 13,
                color: selected ? MonokaiTheme.cyan : MonokaiTheme.comment),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bundle.id,
                      style: MonokaiTheme.bodySmall.copyWith(
                        color: selected
                            ? MonokaiTheme.foreground
                            : MonokaiTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Text('v${bundle.version} · ${bundle.tools.length} tools',
                      style: MonokaiTheme.labelSmall),
                ],
              ),
            ),
            if (gated)
              const Icon(Icons.front_hand,
                  size: 11, color: MonokaiTheme.orange),
          ],
        ),
      ),
    );
  }
}

class _BundleDetail extends ConsumerStatefulWidget {
  final String groupId;
  final InstalledPlugin bundle;

  const _BundleDetail({super.key, required this.groupId, required this.bundle});

  @override
  ConsumerState<_BundleDetail> createState() => _BundleDetailState();
}

class _BundleDetailState extends ConsumerState<_BundleDetail> {
  final _keyController = TextEditingController();
  final _valueController = TextEditingController();

  /// The engine's verbatim refusal of the last write, if it refused.
  String? _writeError;

  /// The key of the last row the engine accepted — a confirmation the row
  /// LANDED, distinct from the field simply having been typed into.
  String? _savedKey;

  @override
  void initState() {
    super.initState();
    // The composer re-renders as the key is typed: a key that looks like
    // credential material turns the value into a secure field, before any
    // round trip.
    _keyController.addListener(_onKeyChanged);
  }

  @override
  void dispose() {
    _keyController.removeListener(_onKeyChanged);
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _onKeyChanged() => setState(() {});

  bool get _keyIsSecret => pluginConfigKeyLooksSecret(_keyController.text);

  Future<void> _save() async {
    final key = _keyController.text.trim();
    final value = _valueController.text;
    if (key.isEmpty) return;

    final backend = ref.read(cyanBackendProvider);
    final result = await backend.pluginConfigSet(
        widget.groupId, widget.bundle.id, key, value);
    if (!mounted) return;

    setState(() {
      _writeError = result.ok ? null : result.error;
      _savedKey = result.ok ? key : null;
      if (result.ok) {
        _keyController.clear();
        _valueController.clear();
      } else if (pluginConfigKeyLooksSecret(key)) {
        // The engine refused a secret. Do not leave it sitting in a text box
        // waiting to be retried — it does not belong in this face at all.
        _valueController.clear();
      }
    });

    if (result.ok) {
      // Re-read from the engine rather than patching a local copy, so what is
      // on screen is what was actually stored.
      ref.invalidate(pluginConfigProvider(
          (groupId: widget.groupId, pluginId: widget.bundle.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    final configAsync = ref.watch(pluginConfigProvider(
        (groupId: widget.groupId, pluginId: bundle.id)));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text(bundle.id, style: MonokaiTheme.titleSmall),
            const SizedBox(width: 8),
            _chip('v${bundle.version}'),
          ],
        ),
        const SizedBox(height: 16),
        _sectionLabel(Icons.build, 'Tools'),
        const SizedBox(height: 8),
        for (final t in bundle.tools) _ToolRow(tool: t),
        const SizedBox(height: 20),
        _sectionLabel(Icons.tune, 'Configuration'),
        const SizedBox(height: 4),
        Text(
          'Non-secret targets, scoped to this group. Resolved into tool '
          'arguments at bind time.',
          style: MonokaiTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        configAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(
                color: MonokaiTheme.cyan, backgroundColor: MonokaiTheme.surface),
          ),
          error: (e, _) => Text('Failed to read configuration: $e',
              style:
                  MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.red)),
          data: (config) => _configBody(config),
        ),
        const SizedBox(height: 20),
        _sectionLabel(Icons.add_circle_outline, 'Add or update a value'),
        const SizedBox(height: 8),
        _composer(),
      ],
    );
  }

  Widget _configBody(PluginConfig config) {
    // A read the engine could not serve says so verbatim — an empty sheet must
    // never be mistaken for "configured with nothing".
    if (config.error != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: MonokaiTheme.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('Configuration unavailable: ${config.error}',
            style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.red)),
      );
    }
    if (config.isEmpty) {
      return Text('No configuration set — this plugin runs on its defaults.',
          style: MonokaiTheme.bodySmall
              .copyWith(color: MonokaiTheme.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in config.values.entries)
          _ConfigRow(configKey: entry.key, value: entry.value),
      ],
    );
  }

  Widget _composer() {
    final secret = _keyIsSecret;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _field(
                controller: _keyController,
                hint: 'key (e.g. folder_id)',
                label: 'Key',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: _field(
                controller: _valueController,
                hint: secret ? 'credential — goes to the vault' : 'value',
                label: secret ? 'Value (secure)' : 'Value',
                // A credential is NEVER rendered in plain text, not even in
                // the box it was mistakenly typed into.
                obscure: secret,
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.cyan,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Save',
                      style: MonokaiTheme.labelMedium
                          .copyWith(color: MonokaiTheme.background)),
                ),
              ),
            ),
          ],
        ),
        if (secret) ...[
          const SizedBox(height: 10),
          _notice(
            icon: Icons.key_off,
            color: MonokaiTheme.orange,
            text: 'That key names credential material. Credentials are held in '
                'the device vault and injected fresh at every spawn — '
                'configuration stores non-secret targets only.',
          ),
        ],
        if (_writeError != null) ...[
          const SizedBox(height: 10),
          // The engine's own words. It names the key and points at the vault;
          // re-wording it would lose the instruction.
          _notice(
            icon: Icons.block,
            color: MonokaiTheme.red,
            text: _writeError!,
          ),
        ],
        if (_savedKey != null) ...[
          const SizedBox(height: 10),
          _notice(
            icon: Icons.check_circle_outline,
            color: MonokaiTheme.green,
            text: 'Saved $_savedKey',
          ),
        ],
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required String label,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: MonokaiTheme.labelSmall),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          obscuringCharacter: '•',
          style: MonokaiTheme.codeSmall
              .copyWith(color: MonokaiTheme.foreground),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: MonokaiTheme.codeSmall
                .copyWith(color: MonokaiTheme.textDisabled),
            filled: true,
            fillColor: MonokaiTheme.surface.withValues(alpha: 0.6),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _notice(
      {required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: MonokaiTheme.bodySmall.copyWith(color: color)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: MonokaiTheme.cyan),
        const SizedBox(width: 8),
        Text(text, style: MonokaiTheme.labelLarge),
      ],
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
}

class _ToolRow extends StatelessWidget {
  final InstalledPluginTool tool;

  const _ToolRow({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.chevron_right, size: 13, color: MonokaiTheme.comment),
          const SizedBox(width: 4),
          Text(tool.name,
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.foreground)),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final s in tool.sideEffects)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: MonokaiTheme.orange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(s,
                        style: MonokaiTheme.labelSmall
                            .copyWith(color: MonokaiTheme.orange)),
                  ),
              ],
            ),
          ),
          if (tool.requiresApproval)
            Text('approval',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.orange)),
        ],
      ),
    );
  }
}

/// One stored config row.
///
/// `plugin_config` cannot hold a secret — the write API refuses one — so every
/// row here is a non-secret target and reads plainly. A row whose key names
/// credential material could only have come from outside that guard, so it is
/// masked rather than trusted and printed.
class _ConfigRow extends StatelessWidget {
  final String configKey;
  final String value;

  const _ConfigRow({required this.configKey, required this.value});

  @override
  Widget build(BuildContext context) {
    final secret = pluginConfigKeyLooksSecret(configKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(configKey,
                style: MonokaiTheme.codeSmall
                    .copyWith(color: MonokaiTheme.textSecondary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              secret ? '•' * 12 : value,
              style: MonokaiTheme.codeSmall.copyWith(
                color:
                    secret ? MonokaiTheme.comment : MonokaiTheme.foreground,
              ),
            ),
          ),
          if (secret)
            const Icon(Icons.lock_outline, size: 12, color: MonokaiTheme.orange),
        ],
      ),
    );
  }
}
