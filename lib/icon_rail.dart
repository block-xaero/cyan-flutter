// widgets/icon_rail.dart
// RustRover-style vertical icon rail
// - Explorer: File tree (groups → workspaces → boards shown inline)
// - DMs: Direct messages panel (click peer in chat → opens DM)
// - Events: Network events
// NOTE: Boards are NOT a separate nav mode. They display in content area based on selection.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';

/// Navigation modes
/// Boards removed - shown in content area based on group/workspace selection
/// Chat removed - contextual per group/workspace/board, triggered from tree context menu
enum AppNavMode {
  explorer('Explorer', Icons.folder_outlined, '⌘1'),
  dms('DMs', Icons.mark_chat_unread_outlined, '⌘2'),
  events('Events', Icons.hub_outlined, '⌘3');

  final String label;
  final IconData icon;
  final String shortcut;
  const AppNavMode(this.label, this.icon, this.shortcut);
}

// ═══════════════════════════════════════════════════════════════════════════
// DM STATE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════

/// Direct Message Conversation
class DMConversation {
  final String peerId;
  final String peerName;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;
  
  const DMConversation({
    required this.peerId,
    required this.peerName,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
  });
  
  String get shortPeerId {
    if (peerId.length > 12) {
      return '${peerId.substring(0, 6)}...${peerId.substring(peerId.length - 4)}';
    }
    return peerId;
  }
  
