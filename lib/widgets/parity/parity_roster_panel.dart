// widgets/parity/parity_roster_panel.dart
//
// PARITY port of the SwiftUI `RosterPanel` (RosterMembersList / RosterMemberRow)
// driven by `RosterViewModel` — the Peers panel.
//
// Each row: an avatar monogram with an online(green)/offline(grey) dot, the
// member's name, a presence/last-seen line, and the craft role the mesh has
// stamped on them. OFFLINE members stay listed with their cached names — the
// engine's roster is persistent, so the panel never drops someone who left. A
// group with no other members reads "just you", never blank.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `groupRosterProvider`).
//
// SwiftUI reference (read-only): cyan-iOS/Cyan/Cyan/Views/RosterPanel.swift

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_identity_provider.dart';
import '../../theme/monokai_theme.dart';

class ParityRosterPanel extends ConsumerWidget {
  /// The group whose persistent roster is listed.
  final String groupId;

  /// The board that is open, if any — its notes carry the craft-role
  /// provenance the rows render. Empty reads the group scope only.
  final String boardId;

  const ParityRosterPanel({
    super.key,
    required this.groupId,
    this.boardId = '',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterAsync =
        ref.watch(groupRosterProvider(RosterScope(groupId, boardId: boardId)));

    return Material(
      color: MonokaiTheme.background,
      child: rosterAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MonokaiTheme.cyan),
        ),
        error: (e, _) => Center(
          child: Text('Failed to load the roster: $e',
              style:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.red)),
        ),
        data: (entries) {
          final others = entries.where((e) => !e.isMe).toList();
          final online = entries.where((e) => e.member.online).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(online: online, total: entries.length),
              const Divider(height: 1, color: MonokaiTheme.divider),
              Expanded(
                child: others.isEmpty
                    ? const _JustYou()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: entries.length,
                        itemBuilder: (context, i) =>
                            _MemberRow(entry: entries[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int online;
  final int total;
  const _Header({required this.online, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          const Icon(Icons.people_outline, size: 13, color: MonokaiTheme.cyan),
          const SizedBox(width: 8),
          Text('Peers',
              style: MonokaiTheme.labelMedium
                  .copyWith(color: MonokaiTheme.foreground)),
          const Spacer(),
          Text('$online of $total online',
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.comment)),
        ],
      ),
    );
  }
}

/// The empty-group copy — the group has no other members yet.
class _JustYou extends StatelessWidget {
  const _JustYou();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.person, size: 11, color: MonokaiTheme.comment),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Just you — invite someone to collaborate.',
                  style: MonokaiTheme.codeSmall
                      .copyWith(color: MonokaiTheme.comment)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final RosterEntry entry;
  const _MemberRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final online = entry.member.online;
    return Opacity(
      opacity: online ? 1.0 : 0.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            _Avatar(monogram: entry.monogram, online: online),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: MonokaiTheme.codeSmall.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: online
                                ? MonokaiTheme.foreground
                                : MonokaiTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (entry.isMe) ...[
                        const SizedBox(width: 6),
                        Text('you',
                            style: MonokaiTheme.labelSmall
                                .copyWith(color: MonokaiTheme.comment)),
                      ],
                    ],
                  ),
                  Text(entry.presenceLabel,
                      style: MonokaiTheme.codeSmall.copyWith(
                          fontSize: 9, color: MonokaiTheme.comment)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RoleChip(role: entry.craftRole),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String monogram;
  final bool online;
  const _Avatar({required this.monogram, required this.online});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: MonokaiTheme.selection,
              shape: BoxShape.circle,
            ),
            child: Text(
              monogram,
              style: MonokaiTheme.codeSmall.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: online ? MonokaiTheme.foreground : MonokaiTheme.comment,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: online
                    ? MonokaiTheme.green
                    : MonokaiTheme.comment.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(color: MonokaiTheme.surface, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The member's craft role. A role the mesh has never stamped reads
/// "unassigned" rather than being guessed at.
class _RoleChip extends StatelessWidget {
  final String? role;
  const _RoleChip({this.role});

  @override
  Widget build(BuildContext context) {
    final known = role != null && role!.isNotEmpty;
    final label = known ? role!.replaceAll('_', ' ') : 'unassigned';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: known
            ? MonokaiTheme.yellow.withValues(alpha: 0.16)
            : MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: MonokaiTheme.labelSmall.copyWith(
          color: known ? MonokaiTheme.yellow : MonokaiTheme.comment,
        ),
      ),
    );
  }
}
