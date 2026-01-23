// ffi/component_bridge.dart
// Generic bridge for component-based command/event communication
// 
// This mirrors the Swift ComponentActor<Command, Event> pattern exactly:
// 1. Commands are serialized to JSON and sent via cyan_send_command()
// 2. Events are polled via cyan_poll_events() which dequeues from Rust VecDeque
// 3. Each component has its own event buffer in Rust

import 'dart:async';
import 'dart:convert';
import 'ffi_helpers.dart';

// ============================================================================
// BASE INTERFACES
// ============================================================================

/// Base interface for commands sent TO Rust
/// Mirrors Swift's ComponentCommand protocol
abstract class ComponentCommand {
  /// Convert command to JSON string for FFI
  String toJson();
  
  /// Optional description for status bar (e.g., "Loading chat...")
  String? get syncDescription => null;
}

/// Base interface for events received FROM Rust
/// Mirrors Swift's ComponentEvent protocol
abstract class ComponentEvent {
  static ComponentEvent? fromJson(String json) => null;
}

// ============================================================================
// COMPONENT BRIDGE
// ============================================================================

/// Generic bridge for component-based FFI communication.
/// 
/// Mirrors Swift's ComponentActor:
/// - Polls Rust event queue periodically (100ms default)
/// - Sends commands via JSON
/// - Dispatches events to listeners via Stream
/// 
/// Usage:
/// ```dart
/// final bridge = FileTreeBridge();
/// bridge.start();
/// bridge.events.listen((event) => handleEvent(event));
/// bridge.send(FileTreeCommand.snapshot());
/// ```
class ComponentBridge<C extends ComponentCommand, E extends ComponentEvent> {
  final String componentName;
  final E? Function(String json) eventParser;
  
  /// Stream of events from Rust
  final _eventController = StreamController<E>.broadcast();
  Stream<E> get events => _eventController.stream;
  
  Timer? _pollTimer;
  bool _isActive = false;
  final int pollIntervalMs;
  
  ComponentBridge({
    required this.componentName,
    required this.eventParser,
    this.pollIntervalMs = 100, // Same as Swift's 100ms
  });
  
  /// Start polling for events
  void start() {
    if (_isActive) return;
    _isActive = true;
    
    _pollTimer = Timer.periodic(
      Duration(milliseconds: pollIntervalMs),
      (_) => _pollEvents(),
    );
    
    print('🌉 ComponentBridge[$componentName] started (poll: ${pollIntervalMs}ms)');
  }
  
  /// Stop polling for events
  void stop() {
    _isActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    print('🌉 ComponentBridge[$componentName] stopped');
  }
  
  /// Send a command to Rust (queues to command channel)
  bool send(C command) {
    final json = command.toJson();
    print('📤 ComponentBridge[$componentName] sending: $json');
    final success = CyanFFI.sendCommand(componentName, json);
    
    if (!success) {
      print('⚠️ ComponentBridge[$componentName] failed to send: $json');
    } else {
      print('✅ ComponentBridge[$componentName] sent successfully');
    }
    
    return success;
  }
  
  /// Poll for events (called by timer)
  void _pollEvents() {
    if (!_isActive) return;
    
    // Poll until queue is empty (may have multiple events)
    while (true) {
      final json = CyanFFI.pollEvents(componentName);
      if (json == null || json.isEmpty) break;
      
      final event = eventParser(json);
      if (event != null) {
        _eventController.add(event);
      }
    }
  }
  
  /// Clean up resources
  void dispose() {
    stop();
    _eventController.close();
  }
}

// ============================================================================
// SPECIALIZED BRIDGES (match Swift components)
// ============================================================================

/// Bridge for file_tree component
class FileTreeBridge extends ComponentBridge<FileTreeCommand, FileTreeEvent> {
  FileTreeBridge() : super(
    componentName: 'file_tree',
    eventParser: FileTreeEvent.fromJson,
  );
}

/// Bridge for chat_panel component  
class ChatBridge extends ComponentBridge<ChatCommand, ChatEvent> {
  ChatBridge() : super(
    componentName: 'chat_panel',
    eventParser: ChatEvent.fromJson,
  );
}

/// Bridge for whiteboard component
class WhiteboardBridge extends ComponentBridge<WhiteboardCommand, WhiteboardEvent> {
  WhiteboardBridge() : super(
    componentName: 'whiteboard',
    eventParser: WhiteboardEvent.fromJson,
  );
}

/// Bridge for board_grid component
class BoardGridBridge extends ComponentBridge<BoardGridCommand, BoardGridEvent> {
  BoardGridBridge() : super(
    componentName: 'board_grid',
    eventParser: BoardGridEvent.fromJson,
  );
}

/// Bridge for network/status component
class NetworkStatusBridge extends ComponentBridge<NetworkStatusCommand, NetworkStatusEvent> {
  NetworkStatusBridge() : super(
    componentName: 'network',
    eventParser: NetworkStatusEvent.fromJson,
  );
}

