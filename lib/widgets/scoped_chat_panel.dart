// widgets/scoped_chat_panel.dart
// Comprehensive chat panel with:
// - Scoped chat (group/workspace/board)
// - Markdown rendering for messages
// - Peers panel with DM support
// - Files panel with drag & drop
// - File tree integration

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../providers/file_tree_provider.dart';
import '../providers/selection_provider.dart';
import '../ffi/ffi_helpers.dart';
import '../ffi/component_bridge.dart';
import '../theme/monokai_theme.dart';

// ============================================================================
// MOCK PEERS (for demo)
// ============================================================================

class MockPeer {
  final String id;
  final String name;
  final String? avatar;
  final bool isOnline;
  final DateTime? lastSeen;
  
  const MockPeer({
    required this.id,
    required this.name,
    this.avatar,
    this.isOnline = true,
    this.lastSeen,
  });
}

final _mockPeers = [
  MockPeer(id: 'alice123', name: 'Alice', isOnline: true),
  MockPeer(id: 'bob456', name: 'Bob', isOnline: true),
  MockPeer(id: 'carol789', name: 'Carol', isOnline: false, lastSeen: DateTime.now().subtract(const Duration(hours: 2))),
  MockPeer(id: 'dave012', name: 'Dave', isOnline: true),
  MockPeer(id: 'eve345', name: 'Eve', isOnline: false, lastSeen: DateTime.now().subtract(const Duration(days: 1))),
];

// ============================================================================
// MOCK FILES (for demo)
// ============================================================================

class ScopedFile {
  final String id;
  final String name;
  final int size;
  final DateTime uploadedAt;
  final String? uploadedBy;
  
  const ScopedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.uploadedAt,
    this.uploadedBy,
  });
  
  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  
  IconData get icon {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'png': case 'jpg': case 'jpeg': case 'gif': return Icons.image;
      case 'mp4': case 'mov': case 'avi': return Icons.videocam;
      case 'mp3': case 'wav': return Icons.audiotrack;
      case 'zip': case 'rar': case 'tar': return Icons.folder_zip;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      default: return Icons.insert_drive_file;
    }
  }
}

// ============================================================================
// SCOPED CHAT PANEL
// ============================================================================

class ScopedChatPanel extends ConsumerStatefulWidget {
  final ChatContextInfo context;
  
  const ScopedChatPanel({super.key, required this.context});
  
  @override
  ConsumerState<ScopedChatPanel> createState() => _ScopedChatPanelState();
}

