// widgets/parity/parity_settings_view.dart
//
// PARITY port of the SwiftUI `SettingsView` — the settings shell: a header, a
// sidebar of tabs, and a scrolling content pane, each tab reading and WRITING
// through the one `CyanBackend` seam.
//
//   • Preferences — the device's craft role (`cyan_get/set_production_role`)
//     and its per-scope anonymous session. Both are real, persisted engine
//     state: a change is written through the seam and then READ BACK, so what
//     the screen shows is what the engine kept, not what was typed.
//   • Groups      — `GroupTransferSettings`: export a signed `.cyangroup`
//     bundle sealed to this device's bundle key, import one back, and issue /
//     scan a capability-grant invite (`ParityGroupInvite`).
//   • Identity    — who this device is on the mesh (node id, bundle key, live
//     peers, engine build) and the one irreversible door out, Delete Identity.
//
// The SwiftUI Appearance and Shortcuts tabs are NOT ported: this app has one
// theme and no shortcut registry to render from, and a tab that renders a
// control wired to nothing is not a face.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/SettingsView.swift
//   cyan-iOS/Cyan/Cyan/Views/GroupTransferView.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../providers/settings_identity_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_group_invite.dart';

/// The settings sidebar's tabs.
enum SettingsTab {
  preferences('Preferences', Icons.tune),
  groups('Groups', Icons.ios_share),
  identity('Identity', Icons.badge_outlined);

  const SettingsTab(this.title, this.icon);
  final String title;
  final IconData icon;
}

class ParitySettingsView extends ConsumerStatefulWidget {
  /// The scope (a board / workspace id) the anonymous-mode preference applies
  /// to. Empty hides that preference — anonymity is per scope, never global.
  final String scopeId;

  /// Dismisses the panel; null hides the close affordance.
  final VoidCallback? onClose;

  const ParitySettingsView({super.key, this.scopeId = '', this.onClose});

  @override
  ConsumerState<ParitySettingsView> createState() => _ParitySettingsViewState();
}

