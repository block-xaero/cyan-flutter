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
import 'markdown_chat.dart';

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
  
  /// Chat scope filter: 'all' shows hierarchy, 'current' shows only this scope
  String _scopeFilter = 'current';
  
  /// Whether user is currently typing inside a code fence
  bool _isInCodeBlock = false;
  String _codeBlockLang = '';
  
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
    _messageController.addListener(_detectCodeBlock);
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
    
    // Tag board-level messages with board ID prefix
    String messageBody = text;
    if (widget.context.scope == 'board') {
      final boardId = widget.context.rawId;
      messageBody = '§board:$boardId§$text';
    }
    
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
      message: messageBody,
    ));
    
    _messageController.clear();
    setState(() => _isInCodeBlock = false);
    _focusNode.requestFocus();
  }
  
  void _detectCodeBlock() {
    final text = _messageController.text;
    final fenceCount = RegExp(r'```').allMatches(text).length;
    final inCode = fenceCount.isOdd;
    
    String lang = '';
    if (inCode) {
      // Extract language from last opening fence
      final lastFence = text.lastIndexOf('```');
      if (lastFence >= 0) {
        final afterFence = text.substring(lastFence + 3);
        final newline = afterFence.indexOf('\n');
        final langStr = newline >= 0 ? afterFence.substring(0, newline).trim() : afterFence.trim();
        if (langStr.isNotEmpty && langStr.length < 20 && !langStr.contains(' ')) {
          lang = langStr;
        }
      }
    }
    
    if (inCode != _isInCodeBlock || lang != _codeBlockLang) {
      setState(() {
        _isInCodeBlock = inCode;
        _codeBlockLang = lang;
      });
    }
  }
  
  /// Strip board tag prefix from message for display
  static String _stripBoardTag(String message) {
    if (message.startsWith('§board:')) {
      final endTag = message.indexOf('§', 7);
      if (endTag > 0) return message.substring(endTag + 1);
    }
    return message;
  }
  
  /// Extract board ID from message tag
  static String? _extractBoardId(String message) {
    if (message.startsWith('§board:')) {
      final endTag = message.indexOf('§', 7);
      if (endTag > 0) return message.substring(7, endTag);
    }
    return null;
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
    
    final showFilter = widget.context.scope == 'board' || widget.context.scope == 'workspace';
    
    final filterLabel = switch (widget.context.scope) {
      'board' => 'Board only',
      'workspace' => 'Workspace only',
      _ => 'Current',
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
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          
          const SizedBox(width: 4),
          
          // Scope icon + title
          Icon(scopeIcon, size: 16, color: scopeColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.context.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MonokaiTheme.foreground,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.context.scope} chat',
                  style: TextStyle(fontSize: 9, color: scopeColor),
                ),
              ],
            ),
          ),
          
          // Scope filter toggle (board and workspace only)
          if (showFilter)
            _buildFilterToggle(scopeColor, filterLabel),
          
          IconButton(
            icon: const Icon(Icons.more_vert, size: 16),
            color: MonokaiTheme.textSecondary,
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilterToggle(Color scopeColor, String filterLabel) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MonokaiTheme.divider.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _filterChip('All', 'all', scopeColor),
          _filterChip(filterLabel, 'current', scopeColor),
        ],
      ),
    );
  }
  
  Widget _filterChip(String label, String value, Color activeColor) {
    final isActive = _scopeFilter == value;
    return GestureDetector(
      onTap: () {
        print('🎯 Filter tapped: $value (was $_scopeFilter)');
        setState(() => _scopeFilter = value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? activeColor : MonokaiTheme.textSecondary,
          ),
        ),
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
    
    // Apply scope filter
    final filtered = _getFilteredMessages();
    
    if (filtered.isEmpty) {
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
              _scopeFilter == 'current' 
                ? 'No messages in this ${widget.context.scope}' 
                : 'Start the conversation!',
              style: TextStyle(fontSize: 12, color: MonokaiTheme.textSecondary.withOpacity(0.7)),
            ),
          ],
        ),
      );
    }
    
    // Build items with workspace headers when showing "all" in group scope
    final items = <Widget>[];
    String? lastWorkspaceId;
    
    for (final msg in filtered) {
      // Insert workspace header when workspace changes (group scope + all filter)
      if (widget.context.scope == 'group' && _scopeFilter == 'all' && msg.workspaceId != lastWorkspaceId) {
        lastWorkspaceId = msg.workspaceId;
        final wsName = _getWorkspaceName(msg.workspaceId);
        items.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(child: Divider(color: MonokaiTheme.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: MonokaiTheme.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MonokaiTheme.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspaces, size: 10, color: MonokaiTheme.green),
                      const SizedBox(width: 4),
                      Text(wsName, style: TextStyle(fontSize: 9, color: MonokaiTheme.green, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              Expanded(child: Divider(color: MonokaiTheme.divider)),
            ],
          ),
        ));
      }
      items.add(_buildMessageBubble(msg));
    }
    
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      children: items,
    );
  }
  
  /// Get filtered messages based on scope filter
  List<ChatMessage> _getFilteredMessages() {
    print('🔍 Filter: scope=${widget.context.scope}, filter=$_scopeFilter, total=${_messages.length}');
    
    if (_scopeFilter == 'all') {
      print('🔍 Returning all ${_messages.length} messages');
      return _messages;
    }
    
    // 'current' filter — only messages matching this exact scope
    switch (widget.context.scope) {
      case 'board':
        // Only show messages tagged with this board ID
        final boardId = widget.context.rawId;
        final filtered = _messages.where((m) {
          final taggedBoard = _extractBoardId(m.message);
          return taggedBoard == boardId;
        }).toList();
        print('🔍 Board filter: boardId=$boardId, found ${filtered.length} tagged messages');
        return filtered;
      case 'workspace':
        // Only messages in this workspace that are NOT tagged to a specific board
        final wsId = widget.context.rawId;
        final filtered = _messages.where((m) {
          final isThisWs = m.workspaceId == wsId;
          final isBoardTagged = m.message.startsWith('§board:');
          return isThisWs && !isBoardTagged;
        }).toList();
        print('🔍 Workspace filter: wsId=$wsId, found ${filtered.length} workspace-only messages');
        return filtered;
      case 'group':
        // Group = all (no further filtering needed)
        return _messages;
      default:
        return _messages;
    }
  }
  
  /// Look up workspace name from file tree
  String _getWorkspaceName(String workspaceId) {
    final fileTreeState = ref.read(fileTreeProvider);
    for (final group in fileTreeState.groups) {
      for (final ws in group.workspaces) {
        if (ws.id == workspaceId) return ws.name;
      }
    }
    return workspaceId.substring(0, 8);
  }
  
  Widget _buildMessageBubble(ChatMessage message) {
    final isMe = message.isOwn;
    final displayMessage = _stripBoardTag(message.message);
    final authorName = message.authorName ?? 'Unknown';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: _getAvatarColor(authorName),
                child: Text(
                  authorName[0].toUpperCase(),
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe 
                  ? MonokaiTheme.cyan.withOpacity(0.12) 
                  : const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                border: Border.all(
                  color: isMe 
                    ? MonokaiTheme.cyan.withOpacity(0.15) 
                    : const Color(0xFF3E3D32).withOpacity(0.4),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author + time row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isMe)
                        Text(
                          authorName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _getAvatarColor(authorName),
                          ),
                        ),
                      if (!isMe) const SizedBox(width: 8),
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(fontSize: 9, color: MonokaiTheme.textSecondary.withOpacity(0.6)),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Markdown-rendered content (with board tag stripped)
                  MarkdownRenderer(markdown: displayMessage, fontSize: 13),
                ],
              ),
            ),
          ),
          
          if (isMe) const SizedBox(width: 8),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        border: Border(top: BorderSide(color: MonokaiTheme.divider.withOpacity(0.5))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Code block indicator bar
          if (_isInCodeBlock)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                border: Border.all(color: MonokaiTheme.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.code, size: 12, color: MonokaiTheme.green),
                  const SizedBox(width: 6),
                  Text(
                    _codeBlockLang.isNotEmpty ? _codeBlockLang : 'code',
                    style: TextStyle(fontSize: 10, color: MonokaiTheme.green, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    'Enter for newline · Close with \`\`\`',
                    style: TextStyle(fontSize: 9, color: MonokaiTheme.textSecondary),
                  ),
                ],
              ),
            ),
          
          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Main input container
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: _isInCodeBlock ? const Color(0xFF1A1A2E) : MonokaiTheme.background,
                    borderRadius: BorderRadius.circular(_isInCodeBlock ? 0 : 12),
                    border: Border.all(
                      color: _isInCodeBlock 
                        ? MonokaiTheme.green.withOpacity(0.3) 
                        : MonokaiTheme.divider.withOpacity(0.5),
                    ),
                  ),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent && 
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed &&
                          !_isInCodeBlock) {
                        _sendMessage();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      maxLines: null,
                      style: TextStyle(
                        fontSize: 13, 
                        color: MonokaiTheme.foreground,
                        fontFamily: _isInCodeBlock ? 'monospace' : null,
                        height: _isInCodeBlock ? 1.5 : 1.3,
                      ),
                      decoration: InputDecoration(
                        hintText: _isInCodeBlock 
                          ? 'Type code...' 
                          : 'Message${_getScopeHint()}',
                        hintStyle: TextStyle(
                          color: MonokaiTheme.textSecondary.withOpacity(0.5),
                          fontFamily: _isInCodeBlock ? 'monospace' : null,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // Send button - circular like Claude
              Container(
                decoration: BoxDecoration(
                  color: _messageController.text.trim().isNotEmpty 
                    ? MonokaiTheme.cyan 
                    : MonokaiTheme.divider,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_upward, size: 18, 
                    color: _messageController.text.trim().isNotEmpty 
                      ? MonokaiTheme.background 
                      : MonokaiTheme.textSecondary),
                  onPressed: _messageController.text.trim().isNotEmpty ? _sendMessage : null,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  String _getScopeHint() {
    switch (widget.context.scope) {
      case 'board': return ' this board...';
      case 'workspace': return ' this workspace...';
      case 'group': return ' this group...';
      default: return '...';
    }
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