class _ScopedChatPanelState extends ConsumerState<ScopedChatPanel> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  
  bool _showPeersPanel = true;
  bool _showFilesPanel = true;
  bool _isSidebarCollapsed = false;
  double _sidebarWidth = 160;
  
  List<ChatMessage> _messages = [];
  List<ScopedFile> _files = [];
  bool _isLoading = true;
  
  late ChatBridge _chatBridge;
  StreamSubscription? _chatSubscription;
  
  @override
  void initState() {
    super.initState();
    _initChat();
    _loadMockFiles();
  }
  
  @override
  void didUpdateWidget(ScopedChatPanel old) {
    super.didUpdateWidget(old);
    if (old.context != widget.context) {
      _disposeChat();
      _initChat();
      _loadMockFiles();
    }
  }
  
  @override
  void dispose() {
    _disposeChat();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  
  void _initChat() {
    _chatBridge = ChatBridge();
    _chatBridge.start();
    _messages = []; // Reset messages
    _allowedWorkspaceIds = _getWorkspaceIdsForScope();
    
    _chatSubscription = _chatBridge.events.listen((event) {
      if (!mounted) return;
      
      // Handle both ChatSent (individual messages) and ChatHistory (bulk)
      if (event.isMessage || event.isMessageReceived) {
        // ChatSent - individual message from history or new message
        final msg = event.singleMessage;
        if (msg != null && _shouldIncludeMessage(msg)) {
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
            _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          }
          if (mounted) {
            setState(() => _isLoading = false);
            _scrollToBottom();
          }
        }
      } else if (event.isHistoryLoaded || event.isHistory) {
        // Bulk history (if Rust ever sends this format)
        final newMessages = event.messages;
        for (final msg in newMessages) {
          if (_shouldIncludeMessage(msg) && !_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
          }
        }
        _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (mounted) {
          setState(() => _isLoading = false);
          _scrollToBottom();
        }
      }
    });
    
    // Load history based on scope
    _loadChatHistory();
    
    // Stop loading after 1 second (simple timeout, no timer state)
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    });
  }
  
  // Get allowed workspace IDs for current scope
  Set<String> _getWorkspaceIdsForScope() {
    switch (widget.context.scope) {
      case 'workspace':
        return {widget.context.rawId};
      case 'board':
        final wsId = widget.context.workspaceId;
        return wsId != null && wsId.isNotEmpty ? {wsId} : {};
      case 'group':
        // Get all workspace IDs in the group
        final fileTreeState = ref.read(fileTreeProvider);
        final group = fileTreeState.groups.where((g) => g.id == widget.context.rawId).firstOrNull;
        if (group != null) {
          return group.workspaces.map((w) => w.id).toSet();
        }
        return {};
      default:
        return {}; // Empty = allow all (global)
    }
  }
  
  // Filter message by workspace ID
  bool _shouldIncludeMessage(ChatMessage msg) {
    // If no filter set (global), include all
    if (_allowedWorkspaceIds.isEmpty) return true;
    // Check if message workspace is in allowed set
    return _allowedWorkspaceIds.contains(msg.workspaceId);
  }
  
  Set<String> _allowedWorkspaceIds = {};
  
  void _loadChatHistory() {
    switch (widget.context.scope) {
      case 'group':
        // Load chat for all workspaces in the group
        _loadGroupChatHistory();
        break;
      case 'workspace':
        // Load chat for this workspace
        _chatBridge.send(ChatCommand.loadHistory(workspaceId: widget.context.rawId));
        break;
      case 'board':
        // Boards use their parent workspace
        final wsId = widget.context.workspaceId;
        if (wsId != null && wsId.isNotEmpty) {
          _chatBridge.send(ChatCommand.loadHistory(workspaceId: wsId));
        } else {
          setState(() => _isLoading = false);
        }
        break;
      default:
        setState(() => _isLoading = false);
    }
  }
  
  void _loadGroupChatHistory() async {
    // Get workspace IDs for this group from file tree
    final fileTreeState = ref.read(fileTreeProvider);
    final group = fileTreeState.groups.where((g) => g.id == widget.context.rawId).firstOrNull;
    
    if (group == null) {
      setState(() => _isLoading = false);
      return;
    }
    
    final workspaceIds = group.workspaces.map((w) => w.id).toList();
    
    if (workspaceIds.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    
    // Load history for each workspace
    for (final wsId in workspaceIds) {
      _chatBridge.send(ChatCommand.loadHistory(workspaceId: wsId));
      // Small delay between requests
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
  
  void _disposeChat() {
    _chatSubscription?.cancel();
    _chatBridge.dispose();
  }
  
  void _loadMockFiles() {
    // Generate mock files based on scope
    final scopeName = widget.context.name.toLowerCase();
    _files = [
      ScopedFile(id: '1', name: 'project_notes.md', size: 2048, uploadedAt: DateTime.now().subtract(const Duration(hours: 1)), uploadedBy: 'Alice'),
      ScopedFile(id: '2', name: 'design_v2.png', size: 156000, uploadedAt: DateTime.now().subtract(const Duration(hours: 3)), uploadedBy: 'Bob'),
      ScopedFile(id: '3', name: 'meeting_recording.mp4', size: 52428800, uploadedAt: DateTime.now().subtract(const Duration(days: 1)), uploadedBy: 'Carol'),
    ];
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    // Get workspace ID for sending
    String? workspaceId;
    switch (widget.context.scope) {
      case 'workspace':
        workspaceId = widget.context.rawId;
        break;
      case 'board':
        workspaceId = widget.context.workspaceId;
        break;
      case 'group':
        // For group chat, need to pick a workspace - use first one
        final fileTreeState = ref.read(fileTreeProvider);
        final group = fileTreeState.groups.where((g) => g.id == widget.context.rawId).firstOrNull;
        workspaceId = group?.workspaces.firstOrNull?.id;
        break;
    }
    
    if (workspaceId == null || workspaceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No workspace selected'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    _chatBridge.send(ChatCommand.sendMessage(
      workspaceId: workspaceId,
      message: text,
    ));
    
    _messageController.clear();
    _focusNode.requestFocus();
  }
  
  void _handleFileDrop(List<String> paths) {
    for (final path in paths) {
      // Call appropriate FFI based on scope
      switch (widget.context.scope) {
        case 'group':
          CyanFFI.uploadFileToGroup(path, widget.context.rawId);
          break;
        case 'workspace':
          CyanFFI.uploadFileToWorkspace(path, widget.context.rawId);
          break;
        case 'board':
          // Board files go to workspace level with board metadata
          final wsId = widget.context.workspaceId;
          if (wsId != null) {
            CyanFFI.uploadFileToWorkspace(path, wsId);
          }
          break;
      }
    }
    
    // Refresh file tree
    ref.read(fileTreeProvider.notifier).refresh();
    
    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Uploaded ${paths.length} file(s)'),
        backgroundColor: MonokaiTheme.green,
      ),
    );
  }
  
  void _openDM(MockPeer peer) {
    // Show a DM dialog
    showDialog(
      context: context,
      builder: (ctx) => _DMDialog(
        peer: peer,
        onSend: (message) => _sendDM(peer, message),
      ),
    );
  }
  
  void _sendDM(MockPeer peer, String message) {
    // Get a workspace ID to use for DM context
    String? workspaceId;
    if (widget.context.scope == 'workspace') {
      workspaceId = widget.context.rawId;
    } else if (widget.context.scope == 'board') {
      workspaceId = widget.context.workspaceId;
    } else {
      // For group, use first workspace
      final fileTreeState = ref.read(fileTreeProvider);
      final group = fileTreeState.groups.where((g) => g.id == widget.context.rawId).firstOrNull;
      workspaceId = group?.workspaces.firstOrNull?.id;
    }
    
    if (workspaceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No workspace context for DM')),
      );
      return;
    }
    
    // Start DM chat
    _chatBridge.send(ChatCommand.startDirectChat(
      peerId: peer.id,
      workspaceId: workspaceId,
    ));
    
    // Send the message
    _chatBridge.send(ChatCommand.sendDirectMessage(
      peerId: peer.id,
      workspaceId: workspaceId,
      message: message,
    ));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('DM sent to ${peer.name}'),
        backgroundColor: MonokaiTheme.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MonokaiTheme.background,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: Row(
              children: [
                // Sidebar (peers + files)
                if (!_isSidebarCollapsed) ...[
                  SizedBox(
                    width: _sidebarWidth,
                    child: Column(
                      children: [
                        _buildPeersSection(),
                        const Divider(height: 1, color: MonokaiTheme.divider),
                        _buildFilesSection(),
                        const Spacer(),
                      ],
                    ),
                  ),
                  _buildResizeHandle(),
                ],
                
                // Main chat area
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _buildMessageList()),
                      _buildInputArea(),
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
  
  // ============================================================================
  // HEADER
  // ============================================================================
  
  Widget _buildHeader() {
    final scopeIcon = switch (widget.context.scope) {
      'group' => Icons.folder,
      'workspace' => Icons.workspaces,
      'board' => Icons.dashboard,
      _ => Icons.chat,
    };
    
    final scopeColor = switch (widget.context.scope) {
      'group' => MonokaiTheme.cyan,
      'workspace' => MonokaiTheme.green,
      'board' => MonokaiTheme.orange,
      _ => MonokaiTheme.textSecondary,
    };
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          // Sidebar toggle
          IconButton(
            icon: Icon(
              _isSidebarCollapsed ? Icons.chevron_right : Icons.chevron_left,
              size: 18,
              color: MonokaiTheme.textSecondary,
            ),
            onPressed: () => setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
            tooltip: _isSidebarCollapsed ? 'Show sidebar' : 'Hide sidebar',
          ),
          
          const SizedBox(width: 8),
          
          // Scope icon
          Icon(scopeIcon, size: 18, color: scopeColor),
          const SizedBox(width: 8),
          
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.context.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MonokaiTheme.foreground,
                  ),
                ),
                Text(
                  '${widget.context.scope} chat',
                  style: TextStyle(
                    fontSize: 10,
                    color: scopeColor,
                  ),
                ),
              ],
            ),
          ),
          
          // Actions
          IconButton(
            icon: const Icon(Icons.attach_file, size: 18),
            color: MonokaiTheme.textSecondary,
            onPressed: () {
              // TODO: File picker
            },
            tooltip: 'Attach file',
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, size: 18),
            color: MonokaiTheme.textSecondary,
            onPressed: () {
              // TODO: More options
            },
          ),
        ],
      ),
    );
  }
  
  // ============================================================================
  // PEERS SECTION
  // ============================================================================
  
  Widget _buildPeersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        InkWell(
          onTap: () => setState(() => _showPeersPanel = !_showPeersPanel),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: MonokaiTheme.surface.withOpacity(0.3),
            child: Row(
              children: [
                Icon(Icons.people, size: 12, color: MonokaiTheme.green),
                const SizedBox(width: 6),
                Text(
                  'Peers',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: MonokaiTheme.foreground,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_mockPeers.where((p) => p.isOnline).length}',
                    style: TextStyle(fontSize: 9, color: MonokaiTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showPeersPanel ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: MonokaiTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        
        // Peers list
        if (_showPeersPanel)
          ..._mockPeers.map((peer) => _buildPeerItem(peer)),
      ],
    );
  }
  
  Widget _buildPeerItem(MockPeer peer) {
    return InkWell(
      onTap: () => _openDM(peer),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: peer.isOnline ? MonokaiTheme.green : MonokaiTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            
            // Avatar
            CircleAvatar(
              radius: 12,
              backgroundColor: _getAvatarColor(peer.name),
              child: Text(
                peer.name[0].toUpperCase(),
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            
            // Name
            Expanded(
              child: Text(
                peer.name,
                style: TextStyle(
                  fontSize: 11,
                  color: peer.isOnline ? MonokaiTheme.foreground : MonokaiTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            
            // DM icon on hover
            Icon(Icons.chat_bubble_outline, size: 12, color: MonokaiTheme.textSecondary.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
  
  Color _getAvatarColor(String name) {
    final colors = [MonokaiTheme.cyan, MonokaiTheme.green, MonokaiTheme.orange, MonokaiTheme.pink, MonokaiTheme.purple];
    return colors[name.hashCode.abs() % colors.length];
  }
  
  // ============================================================================
  // FILES SECTION
  // ============================================================================
  
  Widget _buildFilesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        InkWell(
          onTap: () => setState(() => _showFilesPanel = !_showFilesPanel),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: MonokaiTheme.surface.withOpacity(0.3),
            child: Row(
              children: [
                Icon(Icons.folder, size: 12, color: MonokaiTheme.cyan),
                const SizedBox(width: 6),
                Text(
                  'Files',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: MonokaiTheme.foreground,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_files.length}',
                    style: TextStyle(fontSize: 9, color: MonokaiTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showFilesPanel ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: MonokaiTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        
        // Files list
        if (_showFilesPanel)
          ..._files.map((file) => _buildFileItem(file)),
        
        // Drop zone hint
        if (_showFilesPanel)
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: MonokaiTheme.divider, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload, size: 20, color: MonokaiTheme.textSecondary),
                const SizedBox(height: 4),
                Text(
                  'Drop files here',
                  style: TextStyle(fontSize: 10, color: MonokaiTheme.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
  
  Widget _buildFileItem(ScopedFile file) {
    return InkWell(
      onTap: () {
        // TODO: Download/preview file
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(file.icon, size: 14, color: MonokaiTheme.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: TextStyle(fontSize: 11, color: MonokaiTheme.foreground),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    file.sizeFormatted,
                    style: TextStyle(fontSize: 9, color: MonokaiTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ============================================================================
  // RESIZE HANDLE
  // ============================================================================
  
  Widget _buildResizeHandle() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(120, 280);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 6,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 1,
              color: MonokaiTheme.divider,
            ),
          ),
        ),
      ),
    );
  }
  
  // ============================================================================
  // MESSAGE LIST
  // ============================================================================
  
  Widget _buildMessageList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: MonokaiTheme.cyan),
      );
    }
    
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: MonokaiTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(fontSize: 14, color: MonokaiTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Start the conversation!',
              style: TextStyle(fontSize: 12, color: MonokaiTheme.textSecondary.withOpacity(0.7)),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
    );
  }
  
  Widget _buildMessageBubble(ChatMessage message) {
    final isMe = message.isOwn;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: _getAvatarColor(message.authorName ?? 'Unknown'),
              child: Text(
                (message.authorName ?? 'U')[0].toUpperCase(),
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? MonokaiTheme.cyan.withOpacity(0.2) : MonokaiTheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isMe ? 12 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 12),
                ),
                border: Border.all(
                  color: isMe ? MonokaiTheme.cyan.withOpacity(0.3) : MonokaiTheme.divider,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.authorName ?? "Unknown",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _getAvatarColor(message.authorName ?? "Unknown"),
                        ),
                      ),
                    ),
                  
                  // Markdown-rendered content
                  _buildMarkdownContent(message.message),
                  
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(fontSize: 9, color: MonokaiTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
  
  Widget _buildMarkdownContent(String content) {
    // Simple markdown rendering
    // TODO: Use flutter_markdown for full support
    
    final lines = content.split('\n');
    final widgets = <Widget>[];
    
    for (final line in lines) {
      if (line.startsWith('# ')) {
        widgets.add(Text(
          line.substring(2),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: MonokaiTheme.foreground),
        ));
      } else if (line.startsWith('## ')) {
        widgets.add(Text(
          line.substring(3),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: MonokaiTheme.foreground),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: TextStyle(color: MonokaiTheme.cyan)),
            Expanded(child: _buildInlineMarkdown(line.substring(2))),
          ],
        ));
      } else if (line.startsWith('```')) {
        // Code block start/end - simplified
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: MonokaiTheme.background,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            line.replaceAll('```', ''),
            style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: MonokaiTheme.green),
          ),
        ));
      } else if (line.startsWith('> ')) {
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: MonokaiTheme.textSecondary, width: 2)),
          ),
          child: _buildInlineMarkdown(line.substring(2)),
        ));
      } else {
        widgets.add(_buildInlineMarkdown(line));
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
  
  Widget _buildInlineMarkdown(String text) {
    // Handle **bold**, *italic*, `code`, [links](url)
    final spans = <TextSpan>[];
    
    // Simplified - just render as plain text with basic formatting
    // Full implementation would use regex to parse inline markdown
    
    String remaining = text;
    
    // Bold
    final boldRegex = RegExp(r'\*\*(.+?)\*\*');
    // Italic
    final italicRegex = RegExp(r'\*(.+?)\*');
    // Code
    final codeRegex = RegExp(r'`(.+?)`');
    
    // For simplicity, just show text with code highlighting
    if (codeRegex.hasMatch(remaining)) {
      final parts = remaining.split(codeRegex);
      final codes = codeRegex.allMatches(remaining).map((m) => m.group(1)!).toList();
      
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          spans.add(TextSpan(text: parts[i]));
        }
        if (i < codes.length) {
          spans.add(TextSpan(
            text: codes[i],
            style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: MonokaiTheme.background,
              color: MonokaiTheme.orange,
            ),
          ));
        }
      }
    } else {
      spans.add(TextSpan(text: remaining));
    }
    
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 13, color: MonokaiTheme.foreground, height: 1.4),
        children: spans,
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${time.month}/${time.day}';
  }
  
  // ============================================================================
  // INPUT AREA
  // ============================================================================
  
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        border: Border(top: BorderSide(color: MonokaiTheme.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attach button
          IconButton(
            icon: const Icon(Icons.attach_file, size: 20),
            color: MonokaiTheme.textSecondary,
            onPressed: () {
              // TODO: File picker
            },
          ),
          
          // Simple input field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: MonokaiTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MonokaiTheme.divider),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                maxLines: null,
                style: TextStyle(fontSize: 13, color: MonokaiTheme.foreground),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: MonokaiTheme.textSecondary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // Send button
          IconButton(
            icon: const Icon(Icons.send, size: 20),
            color: MonokaiTheme.cyan,
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DM DIALOG
// ============================================================================

class _DMDialog extends StatefulWidget {
  final MockPeer peer;
  final void Function(String message) onSend;
  
  const _DMDialog({required this.peer, required this.onSend});
  
  @override
  State<_DMDialog> createState() => _DMDialogState();
}

class _DMDialogState extends State<_DMDialog> {
  final _controller = TextEditingController();
  final _messages = <_DMMessage>[];
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    setState(() {
      _messages.add(_DMMessage(text: text, isMe: true, time: DateTime.now()));
    });
    
    widget.onSend(text);
    _controller.clear();
    
    // Simulate reply after delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _messages.add(_DMMessage(
            text: 'Thanks for the message! 👋',
            isMe: false,
            time: DateTime.now(),
          ));
        });
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: MonokaiTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _getColor(widget.peer.name),
                  child: Text(
                    widget.peer.name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.peer.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: MonokaiTheme.foreground,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.peer.isOnline ? MonokaiTheme.green : MonokaiTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.peer.isOnline ? 'Online' : 'Offline',
                            style: TextStyle(fontSize: 12, color: MonokaiTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: MonokaiTheme.textSecondary,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            const Divider(color: MonokaiTheme.divider),
            
            // Messages
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Text(
                        'Start a conversation with ${widget.peer.name}',
                        style: TextStyle(color: MonokaiTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = _messages[i];
                        return Align(
                          alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: msg.isMe
                                  ? MonokaiTheme.cyan.withOpacity(0.2)
                                  : MonokaiTheme.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              msg.text,
                              style: TextStyle(color: MonokaiTheme.foreground),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            const SizedBox(height: 12),
            
            // Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: MonokaiTheme.foreground),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: MonokaiTheme.textSecondary),
                      filled: true,
                      fillColor: MonokaiTheme.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: MonokaiTheme.cyan,
                  onPressed: _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Color _getColor(String name) {
    final colors = [MonokaiTheme.cyan, MonokaiTheme.green, MonokaiTheme.orange, MonokaiTheme.pink, MonokaiTheme.purple];
    return colors[name.hashCode.abs() % colors.length];
  }
}

class _DMMessage {
  final String text;
  final bool isMe;
  final DateTime time;
  
  _DMMessage({required this.text, required this.isMe, required this.time});
}