// ============================================================================
// FILE TREE COMMAND/EVENT (matches Swift FileTreeTypes.swift)
// ============================================================================

class FileTreeCommand implements ComponentCommand {
  final String type;
  final Map<String, dynamic> data;
  
  FileTreeCommand._(this.type, [this.data = const {}]);
  
  // Factory constructors matching Swift
  factory FileTreeCommand.snapshot() => FileTreeCommand._('Snapshot');
  factory FileTreeCommand.seedDemoIfEmpty() => FileTreeCommand._('SeedDemoIfEmpty');
  factory FileTreeCommand.loadGroups({bool recursive = true}) => 
      FileTreeCommand._('LoadGroups', {'recursive': recursive});
  
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
  
  factory FileTreeCommand.createWorkspace({required String groupId, required String name}) =>
      FileTreeCommand._('CreateWorkspace', {'group_id': groupId, 'name': name});
  
  factory FileTreeCommand.renameWorkspace({required String id, required String name}) =>
      FileTreeCommand._('RenameWorkspace', {'id': id, 'name': name});
  
  factory FileTreeCommand.deleteWorkspace({required String id}) =>
      FileTreeCommand._('DeleteWorkspace', {'id': id});
  
  factory FileTreeCommand.leaveWorkspace({required String id}) =>
      FileTreeCommand._('LeaveWorkspace', {'id': id});
  
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
      case 'Snapshot': return 'Loading tree...';
      case 'SeedDemoIfEmpty': return 'Initializing...';
      case 'LoadGroups': return 'Refreshing...';
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
  
  // Event type checks
  bool get isTreeLoaded => type == 'TreeLoaded';
  bool get isGroupCreated => type == 'GroupCreated';
  bool get isGroupRenamed => type == 'GroupRenamed';
  bool get isGroupDeleted => type == 'GroupDeleted';
  bool get isWorkspaceCreated => type == 'WorkspaceCreated';
  bool get isBoardCreated => type == 'BoardCreated';
  bool get isSyncStarted => type == 'SyncStarted';
  bool get isSyncComplete => type == 'SyncComplete';
  bool get isError => type == 'Error';
  
  // Data accessors
  Map<String, dynamic>? get snapshot => data['snapshot'] as Map<String, dynamic>?;
  String? get errorMessage => data['message'] as String?;
  String? get id => data['id'] as String?;
}

// ============================================================================
// CHAT COMMAND/EVENT (matches Swift ChatTypes.swift)
// ============================================================================

class ChatCommand implements ComponentCommand {
  final String type;
  final Map<String, dynamic> data;
  
  ChatCommand._(this.type, [this.data = const {}]);
  
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
  
  factory ChatCommand.loadChatHistory({required String workspaceId}) =>
      ChatCommand._('LoadChatHistory', {'workspace_id': workspaceId});
  
  factory ChatCommand.startDirectChat({required String peerId, required String workspaceId}) =>
      ChatCommand._('StartDirectChat', {'peer_id': peerId, 'workspace_id': workspaceId});
  
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
  
  factory ChatCommand.loadDirectMessageHistory({required String peerId}) =>
      ChatCommand._('LoadDirectMessageHistory', {'peer_id': peerId});
  
  @override
  String toJson() => jsonEncode({'type': type, ...data});
  
  @override
  String? get syncDescription {
    switch (type) {
      case 'LoadChatHistory': return 'Loading chat...';
      case 'StartDirectChat': return 'Connecting...';
      case 'LoadDirectMessageHistory': return 'Loading messages...';
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
      return ChatEvent._(type, map);
    } catch (e) {
      print('⚠️ ChatEvent parse error: $e');
      return null;
    }
  }
  
  bool get isMessage => type == 'ChatSent';
  bool get isMessageDeleted => type == 'ChatDeleted';
  bool get isPeerJoined => type == 'PeerJoined';
  bool get isPeerLeft => type == 'PeerLeft';
  bool get isChatStreamReady => type == 'ChatStreamReady';
  bool get isDirectMessage => type == 'DirectMessage' || type == 'DirectMessageReceived';
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
  
  factory WhiteboardCommand.saveElement({
    required String boardId,
    required Map<String, dynamic> element,
  }) => WhiteboardCommand._('SaveElement', {'board_id': boardId, 'element': element});
  
  factory WhiteboardCommand.deleteElement({required String boardId, required String elementId}) =>
      WhiteboardCommand._('DeleteElement', {'board_id': boardId, 'element_id': elementId});
  
  factory WhiteboardCommand.clear({required String boardId}) =>
      WhiteboardCommand._('Clear', {'board_id': boardId});
  
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
      return BoardGridEvent._(type, map);
    } catch (e) {
      return null;
    }
  }
}

// ============================================================================
// NETWORK STATUS COMMAND/EVENT
// ============================================================================

class NetworkStatusCommand implements ComponentCommand {
  final String type;
  
  NetworkStatusCommand._(this.type);
  
  factory NetworkStatusCommand.getStatus() => NetworkStatusCommand._('GetStatus');
  
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
}
