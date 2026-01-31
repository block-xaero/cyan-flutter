// ffi/component_bridge.dart
// Generic bridge for component-based command/event communication
// Mirrors Swift's ComponentActor pattern exactly:
// 1. Commands are serialized to JSON and sent via cyan_send_command()
// 2. Events are polled via cyan_poll_events() which dequeues from Rust VecDeque
// 3. Each component has its own event buffer in Rust

import 'dart:async';
import 'dart:convert';
import 'ffi_helpers.dart';
import '../models/chat_models.dart' show ChatMessage;

// ============================================================================
// BASE INTERFACES
// ============================================================================

/// Base interface for commands sent TO Rust
/// Mirrors Swift's ComponentCommand protocol
abstract class ComponentCommand {
  String toJson();
  String? get syncDescription => null;
}

/// Base interface for events received FROM Rust
abstract class ComponentEvent {
  static ComponentEvent? fromJson(String json) => null;
}

// ============================================================================
// SYNC ACTIVITY NOTIFICATION
// ============================================================================

typedef SyncActivityCallback = void Function(bool isActive, String description);
SyncActivityCallback? _syncActivityCallback;

void setSyncActivityCallback(SyncActivityCallback callback) {
  _syncActivityCallback = callback;
}

void _postSyncActivity(bool isActive, String description) {
  _syncActivityCallback?.call(isActive, description);
}

// ============================================================================
// COMPONENT BRIDGE
// ============================================================================

/// Generic bridge for component-based FFI communication.
/// Mirrors Swift's ComponentActor pattern with async streams.
class ComponentBridge<C extends ComponentCommand, E extends ComponentEvent> {
  final String componentName;
  final E? Function(String json) eventParser;
  
  final _eventController = StreamController<E>.broadcast();
  Stream<E> get events => _eventController.stream;
  
  final _commandController = StreamController<C>();
  
  Timer? _pollTimer;
  bool _isActive = false;
  final int pollIntervalMs;
  
  ComponentBridge({
    required this.componentName,
    required this.eventParser,
    this.pollIntervalMs = 100,
  }) {
    // Process commands as they come in
    _commandController.stream.listen(_processCommand);
  }
  
  void _processCommand(C command) async {
    final json = command.toJson();
    
    // Post sync activity if command has description
    if (command.syncDescription != null) {
      _postSyncActivity(true, command.syncDescription!);
    }
    
    final success = CyanFFI.sendCommand(componentName, json);
    
    if (!success) {
      print('⚠️ ComponentBridge[$componentName] failed to send: $json');
    }
    
    // End sync activity after brief delay
    if (command.syncDescription != null) {
      await Future.delayed(const Duration(milliseconds: 300));
      _postSyncActivity(false, '');
    }
  }
  
  void start() {
    if (_isActive) return;
    _isActive = true;
    
    _pollTimer = Timer.periodic(
      Duration(milliseconds: pollIntervalMs),
      (_) => _pollEvents(),
    );
    
    print('🌉 ComponentBridge[$componentName] started');
  }
  
  void stop() {
    _isActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    print('🌉 ComponentBridge[$componentName] stopped');
  }
  
  /// Send command to Rust (queued processing)
  bool send(C command) {
    if (!_isActive) {
      print('⚠️ ComponentBridge[$componentName] not active, starting...');
      start();
    }
    _commandController.add(command);
    return true;
  }
  
  void _pollEvents() {
    if (!_isActive) return;
    
    while (true) {
      final json = CyanFFI.pollEvents(componentName);
      if (json == null || json.isEmpty) break;
      
      final event = eventParser(json);
      if (event != null) {
        _eventController.add(event);
      }
    }
  }
  
  void dispose() {
    stop();
    _commandController.close();
    _eventController.close();
  }
}

// ============================================================================
// SPECIALIZED BRIDGES
// ============================================================================