  DMConversation copyWith({
    String? peerName,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isOnline,
  }) {
    return DMConversation(
      peerId: peerId,
      peerName: peerName ?? this.peerName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

/// DMs State
class DMsState {
  final int totalUnreadCount;
  final String? selectedPeerId;
  final List<DMConversation> conversations;
  
  const DMsState({
    this.totalUnreadCount = 0,
    this.selectedPeerId,
    this.conversations = const [],
  });
  
  DMsState copyWith({
    int? totalUnreadCount,
    String? selectedPeerId,
    List<DMConversation>? conversations,
    bool clearSelectedPeer = false,
  }) {
    return DMsState(
      totalUnreadCount: totalUnreadCount ?? this.totalUnreadCount,
      selectedPeerId: clearSelectedPeer ? null : (selectedPeerId ?? this.selectedPeerId),
      conversations: conversations ?? this.conversations,
    );
  }
}

/// DMs Notifier
class DMsNotifier extends StateNotifier<DMsState> {
  DMsNotifier() : super(const DMsState());
  
  /// Select a peer to chat with (opens DM view)
  void selectPeer(String peerId) {
    // Mark as read when selecting
    final updatedConvos = state.conversations.map((c) {
      if (c.peerId == peerId) {
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();
    
    state = state.copyWith(
      selectedPeerId: peerId,
      conversations: updatedConvos,
      totalUnreadCount: _calculateTotalUnread(updatedConvos),
    );
  }
  
  /// Clear selected peer (go back to DM list)
  void clearSelectedPeer() {
    state = state.copyWith(clearSelectedPeer: true);
  }
  
  /// Start a new conversation with a peer (from chat peer panel click)
  void startConversation(String peerId, String peerName, {bool isOnline = true}) {
    final existing = state.conversations.indexWhere((c) => c.peerId == peerId);
    if (existing >= 0) {
      // Already exists, just select it
      selectPeer(peerId);
      return;
    }
    
    // Add new conversation
    final newConvo = DMConversation(
      peerId: peerId,
      peerName: peerName,
      isOnline: isOnline,
    );
    final updated = [newConvo, ...state.conversations];
    state = state.copyWith(
      conversations: updated,
      selectedPeerId: peerId,
    );
  }
  
  /// Update conversation with new message
  void updateConversation({
    required String peerId,
    required String message,
    required bool isIncoming,
    String? peerName,
  }) {
    final existing = state.conversations.indexWhere((c) => c.peerId == peerId);
    List<DMConversation> updated;
    
    if (existing >= 0) {
      final conv = state.conversations[existing];
      final newUnread = isIncoming && state.selectedPeerId != peerId
          ? conv.unreadCount + 1
          : conv.unreadCount;
      
      updated = [...state.conversations];
      updated[existing] = conv.copyWith(
        lastMessage: message,
        lastMessageTime: DateTime.now(),
        unreadCount: newUnread,
        peerName: peerName,
      );
    } else {
      // Create new conversation
      updated = [
        DMConversation(
          peerId: peerId,
          peerName: peerName ?? peerId,
          lastMessage: message,
          lastMessageTime: DateTime.now(),
          unreadCount: isIncoming ? 1 : 0,
        ),
        ...state.conversations,
      ];
    }
    
    // Sort by last message time (newest first)
    updated.sort((a, b) {
      final aTime = a.lastMessageTime ?? DateTime(1970);
      final bTime = b.lastMessageTime ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    
    state = state.copyWith(
      conversations: updated,
      totalUnreadCount: _calculateTotalUnread(updated),
    );
  }
  
  /// Update peer online status
  void updatePeerOnlineStatus(String peerId, bool isOnline) {
    final updated = state.conversations.map((c) {
      if (c.peerId == peerId) {
        return c.copyWith(isOnline: isOnline);
      }
      return c;
    }).toList();
    state = state.copyWith(conversations: updated);
  }
  
  int _calculateTotalUnread(List<DMConversation> convos) {
    return convos.fold(0, (sum, c) => sum + c.unreadCount);
  }
}

/// DMs Provider
final dmsProvider = StateNotifierProvider<DMsNotifier, DMsState>((ref) {
  return DMsNotifier();
});

// ═══════════════════════════════════════════════════════════════════════════
// ICON RAIL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class IconRail extends ConsumerStatefulWidget {
  const IconRail({super.key});

  @override
  ConsumerState<IconRail> createState() => _IconRailState();
}

class _IconRailState extends ConsumerState<IconRail> {
  bool _showConsole = false;
  
  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(navigationModeProvider);
    final dmsState = ref.watch(dmsProvider);
    
    return Container(
      width: 56,
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          const SizedBox(height: 8),
          
          // Explorer
          _IconRailButton(
            icon: AppNavMode.explorer.icon,
            label: AppNavMode.explorer.label,
            isSelected: currentMode == AppNavMode.explorer,
            shortcut: AppNavMode.explorer.shortcut,
            showLabel: true,
            onTap: () => ref.read(navigationModeProvider.notifier).setMode(AppNavMode.explorer),
          ),
          
          // DMs with badge
          _IconRailButton(
            icon: AppNavMode.dms.icon,
            label: AppNavMode.dms.label,
            isSelected: currentMode == AppNavMode.dms,
            shortcut: AppNavMode.dms.shortcut,
            showLabel: true,
            badge: dmsState.totalUnreadCount > 0 ? dmsState.totalUnreadCount : null,
            accentColor: const Color(0xFFF92672),
            onTap: () => ref.read(navigationModeProvider.notifier).setMode(AppNavMode.dms),
          ),
          
          // Events
          _IconRailButton(
            icon: AppNavMode.events.icon,
            label: AppNavMode.events.label,
            isSelected: currentMode == AppNavMode.events,
            shortcut: AppNavMode.events.shortcut,
            showLabel: true,
            accentColor: const Color(0xFFAE81FF),
            onTap: () => ref.read(navigationModeProvider.notifier).setMode(AppNavMode.events),
          ),
          
          // Divider
          _buildDivider(),
          
          // Console toggle
          _IconRailButton(
            icon: Icons.terminal,
            label: 'Console',
            isSelected: _showConsole,
            shortcut: '⌘4',
            accentColor: const Color(0xFF66D9EF),
            showLabel: true,
            onTap: () => setState(() => _showConsole = !_showConsole),
          ),
          
          // Spacer takes remaining space
          const Spacer(),
          
          // Bottom section
          _buildDivider(),
          
          _IconRailButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isSelected: false,
            shortcut: '⌘,',
            showLabel: false,
            onTap: () {
              // Show settings
            },
          ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }
  
  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: const Color(0xFF2A2A2A),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ICON RAIL BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _IconRailButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final String shortcut;
  final Color accentColor;
  final bool showLabel;
  final int? badge;
  final VoidCallback onTap;

  const _IconRailButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.shortcut = '',
    this.accentColor = const Color(0xFFA6E22E),
    this.showLabel = true,
    this.badge,
    required this.onTap,
  });

  @override
  State<_IconRailButton> createState() => _IconRailButtonState();
}

class _IconRailButtonState extends State<_IconRailButton> {
  bool _isHovered = false;

  Color get _iconColor {
    if (widget.isSelected) return widget.accentColor;
    if (_isHovered) return const Color(0xFFCCCCCC);
    return const Color(0xFF808080);
  }

  Color get _labelColor {
    if (widget.isSelected) return widget.accentColor;
    return const Color(0xFF808080);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${widget.label} (${widget.shortcut})',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 26,
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? widget.accentColor.withValues(alpha: 0.15)
                            : (_isHovered ? const Color(0xFF2A2A2A) : Colors.transparent),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 16,
                        color: _iconColor,
                      ),
                    ),
                    // Badge
                    if (widget.badge != null)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF92672),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          constraints: const BoxConstraints(minWidth: 14),
                          child: Text(
                            widget.badge! > 99 ? '99+' : widget.badge.toString(),
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 1),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                      color: _labelColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
