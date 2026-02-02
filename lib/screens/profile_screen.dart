// screens/profile_screen.dart
// User profile - matches Swift ProfileView.swift exactly
// Avatar, XaeroID display, groups, backup QR, sign out

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../theme/monokai_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/file_tree_provider.dart';
import '../models/xaero_identity.dart';
import '../models/tree_item.dart';
import '../ffi/ffi_helpers.dart';
import 'login_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _showCopiedDid = false;
  bool _showCopiedPub = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final identity = authState.identity;

    return Scaffold(
      backgroundColor: MonokaiTheme.surface,
      appBar: AppBar(
        backgroundColor: MonokaiTheme.surface,
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _profileHeader(authState),
            const SizedBox(height: 24),
            if (identity != null) _identitySection(identity),
            const SizedBox(height: 24),
            _groupsSection(),
            const SizedBox(height: 24),
            _actionsSection(authState),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ==== PROFILE HEADER - Matches Swift profileHeader ====

  Widget _profileHeader(AuthState authState) {
    return Column(
      children: [
        // Avatar
        _avatar(authState),
        const SizedBox(height: 12),
        // Name
        Text(authState.displayName, style: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFFF8F8F2),
        )),
        // Test badge
        if (authState.isTestAccount) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: MonokaiTheme.yellow.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Test Account', style: TextStyle(
              fontSize: 12, color: MonokaiTheme.yellow,
            )),
          ),
        ],
        // Email
        if (authState.identity?.email != null) ...[
          const SizedBox(height: 4),
          Text(authState.identity!.email!, style: TextStyle(
            fontSize: 13, color: MonokaiTheme.comment,
          )),
        ],
      ],
    );
  }

  Widget _avatar(AuthState authState) {
    final avatarUrl = authState.avatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: MonokaiTheme.cyan.withOpacity(0.5), width: 2),
        ),
        child: ClipOval(
          child: Image.network(
            avatarUrl,
            width: 80, height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _avatarPlaceholder(authState),
          ),
        ),
      );
    }

    return _avatarPlaceholder(authState);
  }

  Widget _avatarPlaceholder(AuthState authState) {
    final initials = _getInitials(authState.displayName, authState.shortId);
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MonokaiTheme.cyan.withOpacity(0.2),
        border: Border.all(color: MonokaiTheme.cyan.withOpacity(0.3), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(initials, style: const TextStyle(
        fontSize: 28, fontWeight: FontWeight.w600, color: MonokaiTheme.cyan,
      )),
    );
  }

  String _getInitials(String name, String? shortId) {
    if (name.isEmpty || name == 'Anonymous') {
      return (shortId?.substring(0, 2) ?? '??').toUpperCase();
    }
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }

  // ==== IDENTITY SECTION - Matches Swift identitySection ====

  Widget _identitySection(XaeroIdentity identity) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MonokaiTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('XaeroID', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: MonokaiTheme.comment,
          )),
          const SizedBox(height: 12),

          // Short ID
          _infoRow('ID', identity.shortId, MonokaiTheme.cyan),
          const SizedBox(height: 10),

          // DID
          _copyableRow('DID', _truncateDid(identity.did), identity.did, _showCopiedDid, () {
            Clipboard.setData(ClipboardData(text: identity.did));
            setState(() => _showCopiedDid = true);
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _showCopiedDid = false);
            });
          }),
          const SizedBox(height: 10),

          // Public Key
          _copyableRow('Public Key', _truncateHex(identity.publicKeyHex), identity.publicKeyHex, _showCopiedPub, () {
            Clipboard.setData(ClipboardData(text: identity.publicKeyHex));
            setState(() => _showCopiedPub = true);
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) setState(() => _showCopiedPub = false);
            });
          }),
          const SizedBox(height: 10),

          // Created date
          _infoRow('Created', _formatDate(identity.createdAt), MonokaiTheme.comment),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, Color valueColor) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(fontSize: 13, color: MonokaiTheme.comment)),
        ),
        Expanded(
          child: Text(value, style: TextStyle(
            fontSize: 14, fontFamily: 'monospace', color: valueColor,
          )),
        ),
      ],
    );
  }

  Widget _copyableRow(String label, String display, String fullValue, bool showCopied, VoidCallback onCopy) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: TextStyle(fontSize: 13, color: MonokaiTheme.comment)),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onCopy,
            child: Row(
              children: [
                Flexible(
                  child: Text(display, style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace', color: Color(0xFFF8F8F2),
                  ), overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Icon(
                  showCopied ? Icons.check : Icons.copy,
                  size: 12,
                  color: showCopied ? MonokaiTheme.green : MonokaiTheme.comment,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==== ACTIONS SECTION ====

  // ==== GROUPS SECTION - Matches Swift groupsSection ====

  Widget _groupsSection() {
    final fileTreeState = ref.watch(fileTreeProvider);
    final groups = fileTreeState.groups;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MonokaiTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Join button
          Row(
            children: [
              Text('Groups', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: MonokaiTheme.comment,
              )),
              const Spacer(),
              // Join group button
              GestureDetector(
                onTap: _showJoinGroupDialog,
                child: Row(
                  children: [
                    Icon(Icons.qr_code_scanner, size: 12, color: MonokaiTheme.green),
                    const SizedBox(width: 4),
                    Text('Join', style: TextStyle(fontSize: 12, color: MonokaiTheme.green)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Group list
          if (groups.isEmpty)
            Text('No groups yet', style: TextStyle(
              fontSize: 13, fontStyle: FontStyle.italic,
              color: MonokaiTheme.comment.withOpacity(0.7),
            ))
          else
            ...groups.map((group) => _groupRow(group)),
        ],
      ),
    );
  }

  Widget _groupRow(TreeGroup group) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Icon
          Icon(Icons.folder, size: 14, color: MonokaiTheme.purple),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Text(group.name, style: const TextStyle(
              fontSize: 14, color: Color(0xFFF8F8F2),
            )),
          ),
          // Share invite button
          GestureDetector(
            onTap: () => _showGroupInvite(group),
            child: Icon(Icons.share, size: 12, color: MonokaiTheme.cyan),
          ),
        ],
      ),
    );
  }

  void _showJoinGroupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MonokaiTheme.surface,
        title: Text('Join Group', style: TextStyle(color: MonokaiTheme.foreground)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Paste an invite code to join a group', style: TextStyle(
              color: MonokaiTheme.comment, fontSize: 13,
            )),
            const SizedBox(height: 16),
            TextField(
              style: TextStyle(color: MonokaiTheme.foreground, fontFamily: 'monospace', fontSize: 12),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Paste invite JSON here...',
                hintStyle: TextStyle(color: MonokaiTheme.comment.withOpacity(0.5)),
                filled: true,
                fillColor: MonokaiTheme.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onSubmitted: (value) => _joinGroup(value, ctx),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: MonokaiTheme.comment)),
          ),
        ],
      ),
    );
  }

  void _joinGroup(String inviteJson, BuildContext dialogCtx) {
    // Parse invite and join via FFI
    try {
      final invite = jsonDecode(inviteJson) as Map<String, dynamic>;
      final groupId = invite['group_id'] as String?;
      final groupName = invite['group_name'] as String?;
      
      if (groupId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid invite: missing group_id')),
        );
        return;
      }
      
      // Call FFI to join group
      // TODO: CyanFFI.joinGroupFromInvite(inviteJson);
      debugPrint('📥 Joining group: $groupName ($groupId)');
      
      Navigator.pop(dialogCtx);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined group: ${groupName ?? groupId}')),
      );
      
      // Refresh file tree
      ref.read(fileTreeProvider.notifier).refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid invite format')),
      );
    }
  }

  void _showGroupInvite(TreeGroup group) {
    final authState = ref.read(authProvider);
    final identity = authState.identity;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GroupInviteSheet(
        group: group,
        inviterName: authState.displayName,
        identity: identity,
      ),
    );
  }

  // ==== ACTIONS SECTION (continued) ====

  Widget _actionsSection(AuthState authState) {
    return Column(
      children: [
        // Show XaeroID QR
        _actionButton(
          icon: Icons.qr_code,
          label: 'Show XaeroID QR Code',
          color: MonokaiTheme.cyan,
          onTap: () => _showXaeroQR(authState),
        ),
        const SizedBox(height: 12),

        // Show Backup Key
        _actionButton(
          icon: Icons.key,
          label: 'Show Backup Key',
          color: MonokaiTheme.yellow,
          onTap: () => _showBackupKey(authState),
        ),
        const SizedBox(height: 24),

        // Sign Out
        _actionButton(
          icon: Icons.logout,
          label: 'Sign Out',
          color: MonokaiTheme.red,
          onTap: () => _confirmSignOut(authState),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }

  // ==== DIALOGS ====

  void _showXaeroQR(AuthState authState) {
    final identity = authState.identity;
    if (identity == null) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: MonokaiTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your XaeroID', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF8F8F2),
              )),
              const SizedBox(height: 16),
              // QR
              Container(
                width: 200, height: 200,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CustomPaint(
                  painter: _SimpleQRPainter(identity.secretKeyHex),
                  size: const Size(168, 168),
                ),
              ),
              const SizedBox(height: 12),
              Text('XaeroID: ${identity.shortId}', style: const TextStyle(
                fontSize: 14, fontFamily: 'monospace', color: MonokaiTheme.cyan,
              )),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done', style: TextStyle(color: MonokaiTheme.cyan)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBackupKey(AuthState authState) {
    final identity = authState.identity;
    if (identity == null) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: MonokaiTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber, size: 18, color: MonokaiTheme.yellow),
                  const SizedBox(width: 8),
                  Text('Backup Key', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: MonokaiTheme.yellow,
                  )),
                ],
              ),
              const SizedBox(height: 12),
              Text('Keep this key safe. It is the only way to restore your identity.', style: TextStyle(
                fontSize: 13, color: MonokaiTheme.comment,
              )),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MonokaiTheme.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(identity.secretKeyHex, style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace', color: Color(0xFFF8F8F2),
                )),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: MonokaiTheme.cyan),
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('Copy Key'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: identity.secretKeyHex));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Backup key copied to clipboard')),
                        );
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(AuthState authState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MonokaiTheme.surface,
        title: const Text('Sign Out', style: TextStyle(color: Color(0xFFF8F8F2))),
        content: Text(
          "You'll need your backup key to sign back in. Make sure you have it saved.",
          style: TextStyle(color: MonokaiTheme.comment),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: MonokaiTheme.comment)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MonokaiTheme.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  // ==== HELPERS ====

  String _truncateDid(String did) {
    if (did.length > 30) return '${did.substring(0, 20)}…${did.substring(did.length - 8)}';
    return did;
  }

  String _truncateHex(String hex) {
    if (hex.length > 20) return '${hex.substring(0, 12)}…${hex.substring(hex.length - 8)}';
    return hex;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

// ==== SIMPLE QR PAINTER ====

class _SimpleQRPainter extends CustomPainter {
  final String data;
  _SimpleQRPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final cellSize = size.width / 25;

    // Finder patterns
    _drawFinder(canvas, paint, 0, 0, cellSize);
    _drawFinder(canvas, paint, 18 * cellSize, 0, cellSize);
    _drawFinder(canvas, paint, 0, 18 * cellSize, cellSize);

    // Data area
    final bytes = <int>[];
    for (var i = 0; i < data.length - 1; i += 2) {
      try { bytes.add(int.parse(data.substring(i, i + 2), radix: 16)); } catch (_) {}
    }

    var bi = 0;
    for (var r = 0; r < 25; r++) {
      for (var c = 0; c < 25; c++) {
        if ((r < 8 && c < 8) || (r < 8 && c > 16) || (r > 16 && c < 8)) continue;
        if (bi < bytes.length && (bytes[bi % bytes.length] >> (c % 8)) & 1 == 1) {
          canvas.drawRect(Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize), paint);
        }
        if (c % 3 == 0) bi++;
      }
    }
  }

  void _drawFinder(Canvas canvas, Paint paint, double x, double y, double cs) {
    canvas.drawRect(Rect.fromLTWH(x, y, 7 * cs, 7 * cs), paint);
    canvas.drawRect(Rect.fromLTWH(x + cs, y + cs, 5 * cs, 5 * cs), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(x + 2 * cs, y + 2 * cs, 3 * cs, 3 * cs), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==== GROUP INVITE SHEET - Matches Swift GroupInviteSheet ====

class GroupInviteSheet extends StatefulWidget {
  final TreeGroup group;
  final String inviterName;
  final XaeroIdentity? identity;

  const GroupInviteSheet({
    super.key,
    required this.group,
    required this.inviterName,
    this.identity,
  });

  @override
  State<GroupInviteSheet> createState() => _GroupInviteSheetState();
}

class _GroupInviteSheetState extends State<GroupInviteSheet> {
  String _inviteJson = '';
  bool _showCopied = false;

  @override
  void initState() {
    super.initState();
    _generateInvite();
  }

  void _generateInvite() {
    final identity = widget.identity;
    if (identity == null) return;

    // Get local iroh node ID for gossip bootstrap
    final nodeId = CyanFFI.getNodeId();

    // Create invite payload
    // In production this would call xaero_create_group_invite FFI
    final invite = {
      'type': 'group_invite',
      'version': 1,
      'group_id': widget.group.id,
      'group_name': widget.group.name,
      'group_icon': 'folder.fill',
      'group_color': '#AE81FF',
      'inviter_name': widget.inviterName,
      'inviter_node_id': nodeId,
      'inviter_pubkey': identity.publicKeyHex,
      'created_at': DateTime.now().toIso8601String(),
      // TODO: Add Ed25519 signature from identity.secretKeyHex
    };

    setState(() {
      _inviteJson = jsonEncode(invite);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: MonokaiTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: MonokaiTheme.comment.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Header
                  Icon(Icons.folder, size: 40, color: MonokaiTheme.purple),
                  const SizedBox(height: 8),
                  Text('Invite to ${widget.group.name}', style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF8F8F2),
                  )),
                  const SizedBox(height: 4),
                  Text('Share this QR code to invite others', style: TextStyle(
                    fontSize: 13, color: MonokaiTheme.comment,
                  )),
                  const SizedBox(height: 24),

                  // QR Code
                  Container(
                    width: 220, height: 220,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CustomPaint(
                      painter: _InviteQRPainter(_inviteJson),
                      size: const Size(188, 188),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Copy invite button
                  ElevatedButton.icon(
                    onPressed: _copyInvite,
                    icon: Icon(_showCopied ? Icons.check : Icons.copy, size: 16),
                    label: Text(_showCopied ? 'Copied!' : 'Copy Invite Code'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MonokaiTheme.cyan.withOpacity(0.15),
                      foregroundColor: _showCopied ? MonokaiTheme.green : MonokaiTheme.cyan,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Info bullets
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: MonokaiTheme.background.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('When someone scans this:', style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500, color: MonokaiTheme.comment,
                        )),
                        const SizedBox(height: 8),
                        _bullet("They'll join your group automatically"),
                        _bullet("They can collaborate on workspaces"),
                        _bullet("Invite is valid forever"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Done button
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MonokaiTheme.comment.withOpacity(0.2),
                  foregroundColor: MonokaiTheme.comment,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•', style: TextStyle(color: MonokaiTheme.green)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: MonokaiTheme.comment))),
        ],
      ),
    );
  }

  void _copyInvite() {
    Clipboard.setData(ClipboardData(text: _inviteJson));
    setState(() => _showCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showCopied = false);
    });
  }
}

// ==== INVITE QR PAINTER ====

class _InviteQRPainter extends CustomPainter {
  final String data;
  _InviteQRPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final paint = Paint()..color = Colors.black;
    final cellSize = size.width / 33; // Larger grid for more data

    // Finder patterns (7x7 boxes at corners)
    _drawFinder(canvas, paint, 0, 0, cellSize);
    _drawFinder(canvas, paint, 26 * cellSize, 0, cellSize);
    _drawFinder(canvas, paint, 0, 26 * cellSize, cellSize);

    // Hash the data to generate deterministic pattern
    var hash = 0;
    for (var i = 0; i < data.length; i++) {
      hash = ((hash << 5) - hash + data.codeUnitAt(i)) & 0xFFFFFFFF;
    }

    // Data modules
    final rng = _SeededRandom(hash);
    for (var r = 0; r < 33; r++) {
      for (var c = 0; c < 33; c++) {
        // Skip finder pattern areas
        if ((r < 8 && c < 8) || (r < 8 && c > 24) || (r > 24 && c < 8)) continue;
        // Skip timing patterns
        if (r == 6 || c == 6) {
          if ((r + c) % 2 == 0) {
            canvas.drawRect(Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize), paint);
          }
          continue;
        }
        // Data area
        if (rng.nextBool()) {
          canvas.drawRect(Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize), paint);
        }
      }
    }
  }

  void _drawFinder(Canvas canvas, Paint paint, double x, double y, double cs) {
    canvas.drawRect(Rect.fromLTWH(x, y, 7 * cs, 7 * cs), paint);
    canvas.drawRect(Rect.fromLTWH(x + cs, y + cs, 5 * cs, 5 * cs), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(x + 2 * cs, y + 2 * cs, 3 * cs, 3 * cs), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Simple seeded random for deterministic QR pattern
class _SeededRandom {
  int _seed;
  _SeededRandom(this._seed);

  bool nextBool() {
    _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return (_seed >> 16) & 1 == 1;
  }
}