class FileTreeBridge extends ComponentBridge<FileTreeCommand, FileTreeEvent> {
  FileTreeBridge() : super(
    componentName: 'file_tree',
    eventParser: FileTreeEvent.fromJson,
  );
}

class ChatBridge extends ComponentBridge<ChatCommand, ChatEvent> {
  ChatBridge() : super(
    componentName: 'chat_panel',
    eventParser: ChatEvent.fromJson,
  );
}

class WhiteboardBridge extends ComponentBridge<WhiteboardCommand, WhiteboardEvent> {
  WhiteboardBridge() : super(
    componentName: 'whiteboard',
    eventParser: WhiteboardEvent.fromJson,
  );
}

class BoardGridBridge extends ComponentBridge<BoardGridCommand, BoardGridEvent> {
  BoardGridBridge() : super(
    componentName: 'board_grid',
    eventParser: BoardGridEvent.fromJson,
  );
}

class NetworkStatusBridge extends ComponentBridge<NetworkStatusCommand, NetworkStatusEvent> {
  NetworkStatusBridge() : super(
    componentName: 'network',
    eventParser: NetworkStatusEvent.fromJson,
  );
}

// ============================================================================
// FILE TREE COMMAND/EVENT (matches Rust CommandMsg enum)
// ============================================================================

class FileTreeCommand implements ComponentCommand {
  final String type;
  final Map<String, dynamic> data;
  
  FileTreeCommand._(this.type, [this.data = const {}]);
  
  // Lifecycle
  factory FileTreeCommand.snapshot() => FileTreeCommand._('Snapshot');
  factory FileTreeCommand.seedDemoIfEmpty() => FileTreeCommand._('SeedDemoIfEmpty');
  
  // Groups
  factory FileTreeCommand.createGroup({
    required String name,
    String icon = 'folder.fill',
    String color = '#00AEEF',
  }) => FileTreeCommand._('CreateGroup', {'name': name, 'icon': icon, 'color': color});
  
  factory FileTreeCommand.renameGroup({required String id, required String name}) =>
      FileTreeCommand._('RenameGroup', {'id': id, 'name': name});
  
  factory FileTreeCommand.deleteGroup({required String id}) =>
      FileTreeCommand._('DeleteGroup', {'id': id});
  
  factory FileTreeCommand.leaveGroup({required String id}) =>
      FileTreeCommand._('LeaveGroup', {'id': id});
  
  // Workspaces
  factory FileTreeCommand.createWorkspace({required String groupId, required String name}) =>
      FileTreeCommand._('CreateWorkspace', {'group_id': groupId, 'name': name});
  
  factory FileTreeCommand.renameWorkspace({required String id, required String name}) =>
      FileTreeCommand._('RenameWorkspace', {'id': id, 'name': name});
  
  factory FileTreeCommand.deleteWorkspace({required String id}) =>
      FileTreeCommand._('DeleteWorkspace', {'id': id});
  
  factory FileTreeCommand.leaveWorkspace({required String id}) =>
      FileTreeCommand._('LeaveWorkspace', {'id': id});
  
  // Boards
  factory FileTreeCommand.createBoard({required String workspaceId, required String name}) =>
      FileTreeCommand._('CreateBoard', {'workspace_id': workspaceId, 'name': name});
  
  factory FileTreeCommand.renameBoard({required String id, required String name}) =>
      FileTreeCommand._('RenameBoard', {'id': id, 'name': name});
  
  factory FileTreeCommand.deleteBoard({required String id}) =>
      FileTreeCommand._('DeleteBoard', {'id': id});
  
  factory FileTreeCommand.leaveBoard({required String id}) =>
      FileTreeCommand._('LeaveBoard', {'id': id});
  
  @override
  String toJson() => jsonEncode({'type': type, ...data});
  