class _ParitySettingsViewState extends ConsumerState<ParitySettingsView> {
  SettingsTab _tab = SettingsTab.preferences;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onClose: widget.onClose),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 200,
                  child: _Sidebar(
                    tab: _tab,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                ),
                const VerticalDivider(width: 1, color: MonokaiTheme.divider),
                Expanded(
                  child: ListView(
                    key: ValueKey('settings-pane-${_tab.name}'),
                    padding: const EdgeInsets.all(20),
                    children: [
                      switch (_tab) {
                        SettingsTab.preferences =>
                          _PreferencesTab(scopeId: widget.scopeId),
                        SettingsTab.groups => const _GroupsTab(),
                        SettingsTab.identity => const _IdentityTab(),
                      },
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Chrome

class _Header extends StatelessWidget {
  final VoidCallback? onClose;
  const _Header({this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: MonokaiTheme.surface.withValues(alpha: 0.5),
      child: Row(
        children: [
          Text('Settings',
              style: MonokaiTheme.titleMedium
                  .copyWith(color: MonokaiTheme.foreground)),
          const Spacer(),
          if (onClose != null)
            GestureDetector(
              key: const ValueKey('settings-close'),
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: MonokaiTheme.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close,
                    size: 12, color: MonokaiTheme.comment),
              ),
            ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  final SettingsTab tab;
  final ValueChanged<SettingsTab> onChanged;

  const _Sidebar({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commit = ref.watch(deviceIdentityProvider).asData?.value.buildCommit;
    return Container(
      color: MonokaiTheme.background,
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in SettingsTab.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: GestureDetector(
                key: ValueKey('settings-tab-${t.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(t),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: t == tab ? MonokaiTheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(t.icon,
                          size: 14,
                          color: t == tab
                              ? MonokaiTheme.cyan
                              : MonokaiTheme.comment),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          t.title,
                          overflow: TextOverflow.ellipsis,
                          style: MonokaiTheme.labelMedium.copyWith(
                            color: t == tab
                                ? MonokaiTheme.foreground
                                : MonokaiTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Spacer(),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Text(
              // The engine's own build stamp, so a bug report names the exact
              // binary. No fabricated app version.
              commit == null || commit.isEmpty
                  ? 'Engine not loaded'
                  : 'Engine ${commit.substring(0, commit.length.clamp(0, 8))}',
              style:
                  MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.comment),
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Preferences

class _PreferencesTab extends ConsumerStatefulWidget {
  final String scopeId;
  const _PreferencesTab({required this.scopeId});

  @override
  ConsumerState<_PreferencesTab> createState() => _PreferencesTabState();
}

class _PreferencesTabState extends ConsumerState<_PreferencesTab> {
  String? _notice;
  bool _noticeIsError = false;
  bool _working = false;

  Future<void> _setRole(String role) async {
    if (_working) return;
    setState(() => _working = true);
    final ok = await ref.read(cyanBackendProvider).setProductionRole(role);

    // Read the pref back off the engine — and the roster with it, since every
    // row's craft role is resolved from the same place.
    ref.invalidate(productionRoleProvider);
    ref.invalidate(groupRosterProvider);

    if (!mounted) return;
    setState(() {
      _working = false;
      _noticeIsError = !ok;
      _notice = ok
          ? (role.isEmpty
              ? 'Craft role cleared.'
              : 'Saved — you author as $role.')
          : 'The engine refused “$role” — the pref is unchanged.';
    });
  }

  Future<void> _setAnonymous(bool on) async {
    if (_working || widget.scopeId.isEmpty) return;
    setState(() => _working = true);
    final backend = ref.read(cyanBackendProvider);
    if (on) {
      await backend.createAnonymousSession(widget.scopeId);
    } else {
      await backend.exitAnonymousMode(widget.scopeId);
    }
    ref.invalidate(anonymousStatusProvider(widget.scopeId));
    if (!mounted) return;
    setState(() => _working = false);
  }

  Future<void> _reveal() async {
    if (_working || widget.scopeId.isEmpty) return;
    setState(() => _working = true);
    await ref.read(cyanBackendProvider).revealAnonymousIdentity(widget.scopeId);
    ref.invalidate(anonymousStatusProvider(widget.scopeId));
    if (!mounted) return;
    setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final vocab =
        ref.watch(craftRoleVocabProvider).asData?.value ?? const <String>[];
    final role = ref.watch(productionRoleProvider).asData?.value ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
            title: 'Craft role', icon: Icons.movie_filter_outlined),
        const SizedBox(height: 8),
        Text(
          'Device-local: it steers what your surfaces open on and is stamped '
          'on every note you author. It is never synced to the mesh.',
          style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in vocab)
              _Chip(
                key: ValueKey('settings-role-$r'),
                label: r.replaceAll('_', ' '),
                selected: r == role,
                onTap: () => _setRole(r),
              ),
            if (role.isNotEmpty)
              _Chip(
                key: const ValueKey('settings-role-clear'),
                label: 'clear',
                selected: false,
                onTap: () => _setRole(''),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('Current',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.comment)),
            const SizedBox(width: 8),
            Text(
              role.isEmpty ? 'unset' : role,
              key: const ValueKey('settings-role-current'),
              style: MonokaiTheme.codeSmall.copyWith(
                color:
                    role.isEmpty ? MonokaiTheme.comment : MonokaiTheme.yellow,
              ),
            ),
          ],
        ),
        if (_notice != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                  _noticeIsError
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle,
                  size: 12,
                  color: _noticeIsError
                      ? MonokaiTheme.orange
                      : MonokaiTheme.green),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _notice!,
                  key: const ValueKey('settings-pref-notice'),
                  style: MonokaiTheme.labelSmall.copyWith(
                    color: _noticeIsError
                        ? MonokaiTheme.orange
                        : MonokaiTheme.green,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (widget.scopeId.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Divider(height: 1, color: MonokaiTheme.divider),
          const SizedBox(height: 22),
          const _SectionHeader(
              title: 'Anonymous mode', icon: Icons.masks_outlined),
          const SizedBox(height: 8),
          _AnonymousPreference(
            scopeId: widget.scopeId,
            onToggle: _setAnonymous,
            onReveal: _reveal,
          ),
        ],
      ],
    );
  }
}

class _AnonymousPreference extends ConsumerWidget {
  final String scopeId;
  final ValueChanged<bool> onToggle;
  final VoidCallback onReveal;

  const _AnonymousPreference({
    required this.scopeId,
    required this.onToggle,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(anonymousStatusProvider(scopeId)).asData?.value ??
        const AnonymousStatus.none();
    final profile = ref.watch(deviceIdentityProvider).asData?.value.profile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'An ephemeral key stands in for your real one in this scope. Peers '
          'see the handle; revealing binds the two with a signature the group '
          'can check, and is one-way.',
          style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                status.anonymous
                    ? 'Masked as ${status.handle ?? '—'}'
                    : 'Visible as ${profile?.label ?? '—'}',
                key: const ValueKey('settings-anon-status'),
                style: MonokaiTheme.bodySmall.copyWith(
                  color: status.anonymous
                      ? MonokaiTheme.purple
                      : MonokaiTheme.foreground,
                ),
              ),
            ),
            Switch(
              key: const ValueKey('settings-anon-toggle'),
              value: status.anonymous,
              activeThumbColor: MonokaiTheme.purple,
              onChanged: onToggle,
            ),
          ],
        ),
        if (status.anonymous && !status.revealed)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _Chip(
                key: const ValueKey('settings-anon-reveal'),
                label: 'reveal my identity',
                selected: false,
                onTap: onReveal,
              ),
            ),
          ),
        if (status.revealed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Revealed — this handle is provably you now.',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.green)),
          ),
      ],
    );
  }
}

// MARK: - Groups (transfer + invite)

class _GroupsTab extends ConsumerStatefulWidget {
  const _GroupsTab();

  @override
  ConsumerState<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends ConsumerState<_GroupsTab> {
  final TextEditingController _bundle = TextEditingController();
  String _selected = '';
  GroupExportResult? _export;
  GroupImportResult? _import;
  bool _working = false;

  @override
  void dispose() {
    _bundle.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    if (_selected.isEmpty || _working) return;
    setState(() => _working = true);
    final backend = ref.read(cyanBackendProvider);
    // Sealed TO this device's bundle key, so the export can be re-imported here
    // and nowhere else.
    final pubkey = await backend.bundlePubkey() ?? '';
    final result = await backend.exportGroup(_selected, pubkey);
    if (!mounted) return;
    setState(() {
      _export = result;
      _working = false;
      if (result.success) _bundle.text = result.bundle;
    });
  }

  Future<void> _importBundle() async {
    final body = _bundle.text.trim();
    if (body.isEmpty || _working) return;
    setState(() => _working = true);
    final result = await ref.read(cyanBackendProvider).importGroup(body);
    if (result.success) ref.invalidate(groupsProvider);
    if (!mounted) return;
    setState(() {
      _import = result;
      _working = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups =
        ref.watch(groupsProvider).asData?.value ?? const <CyanGroup>[];
    if (_selected.isEmpty && groups.isNotEmpty) _selected = groups.first.id;
    final export = _export;
    final import = _import;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: 'Download group', icon: Icons.ios_share),
        const SizedBox(height: 8),
        Text(
          'Export a signed bundle you can share out-of-band. Whoever you share '
          'it with can seed the group offline — no network needed.',
          style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment),
        ),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          Text('No groups yet — create one first.',
              style:
                  MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment))
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in groups)
                _Chip(
                  key: ValueKey('settings-export-${g.id}'),
                  label: g.name,
                  selected: g.id == _selected,
                  onTap: () => setState(() => _selected = g.id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _Chip(
              key: const ValueKey('settings-export-run'),
              label: 'Download group',
              selected: true,
              onTap: _download,
            ),
          ),
        ],
        if (export != null) ...[
          const SizedBox(height: 10),
          Text(
            export.success
                ? 'Saved to ${export.path}'
                : export.error ?? 'The engine refused the export.',
            key: const ValueKey('settings-export-status'),
            style: MonokaiTheme.labelSmall.copyWith(
              color: export.success ? MonokaiTheme.green : MonokaiTheme.orange,
            ),
          ),
        ],
        const SizedBox(height: 22),
        const Divider(height: 1, color: MonokaiTheme.divider),
        const SizedBox(height: 22),
        const _SectionHeader(
            title: 'Import group from a bundle', icon: Icons.download),
        const SizedBox(height: 8),
        Text(
          'Paste a .cyangroup bundle to seed that group on this device, fully '
          'offline. The engine verifies the signature and the grant scope '
          'before anything lands.',
          style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: MonokaiTheme.background,
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: MonokaiTheme.comment.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: TextField(
            key: const ValueKey('settings-import-field'),
            controller: _bundle,
            minLines: 3,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            style:
                MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.foreground),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              hintText: 'Paste the bundle body',
              hintStyle:
                  MonokaiTheme.codeSmall.copyWith(color: MonokaiTheme.comment),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: _Chip(
            key: const ValueKey('settings-import-run'),
            label: 'Import group',
            selected: true,
            onTap: _importBundle,
          ),
        ),
        if (import != null) ...[
          const SizedBox(height: 10),
          Text(
            import.success
                ? 'Imported ${import.groupId}'
                : import.error ?? 'The engine refused the bundle.',
            key: const ValueKey('settings-import-status'),
            style: MonokaiTheme.labelSmall.copyWith(
              color: import.success ? MonokaiTheme.green : MonokaiTheme.orange,
            ),
          ),
        ],
        const SizedBox(height: 22),
        const Divider(height: 1, color: MonokaiTheme.divider),
        const SizedBox(height: 22),
        const ParityGroupInvite(scrollable: false),
      ],
    );
  }
}

