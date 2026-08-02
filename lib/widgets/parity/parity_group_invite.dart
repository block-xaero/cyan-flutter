// widgets/parity/parity_group_invite.dart
//
// PARITY port of the SwiftUI `GrantQRView` (+ `GrantQRViewModel`) — the
// capability-grant invite: issue one, scan one.
//
//   • ISSUE — mint a signed grant QR for a {group, role}. Only the group's
//     Owner/Admin may, and the ENGINE runs that gate, so a refusal comes back
//     from it (authority · unknown role · unknown group) and is shown verbatim
//     rather than pre-judged here.
//   • SCAN  — hand a payload to the engine, which verifies signature · issuer
//     admin · expiry · nonce/anti-replay · revocation and, on success, JOINS
//     the group. A forged, expired or revoked QR comes back as a refusal.
//
// Driven ENTIRELY through the `CyanBackend` seam, so the whole issue→scan
// round trip runs against `FakeCyanBackend` with no dylib.
//
// SwiftUI reference (read-only): cyan-iOS/Cyan/Cyan/Views/Auth/GrantQRView.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityGroupInvite extends ConsumerStatefulWidget {
  /// Pre-selects a group; empty selects the first one the mesh answers with.
  final String groupId;

  /// False when this face is embedded in a surface that already scrolls (the
  /// Settings ▸ Groups tab) — it then lays out as a plain column.
  final bool scrollable;

  const ParityGroupInvite({
    super.key,
    this.groupId = '',
    this.scrollable = true,
  });

  @override
  ConsumerState<ParityGroupInvite> createState() => _ParityGroupInviteState();
}

class _ParityGroupInviteState extends ConsumerState<ParityGroupInvite> {
  /// The grant roles the engine's `Role::parse` admits, most to least capable.
  /// The ENGINE owns the vocabulary and re-checks it at the mint door, so a
  /// role it no longer admits comes back as a refusal rather than silently
  /// minting.
  static const List<String> _roles = [
    'owner',
    'admin',
    'member',
    'viewer',
    'guest',
  ];

  final TextEditingController _scanPayload = TextEditingController();