  @override
  String? get syncDescription {
    switch (type) {
      case 'Snapshot': return 'Loading...';
      case 'SeedDemoIfEmpty': return 'Initializing...';
      case 'CreateGroup': return 'Creating group...';
      case 'CreateWorkspace': return 'Creating workspace...';
      case 'CreateBoard': return 'Creating board...';
      default: return null;
    }
  }
}

class FileTreeEvent implements ComponentEvent {
  final String type;
  final Map<String, dynamic> data;
  
  FileTreeEvent._(this.type, this.data);
  
  static FileTreeEvent? fromJson(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type == null) return null;
      return FileTreeEvent._(type, map);
    } catch (e) {
      print('⚠️ FileTreeEvent parse error: $e');
      return null;
    }
  }
  
  bool get isTreeLoaded => type == 'TreeLoaded';
  bool get isGroupCreated => type == 'GroupCreated';
  bool get isGroupRenamed => type == 'GroupRenamed';
  bool get isGroupDeleted => type == 'GroupDeleted';
  bool get isWorkspaceCreated => type == 'WorkspaceCreated';
  bool get isWorkspaceRenamed => type == 'WorkspaceRenamed';
  bool get isWorkspaceDeleted => type == 'WorkspaceDeleted';
  bool get isBoardCreated => type == 'BoardCreated';
  bool get isBoardRenamed => type == 'BoardRenamed';
  bool get isBoardDeleted => type == 'BoardDeleted';
  bool get isFileUploaded => type == 'FileUploaded';
  bool get isFileDownloaded => type == 'FileDownloaded';
  bool get isNetwork => type == 'Network';
  bool get isError => type == 'Error';
  
  String? get errorMessage => data['message'] as String?;
  String? get id => data['id'] as String?;
  Map<String, dynamic>? get treeData => data['data'] as Map<String, dynamic>?;
}

// ============================================================================
// CHAT COMMAND/EVENT (matches Rust CommandMsg enum)
// ============================================================================

class ChatCommand implements ComponentCommand {
  final String type;
  final Map<String, dynamic> data;
  
  ChatCommand._(this.type, [this.data = const {}]);
  
  // Group/Workspace chat
  factory ChatCommand.sendMessage({
    required String workspaceId,
    required String message,
    String? parentId,
  }) => ChatCommand._('SendChat', {
    'workspace_id': workspaceId,
    'message': message,
    if (parentId != null) 'parent_id': parentId,
  });
  
  factory ChatCommand.deleteMessage({required String id}) =>
      ChatCommand._('DeleteChat', {'id': id});
  
  factory ChatCommand.loadHistory({
    required String workspaceId,
    String? scope,
    String? scopeId,
  }) => ChatCommand._('LoadChatHistory', {
    'workspace_id': workspaceId,
    if (scope != null) 'scope': scope,
    if (scopeId != null) 'scope_id': scopeId,
  });
  
  // Scoped chat - group/workspace/board
  factory ChatCommand.loadScopedHistory({
    required String scope,  // 'group', 'workspace', 'board'
    required String scopeId,
  }) => ChatCommand._('LoadChatHistory', {
    'scope': scope,
    'scope_id': scopeId,
  });
  
  factory ChatCommand.send({
    required String scope,
    required String scopeId,
    required String content,
    String? parentId,
  }) {
    // Map scope to appropriate command type
    switch (scope) {
      case 'group':
        return ChatCommand._('SendGroupChat', {
          'group_id': scopeId,
          'message': content,
          if (parentId != null) 'parent_id': parentId,
        });
      case 'workspace':
        return ChatCommand._('SendChat', {
          'workspace_id': scopeId,
          'message': content,
          if (parentId != null) 'parent_id': parentId,
        });
      case 'board':
        return ChatCommand._('SendBoardChat', {
          'board_id': scopeId,
          'message': content,
          if (parentId != null) 'parent_id': parentId,
        });
      default:
        return ChatCommand._('SendChat', {
          'workspace_id': scopeId,
          'message': content,
          if (parentId != null) 'parent_id': parentId,
        });
    }
  }
  