// MARK: - Identity

class _IdentityTab extends ConsumerStatefulWidget {
  const _IdentityTab();

  @override
  ConsumerState<_IdentityTab> createState() => _IdentityTabState();
}

class _IdentityTabState extends ConsumerState<_IdentityTab> {
  bool _working = false;

  Future<void> _deleteIdentity() async {
    if (_working) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: MonokaiTheme.surface,
            title: Text("Delete this device's identity?",
                style: MonokaiTheme.titleSmall
                    .copyWith(color: MonokaiTheme.foreground)),
            content: Text(
              'This wipes your XaeroID from this device. Everything keyed to '
              'the old identity is orphaned. It cannot be undone.',
              style: MonokaiTheme.bodySmall
                  .copyWith(color: MonokaiTheme.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel',
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.comment)),
              ),
              TextButton(
                key: const ValueKey('settings-identity-delete-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Delete identity',
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.red)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _working = true);
    await ref.read(cyanBackendProvider).deleteIdentity();
    ref.invalidate(deviceIdentityProvider);
    ref.invalidate(groupRosterProvider);
    if (!mounted) return;
    setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(deviceIdentityProvider).asData?.value;
    final profile = identity?.profile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
            title: 'This device on the mesh', icon: Icons.hub_outlined),
        const SizedBox(height: 12),
        if (profile == null)
          Text(
            'No identity on this device — a new one is minted on next launch.',
            key: const ValueKey('settings-identity-none'),
            style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.orange),
          )
        else ...[
          _InfoRow(label: 'Display name', value: profile.label),
          _InfoRow(
              label: 'Node ID',
              value: profile.nodeId,
              valueKey: const ValueKey('settings-identity-node')),
          _InfoRow(label: 'Bundle key', value: _short(identity?.bundlePubkey)),
        ],
        _InfoRow(
            label: 'Live peers',
            value: '${identity?.presence.totalPeers ?? 0}'),
        _InfoRow(label: 'Engine build', value: _short(identity?.buildCommit)),
        const SizedBox(height: 22),
        const Divider(height: 1, color: MonokaiTheme.divider),
        const SizedBox(height: 22),
        const _SectionHeader(
            title: 'Identity', icon: Icons.person_off_outlined),
        const SizedBox(height: 8),
        Text(
          'Deleting your identity wipes this device’s XaeroID from the vault. '
          'A new one is minted next run and everything keyed to the old one is '
          'orphaned.',
          style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            key: const ValueKey('settings-identity-delete'),
            behavior: HitTestBehavior.opaque,
            onTap: profile == null ? null : _deleteIdentity,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: MonokaiTheme.red
                    .withValues(alpha: profile == null ? 0.05 : 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.no_accounts,
                      size: 13,
                      color: profile == null
                          ? MonokaiTheme.comment
                          : MonokaiTheme.red),
                  const SizedBox(width: 6),
                  Text('Delete Identity',
                      style: MonokaiTheme.labelMedium.copyWith(
                        color: profile == null
                            ? MonokaiTheme.comment
                            : MonokaiTheme.red,
                      )),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _short(String? value) {
    if (value == null || value.isEmpty) return '—';
    return value.length <= 16 ? value : '${value.substring(0, 16)}…';
  }
}

// MARK: - Shared pieces

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: MonokaiTheme.cyan),
        const SizedBox(width: 8),
        Flexible(
          child: Text(title,
              overflow: TextOverflow.ellipsis,
              style: MonokaiTheme.titleSmall
                  .copyWith(color: MonokaiTheme.foreground)),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Key? valueKey;

  const _InfoRow({required this.label, required this.value, this.valueKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(label,
              style: MonokaiTheme.bodySmall
                  .copyWith(color: MonokaiTheme.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              key: valueKey,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? MonokaiTheme.cyan.withValues(alpha: 0.18)
              : MonokaiTheme.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? MonokaiTheme.cyan.withValues(alpha: 0.6)
                : MonokaiTheme.comment.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: MonokaiTheme.labelSmall.copyWith(
            color: selected ? MonokaiTheme.cyan : MonokaiTheme.comment,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