  String _selectedGroup = '';
  String _role = 'member';
  GrantQrIssue? _issued;
  GrantScanResult? _scanned;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.groupId;
  }

  @override
  void dispose() {
    _scanPayload.dispose();
    super.dispose();
  }

  Future<void> _issue() async {
    if (_selectedGroup.isEmpty || _working) return;
    setState(() => _working = true);
    final issue =
        await ref.read(cyanBackendProvider).issueGrantQr(_selectedGroup, _role);
    if (!mounted) return;
    setState(() {
      _issued = issue;
      _working = false;
    });
  }

  Future<void> _scan() async {
    final payload = _scanPayload.text.trim();
    if (payload.isEmpty || _working) return;
    setState(() => _working = true);
    final result = await ref.read(cyanBackendProvider).scanGrantQr(payload);
    if (!mounted) return;
    // A successful scan JOINS a group — the tree the rest of the app reads has
    // changed, so it is re-read rather than patched.
    if (result.success) ref.invalidate(groupsProvider);
    setState(() {
      _scanned = result;
      _working = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);

    // Bounded rather than Center-in-a-Column: this face also lays out inside
    // the Settings scroll view, where an unbounded height would not resolve.
    final body = groupsAsync.when(
      loading: () => const SizedBox(
        height: 120,
        child:
            Center(child: CircularProgressIndicator(color: MonokaiTheme.cyan)),
      ),
      error: (e, _) => SizedBox(
        height: 120,
        child: Center(
          child: Text('Failed to load groups: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
      ),
      data: (groups) {
        // Fall back to the first group the mesh knows about.
        if (_selectedGroup.isEmpty && groups.isNotEmpty) {
          _selectedGroup = groups.first.id;
        }
        final sections = [
          _issueSection(groups),
          const SizedBox(height: 16),
          _scanSection(),
        ];
        return widget.scrollable
            ? ListView(padding: const EdgeInsets.all(16), children: sections)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sections,
              );
      },
    );

    return widget.scrollable
        ? Material(color: MonokaiTheme.background, child: body)
        : body;
  }

  // MARK: - Issue

  Widget _issueSection(List<CyanGroup> groups) {
    final issued = _issued;
    return _Card(
      title: 'Issue an invite',
      icon: Icons.qr_code_2,
      blurb: 'Mint a signed capability grant for a group. Whoever scans it '
          'joins with the role it grants — the engine signs it and only an '
          'Owner or Admin may issue one.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (groups.isEmpty)
            Text('No groups yet — create one first.',
                style: MonokaiTheme.bodySmall
                    .copyWith(color: MonokaiTheme.comment))
          else ...[
            Text('Group',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.comment)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final group in groups)
                  _Chip(
                    key: ValueKey('invite-group-${group.id}'),
                    label: group.name,
                    selected: group.id == _selectedGroup,
                    onTap: () => setState(() => _selectedGroup = group.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Role',
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.comment)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final role in _roles)
                  _Chip(
                    key: ValueKey('invite-role-$role'),
                    label: role,
                    selected: role == _role,
                    onTap: () => setState(() => _role = role),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _PillButton(
              key: const ValueKey('invite-issue'),
              label: 'Issue invite',
              icon: Icons.vpn_key,
              onTap: _working ? null : _issue,
            ),
          ],
          if (issued != null) ...[
            const SizedBox(height: 14),
            if (!issued.success)
              _Banner(
                key: const ValueKey('invite-issue-error'),
                text: issued.error ?? 'The engine refused to issue the grant.',
                ok: false,
              )
            else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: QrImageView(
                    key: const ValueKey('invite-qr'),
                    data: issued.qr,
                    version: QrVersions.auto,
                    size: 168,
                    backgroundColor: Colors.white,
                    gapless: true,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _KeyValue(label: 'Grants', value: issued.role),
              _KeyValue(label: 'Expires', value: _utcStamp(issued.expiry)),
              _KeyValue(label: 'Nonce', value: _short(issued.nonce)),
              const SizedBox(height: 8),
              Text('Payload',
                  style: MonokaiTheme.labelSmall
                      .copyWith(color: MonokaiTheme.comment)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: MonokaiTheme.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  issued.qr,
                  key: const ValueKey('invite-payload'),
                  maxLines: 4,
                  style: MonokaiTheme.codeSmall
                      .copyWith(color: MonokaiTheme.textSecondary),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // MARK: - Scan

  Widget _scanSection() {
    final scanned = _scanned;
    return _Card(
      title: 'Scan an invite',
      icon: Icons.qr_code_scanner,
      blurb: 'Paste a grant payload to verify and join. The engine checks the '
          'signature, the issuer’s authority, the expiry and replay before '
          'anything is joined.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: MonokaiTheme.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: MonokaiTheme.comment.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              key: const ValueKey('invite-scan-field'),
              controller: _scanPayload,
              minLines: 3,
              maxLines: 5,
              autocorrect: false,
              enableSuggestions: false,
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.foreground),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: 'Paste grant payload',
                hintStyle: MonokaiTheme.codeSmall
                    .copyWith(color: MonokaiTheme.comment),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _PillButton(
            key: const ValueKey('invite-scan'),
            label: 'Verify & join',
            icon: Icons.login,
            onTap: _working ? null : _scan,
          ),
          if (scanned != null) ...[
            const SizedBox(height: 12),
            scanned.success
                ? _Banner(
                    key: const ValueKey('invite-scan-joined'),
                    text: 'Joined ${scanned.groupName}',
                    ok: true,
                  )
                : _Banner(
                    key: const ValueKey('invite-scan-error'),
                    text: scanned.error ?? 'The grant could not be verified.',
                    ok: false,
                  ),
          ],
        ],
      ),
    );
  }

  // MARK: - Formatting

  /// The grant's expiry as a UTC stamp — an absolute instant, never a relative
  /// claim this device's clock would have to be right about.
  static String _utcStamp(int unixSeconds) {
    if (unixSeconds <= 0) return '—';
    final t =
        DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)} UTC';
  }

  static String _short(String value) =>
      value.length <= 16 ? value : '${value.substring(0, 16)}…';
}

// MARK: - Shared pieces

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final String blurb;
  final Widget child;

  const _Card({
    required this.title,
    required this.icon,
    required this.blurb,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: MonokaiTheme.cyan),
              const SizedBox(width: 6),
              Text(title,
                  style: MonokaiTheme.titleSmall
                      .copyWith(color: MonokaiTheme.foreground)),
            ],
          ),
          const SizedBox(height: 6),
          Text(blurb,
              style: MonokaiTheme.bodySmall
                  .copyWith(color: MonokaiTheme.textSecondary)),
          const SizedBox(height: 12),
          child,
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

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _PillButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: enabled ? MonokaiTheme.cyan : MonokaiTheme.surfaceLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color:
                    enabled ? MonokaiTheme.background : MonokaiTheme.comment),
            const SizedBox(width: 6),
            Text(
              label,
              style: MonokaiTheme.labelMedium.copyWith(
                color:
                    enabled ? MonokaiTheme.background : MonokaiTheme.comment,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;
  const _KeyValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label,
              style: MonokaiTheme.labelSmall
                  .copyWith(color: MonokaiTheme.comment)),
          const Spacer(),
          Text(value,
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.foreground)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final bool ok;

  const _Banner({super.key, required this.text, required this.ok});

  @override
  Widget build(BuildContext context) {
    final tint = ok ? MonokaiTheme.green : MonokaiTheme.orange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 14, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: MonokaiTheme.bodySmall
                    .copyWith(color: MonokaiTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}