  // Direct messages
  factory ChatCommand.startDirectChat({
    required String peerId,
    required String workspaceId,
  }) => ChatCommand._('StartDirectChat', {
    'peer_id': peerId,
    'workspace_id': workspaceId,
  });
  
  factory ChatCommand.sendDirectMessage({
    required String peerId,
    required String workspaceId,
    required String message,
    String? parentId,
  }) => ChatCommand._('SendDirectMessage', {
    'peer_id': peerId,
    'workspace_id': workspaceId,
    'message': message,
    if (parentId != null) 'parent_id': parentId,
  });
  
  factory ChatCommand.loadDirectHistory({required String peerId}) =>
      ChatCommand._('LoadDirectMessageHistory', {'peer_id': peerId});
  
  // Alias for compatibility
  factory ChatCommand.loadDirectMessageHistory({required String peerId}) =>
      ChatCommand._('LoadDirectMessageHistory', {'peer_id': peerId});
  
  @override
  String toJson() => jsonEncode({'type': type, ...data});
  
  @override
  String? get syncDescription {
    switch (type) {
      case 'LoadChatHistory': return 'Loading chat...';
      case 'LoadDirectMessageHistory': return 'Loading messages...';
      case 'StartDirectChat': return 'Connecting...';
      default: return null;
    }
  }
}

class ChatEvent implements ComponentEvent {
  final String type;
  final Map<String, dynamic> data;
  
  ChatEvent._(this.type, this.data);
  
  static ChatEvent? fromJson(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type == null) return null;
      
      // Handle nested data like Swift does
      Map<String, dynamic> data;
      if (map.containsKey('data') && map['data'] is Map) {
        data = Map<String, dynamic>.from(map['data'] as Map);
        // Also include type in data for convenience
        data['_event_type'] = type;
      } else {
        data = Map<String, dynamic>.from(map);
      }
      
      // Handle Network wrapper events (Swift pattern)
      if (type == 'Network' && data.containsKey('type')) {
        final innerType = data['type'] as String?;
        if (innerType != null) {
          return ChatEvent._(innerType, data);
        }
      }
      
      return ChatEvent._(type, data);
    } catch (e) {
      print('⚠️ ChatEvent parse error: $e');
      return null;
    }
  }
  
  // Message types matching Swift ChatEvent cases
  bool get isMessage => type == 'ChatReceived' || type == 'ChatSent';
  bool get isMessageReceived => type == 'ChatReceived' || type == 'ChatSent';
  bool get isMessageDeleted => type == 'ChatDeleted';
  bool get isHistory => type == 'ChatHistory';
  bool get isHistoryLoaded => type == 'ChatHistory' || type == 'ChatHistoryLoaded';
  bool get isPeerJoined => type == 'PeerJoined';
  bool get isPeerLeft => type == 'PeerLeft';
  bool get isStreamReady => type == 'ChatStreamReady';
  bool get isChatStreamReady => type == 'ChatStreamReady'; // alias
  bool get isChatStreamClosed => type == 'ChatStreamClosed';
  bool get isDirectMessage => type == 'DirectMessage' || type == 'DirectMessageReceived';
  bool get isDirectHistory => type == 'DirectMessageHistory';
  
  // Data accessors matching Swift event structure
  String? get messageId => data['id'] as String?;
  String? get workspaceId => data['workspace_id'] as String?;
  String? get message => data['message'] as String?;
  String? get author => data['author'] as String?;
  String? get parentId => data['parent_id'] as String?;
  String? get peerId => data['peer_id'] as String?;
  String? get groupId => data['group_id'] as String?;
  List<String> get mentions => (data['mentions'] as List?)?.cast<String>() ?? [];
  bool get isBroadcast => data['is_broadcast'] as bool? ?? false;
  bool get mentionsMe => data['mentions_me'] as bool? ?? false;
  
  int get timestamp {
    final ts = data['timestamp'];
    if (ts is int) return ts;
    if (ts is double) return ts.toInt();
    if (ts is num) return ts.toInt();
    return 0;
  }
  
  DateTime get timestampDate => DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  
  /// Parse messages array from history event
  List<ChatMessage> get messages {
    final messagesArray = data['messages'] as List<dynamic>? ?? data['history'] as List<dynamic>? ?? [];
    return messagesArray.map((m) {
      if (m is Map<String, dynamic>) {
        return ChatMessage.fromJson(m);
      }
      return null;
    }).whereType<ChatMessage>().toList();
  }
  
  /// Get single message from event (for ChatReceived)
  ChatMessage? get singleMessage {
    if (messageId == null) return null;
    return ChatMessage(
      id: messageId!,
      workspaceId: workspaceId ?? '',
      message: message ?? '',
      authorId: author ?? '',
      authorName: data['author_name'] as String?,
      parentId: parentId,
      timestamp: timestampDate,
      mentions: mentions,
      isBroadcast: isBroadcast,
      mentionsMe: mentionsMe,
      isOwn: data['is_own'] as bool? ?? false,
    );
  }
}

// ============================================================================
// WHITEBOARD COMMAND/EVENT
// ============================================================================

class WhiteboardCommand implements ComponentCommand {
  final String type;
  final Map<String, dynamic> data;
  
  WhiteboardCommand._(this.type, [this.data = const {}]);
  
  factory WhiteboardCommand.loadElements({required String boardId}) =>
      WhiteboardCommand._('LoadElements', {'board_id': boardId});
  
  factory WhiteboardCommand.createElement({
    required String boardId,
    required String elementType,
    required double x,
    required double y,
    required double width,
    required double height,
    int zIndex = 0,
    Map<String, dynamic>? style,
    Map<String, dynamic>? content,
  }) => WhiteboardCommand._('CreateWhiteboardElement', {
    'board_id': boardId,
    'element_type': elementType,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'z_index': zIndex,
    if (style != null) 'style_json': jsonEncode(style),
    if (content != null) 'content_json': jsonEncode(content),
  });
  
  factory WhiteboardCommand.updateElement({
    required String id,
    required String boardId,
    required String elementType,
    required double x,
    required double y,
    required double width,
    required double height,
    int zIndex = 0,
    Map<String, dynamic>? style,
    Map<String, dynamic>? content,
  }) => WhiteboardCommand._('UpdateWhiteboardElement', {
    'id': id,
    'board_id': boardId,
    'element_type': elementType,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'z_index': zIndex,
    if (style != null) 'style_json': jsonEncode(style),
    if (content != null) 'content_json': jsonEncode(content),
  });
  
  factory WhiteboardCommand.deleteElement({required String id, required String boardId}) =>
      WhiteboardCommand._('DeleteWhiteboardElement', {'id': id, 'board_id': boardId});
  
  factory WhiteboardCommand.clear({required String boardId}) =>
      WhiteboardCommand._('ClearWhiteboard', {'board_id': boardId});
  
  @override
  String toJson() => jsonEncode({'type': type, ...data});
  
  @override
  String? get syncDescription => null;
}

class WhiteboardEvent implements ComponentEvent {
  final String type;
  final Map<String, dynamic> data;
  
  WhiteboardEvent._(this.type, this.data);
  
  static WhiteboardEvent? fromJson(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type == null) return null;
      return WhiteboardEvent._(type, map);
    } catch (e) {
      return null;
    }
  }
  
  bool get isElementsLoaded => type == 'ElementsLoaded';
  bool get isElementCreated => type == 'ElementCreated';
  bool get isElementUpdated => type == 'ElementUpdated';
  bool get isElementDeleted => type == 'ElementDeleted';
  bool get isCleared => type == 'Cleared';
  
  List<dynamic>? get elements => data['elements'] as List<dynamic>?;
  Map<String, dynamic>? get element => data['element'] as Map<String, dynamic>?;
  String? get elementId => data['element_id'] as String?;
}

// ============================================================================
// BOARD GRID COMMAND/EVENT
// ============================================================================

class BoardGridCommand implements ComponentCommand {
  final String type;
  final Map<String, dynamic> data;
  
  BoardGridCommand._(this.type, [this.data = const {}]);
  
  factory BoardGridCommand.loadBoards({String? groupId, String? workspaceId}) =>
      BoardGridCommand._('LoadBoards', {
        if (groupId != null) 'group_id': groupId,
        if (workspaceId != null) 'workspace_id': workspaceId,
      });
  
  factory BoardGridCommand.updateMetadata({
    required String boardId,
    List<String>? labels,
    int? rating,
    bool? isPinned,
    String? boardType,
  }) => BoardGridCommand._('UpdateBoardMetadata', {
    'board_id': boardId,
    if (labels != null) 'labels': labels,
    if (rating != null) 'rating': rating,
    if (isPinned != null) 'is_pinned': isPinned,
    if (boardType != null) 'board_type': boardType,
  });
  
  factory BoardGridCommand.incrementViewCount({required String boardId}) =>
      BoardGridCommand._('IncrementBoardViewCount', {'board_id': boardId});
  
  factory BoardGridCommand.setPinned({required String boardId, required bool isPinned}) =>
      BoardGridCommand._('SetBoardPinned', {'board_id': boardId, 'is_pinned': isPinned});
  
  @override
  String toJson() => jsonEncode({'type': type, ...data});
  
  @override
  String? get syncDescription => null;
}

class BoardGridEvent implements ComponentEvent {
  final String type;
  final Map<String, dynamic> data;
  
  BoardGridEvent._(this.type, this.data);
  
  static BoardGridEvent? fromJson(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type == null) return null;
      
      // Handle nested data
      Map<String, dynamic> data;
      if (map.containsKey('data') && map['data'] is Map) {
        data = Map<String, dynamic>.from(map['data'] as Map);
      } else {
        data = Map<String, dynamic>.from(map);
      }
      
      return BoardGridEvent._(type, data);
    } catch (e) {
      print('⚠️ BoardGridEvent parse error: $e');
      return null;
    }
  }
  
  bool get isBoardsLoaded => type == 'BoardsLoaded';
  bool get isBoardCreated => type == 'BoardCreated';
  bool get isBoardRenamed => type == 'BoardRenamed';
  bool get isBoardDeleted => type == 'BoardDeleted';
  bool get isBoardPinChanged => type == 'BoardPinChanged';
  bool get isBoardRatingChanged => type == 'BoardRatingChanged';
  bool get isBoardLabelsChanged => type == 'BoardLabelsChanged';
  bool get isMetadataUpdated => type == 'MetadataUpdated';
  
  /// Parse boards array from BoardsLoaded event
  List<BoardGridItem> get boards {
    final boardsArray = data['boards'] as List<dynamic>? ?? [];
    return boardsArray.map((b) {
      final bMap = b as Map<String, dynamic>;
      return BoardGridItem(
        id: bMap['id'] as String? ?? '',
        workspaceId: bMap['workspace_id'] as String? ?? '',
        groupId: bMap['group_id'] as String? ?? '',
        name: bMap['name'] as String? ?? 'Untitled',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          ((bMap['created_at'] as int?) ?? 0) * 1000,
        ),
        elementCount: bMap['element_count'] as int? ?? 0,
        isPinned: bMap['is_pinned'] as bool? ?? false,
        labels: _parseLabels(bMap['labels']),
        rating: bMap['rating'] as int? ?? 0,
        lastAccessed: bMap['last_accessed'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                ((bMap['last_accessed'] as int?) ?? 0) * 1000)
            : null,
      );
    }).toList();
  }
  
  List<String> _parseLabels(dynamic labels) {
    if (labels == null) return [];
    if (labels is List) return labels.cast<String>();
    if (labels is String) {
      try {
        final parsed = jsonDecode(labels) as List;
        return parsed.cast<String>();
      } catch (_) {
        return [];
      }
    }
    return [];
  }
  
  Map<String, dynamic>? get metadata => data['metadata'] as Map<String, dynamic>?;
}

/// Board item with full metadata
class BoardGridItem {
  final String id;
  final String workspaceId;
  final String groupId;
  final String name;
  final DateTime createdAt;
  final int elementCount;
  final bool isPinned;
  final List<String> labels;
  final int rating;
  final DateTime? lastAccessed;
  
  const BoardGridItem({
    required this.id,
    required this.workspaceId,
    required this.groupId,
    required this.name,
    required this.createdAt,
    this.elementCount = 0,
    this.isPinned = false,
    this.labels = const [],
    this.rating = 0,
    this.lastAccessed,
  });
}

// ============================================================================
// NETWORK STATUS COMMAND/EVENT
// ============================================================================

class NetworkStatusCommand implements ComponentCommand {
  final String type;
  
  NetworkStatusCommand._(this.type);
  
  factory NetworkStatusCommand.getStatus() => NetworkStatusCommand._('GetStatus');
  factory NetworkStatusCommand.getPeers() => NetworkStatusCommand._('GetPeers');
  
  @override
  String toJson() => jsonEncode({'type': type});
  
  @override
  String? get syncDescription => null;
}

class NetworkStatusEvent implements ComponentEvent {
  final String type;
  final Map<String, dynamic> data;
  
  NetworkStatusEvent._(this.type, this.data);
  
  static NetworkStatusEvent? fromJson(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type == null) return null;
      return NetworkStatusEvent._(type, map);
    } catch (e) {
      return null;
    }
  }
  
  bool get isPeerConnected => type == 'PeerConnected';
  bool get isPeerDisconnected => type == 'PeerDisconnected';
  bool get isNetworkStatus => type == 'NetworkStatus';
  bool get isPeerList => type == 'PeerList';
  
  String? get peerId => data['peer_id'] as String?;
  String? get peerName => data['peer_name'] as String?;
  int? get peerCount => data['peer_count'] as int?;
  int? get objectCount => data['object_count'] as int?;
  List<dynamic>? get peers => data['peers'] as List<dynamic>?;
}

// ============================================================================
// FILE COMMAND/EVENT (for uploads/downloads)
// ============================================================================

class FileCommand implements ComponentCommand {
  final String type;
  final Map<String, dynamic> data;
  
  FileCommand._(this.type, [this.data = const {}]);
  
  factory FileCommand.uploadToGroup({
    required String path,
    required String groupId,
  }) => FileCommand._('UploadToGroup', {
    'path': path,
    'group_id': groupId,
  });
  
  factory FileCommand.uploadToWorkspace({
    required String path,
    required String workspaceId,
  }) => FileCommand._('UploadToWorkspace', {
    'path': path,
    'workspace_id': workspaceId,
  });
  
  factory FileCommand.requestDownload({
    required String fileId,
  }) => FileCommand._('RequestFileDownload', {
    'file_id': fileId,
  });
  
  factory FileCommand.getFiles({String? groupId, String? workspaceId}) =>
      FileCommand._('GetFiles', {
        if (groupId != null) 'group_id': groupId,
        if (workspaceId != null) 'workspace_id': workspaceId,
      });
  
  @override
  String toJson() => jsonEncode({'type': type, ...data});
  
  @override
  String? get syncDescription {
    switch (type) {
      case 'UploadToGroup':
      case 'UploadToWorkspace':
        return 'Uploading file...';
      case 'RequestFileDownload':
        return 'Downloading file...';
      default:
        return null;
    }
  }
}
