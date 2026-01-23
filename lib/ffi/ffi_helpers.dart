// ffi/ffi_helpers.dart
// Safe Dart wrappers for all FFI functions
// Handles memory allocation/deallocation, null checks, string conversion

import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'cyan_bindings.dart';

// ============================================================================
// STRING HELPERS
// ============================================================================

extension Utf8PointerExt on Pointer<Utf8> {
  /// Convert to Dart string and free using cyan_free_string
  String toDartStringAndFree() {
    if (this == nullptr) return '';
    final result = toDartString();
    CyanBindings.instance.freeString(this);
    return result;
  }
}

// ============================================================================
// CYAN FFI - SAFE WRAPPERS
// ============================================================================

/// Static class providing safe Dart wrappers for all cyan_* FFI functions.
/// Matches the ComponentActor pattern from Swift:
/// - sendCommand() queues JSON command to Rust
/// - pollEvents() dequeues JSON event from Rust
class CyanFFI {
  static final _b = CyanBindings.instance;
  
  // ==========================================================================
  // LIFECYCLE
  // ==========================================================================
  
  static bool init(String dbPath) {
    final ptr = dbPath.toNativeUtf8();
    try {
      return _b.init(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool initWithIdentity({
    required String dbPath,
    required String secretKeyHex,
    required String relayUrl,
    required String discoveryKey,
  }) {
    final dbPtr = dbPath.toNativeUtf8();
    final keyPtr = secretKeyHex.toNativeUtf8();
    final relayPtr = relayUrl.toNativeUtf8();
    final discPtr = discoveryKey.toNativeUtf8();
    try {
      return _b.initWithIdentity(dbPtr, keyPtr, relayPtr, discPtr);
    } finally {
      calloc.free(dbPtr);
      calloc.free(keyPtr);
      calloc.free(relayPtr);
      calloc.free(discPtr);
    }
  }
  
  static bool setDataDir(String path) {
    final ptr = path.toNativeUtf8();
    try {
      return _b.setDataDir(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool setDiscoveryKey(String key) {
    final ptr = key.toNativeUtf8();
    try {
      return _b.setDiscoveryKey(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool isReady() => _b.isReady();
  
  // ==========================================================================
  // IDENTITY
  // ==========================================================================
  
  static String? getNodeId() {
    final ptr = _b.getNodeId();
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
  
  static String? getXaeroId() {
    final ptr = _b.getXaeroId();
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
  
  static bool setXaeroId(String id) {
    final ptr = id.toNativeUtf8();
    try {
      return _b.setXaeroId(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getMyNodeId() {
    final ptr = _b.getMyNodeId();
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
  
  static String? getMyProfile() {
    final ptr = _b.getMyProfile();
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
  
  static bool setMyProfile(Map<String, dynamic> profile) {
    final json = jsonEncode(profile);
    final ptr = json.toNativeUtf8();
    try {
      return _b.setMyProfile(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  // ==========================================================================
  // COMMAND/EVENT (ComponentActor pattern)
  // ==========================================================================
  
  /// Send command JSON to a component (queues to Rust VecDeque)
  static bool sendCommand(String component, String json) {
    final compPtr = component.toNativeUtf8();
    final jsonPtr = json.toNativeUtf8();
    try {
      return _b.sendCommand(compPtr, jsonPtr);
    } finally {
      calloc.free(compPtr);
      calloc.free(jsonPtr);
    }
  }
  
  /// Poll event JSON from a component (dequeues from Rust VecDeque)
  static String? pollEvents(String component) {
    final compPtr = component.toNativeUtf8();
    try {
      final ptr = _b.pollEvents(compPtr);
      if (ptr == nullptr) return null;
      return ptr.toDartStringAndFree();
    } finally {
      calloc.free(compPtr);
    }
  }
  
  static bool seedDemoIfEmpty() => _b.seedDemoIfEmpty();
  
  // ==========================================================================
  // STATS
  // ==========================================================================
  
  static int getObjectCount() => _b.getObjectCount();
  static int getTotalPeerCount() => _b.getTotalPeerCount();
  
  static int getGroupPeerCount(String groupId) {
    final ptr = groupId.toNativeUtf8();
    try {
      return _b.getGroupPeerCount(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  // ==========================================================================
  // GROUPS
  // ==========================================================================
  
  static void createGroup(String name, {String icon = 'folder.fill', String color = '#00AEEF'}) {
    final namePtr = name.toNativeUtf8();
    final iconPtr = icon.toNativeUtf8();
    final colorPtr = color.toNativeUtf8();
    try {
      _b.createGroup(namePtr, iconPtr, colorPtr);
    } finally {
      calloc.free(namePtr);
      calloc.free(iconPtr);
      calloc.free(colorPtr);
    }
  }
  
  static void renameGroup(String id, String name) {
    final idPtr = id.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      _b.renameGroup(idPtr, namePtr);
    } finally {
      calloc.free(idPtr);
      calloc.free(namePtr);
    }
  }
  
  static void deleteGroup(String id) {
    final ptr = id.toNativeUtf8();
    try {
      _b.deleteGroup(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static void leaveGroup(String id) {
    final ptr = id.toNativeUtf8();
    try {
      _b.leaveGroup(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool isGroupOwner(String id) {
    final ptr = id.toNativeUtf8();
    try {
      return _b.isGroupOwner(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  // ==========================================================================
  // WORKSPACES
  // ==========================================================================
  
  static void createWorkspace(String groupId, String name) {
    final gPtr = groupId.toNativeUtf8();
    final nPtr = name.toNativeUtf8();
    try {
      _b.createWorkspace(gPtr, nPtr);
    } finally {
      calloc.free(gPtr);
      calloc.free(nPtr);
    }
  }
  
  static void renameWorkspace(String id, String name) {
    final iPtr = id.toNativeUtf8();
    final nPtr = name.toNativeUtf8();
    try {
      _b.renameWorkspace(iPtr, nPtr);
    } finally {
      calloc.free(iPtr);
      calloc.free(nPtr);
    }
  }
  
  static void deleteWorkspace(String id) {
    final ptr = id.toNativeUtf8();
    try {
      _b.deleteWorkspace(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static void leaveWorkspace(String id) {
    final ptr = id.toNativeUtf8();
    try {
      _b.leaveWorkspace(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool isWorkspaceOwner(String id) {
    final ptr = id.toNativeUtf8();
    try {
      return _b.isWorkspaceOwner(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getWorkspacesForGroup(String groupId) {
    final ptr = groupId.toNativeUtf8();
    try {
      final result = _b.getWorkspacesForGroup(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  // ==========================================================================
  // BOARDS
  // ==========================================================================
  
  static void createBoard(String workspaceId, String name) {
    final wPtr = workspaceId.toNativeUtf8();
    final nPtr = name.toNativeUtf8();
    try {
      _b.createBoard(wPtr, nPtr);
    } finally {
      calloc.free(wPtr);
      calloc.free(nPtr);
    }
  }
  
  static void renameBoard(String id, String name) {
    final iPtr = id.toNativeUtf8();
    final nPtr = name.toNativeUtf8();
    try {
      _b.renameBoard(iPtr, nPtr);
    } finally {
      calloc.free(iPtr);
      calloc.free(nPtr);
    }
  }
  
  static void deleteBoard(String id) {
    final ptr = id.toNativeUtf8();
    try {
      _b.deleteBoard(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static void leaveBoard(String id) {
    final ptr = id.toNativeUtf8();
    try {
      _b.leaveBoard(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool isBoardOwner(String id) {
    final ptr = id.toNativeUtf8();
    try {
      return _b.isBoardOwner(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getAllBoards() {
    final ptr = _b.getAllBoards();
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
  
  static String? getBoardsForGroup(String groupId) {
    final gPtr = groupId.toNativeUtf8();
    try {
      final ptr = _b.getBoardsForGroup(gPtr);
      if (ptr == nullptr) return null;
      return ptr.toDartStringAndFree();
    } finally {
      calloc.free(gPtr);
    }
  }
  
  static String? getBoardsForWorkspace(String workspaceId) {
    final wPtr = workspaceId.toNativeUtf8();
    try {
      final ptr = _b.getBoardsForWorkspace(wPtr);
      if (ptr == nullptr) return null;
      return ptr.toDartStringAndFree();
    } finally {
      calloc.free(wPtr);
    }
  }
  
  static String? getBoardMode(String boardId) {
    final bPtr = boardId.toNativeUtf8();
    try {
      final ptr = _b.getBoardMode(bPtr);
      if (ptr == nullptr) return null;
      return ptr.toDartStringAndFree();
    } finally {
      calloc.free(bPtr);
    }
  }
  
  static bool setBoardMode(String boardId, String mode) {
    final bPtr = boardId.toNativeUtf8();
    final mPtr = mode.toNativeUtf8();
    try {
      return _b.setBoardMode(bPtr, mPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(mPtr);
    }
  }
  
  static bool isBoardPinned(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      return _b.isBoardPinned(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool pinBoard(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      return _b.pinBoard(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool unpinBoard(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      return _b.unpinBoard(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool rateBoard(String boardId, int rating) {
    final ptr = boardId.toNativeUtf8();
    try {
      return _b.rateBoard(ptr, rating);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool recordBoardView(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      return _b.recordBoardView(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  // ==========================================================================
  // BOARD METADATA
  // ==========================================================================
  
  static String? getBoardMetadata(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.getBoardMetadata(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getBoardsMetadata(List<String> boardIds) {
    final json = jsonEncode(boardIds);
    final ptr = json.toNativeUtf8();
    try {
      final result = _b.getBoardsMetadata(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getTopBoards(int limit) {
    final ptr = _b.getTopBoards(limit);
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
  
  static String? getBoardLink(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.getBoardLink(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? searchBoardsByLabel(String label) {
    final ptr = label.toNativeUtf8();
    try {
      final result = _b.searchBoardsByLabel(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool setBoardLabels(String boardId, List<String> labels) {
    final bPtr = boardId.toNativeUtf8();
    final lPtr = jsonEncode(labels).toNativeUtf8();
    try {
      return _b.setBoardLabels(bPtr, lPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(lPtr);
    }
  }
  
  static bool addBoardLabel(String boardId, String label) {
    final bPtr = boardId.toNativeUtf8();
    final lPtr = label.toNativeUtf8();
    try {
      return _b.addBoardLabel(bPtr, lPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(lPtr);
    }
  }
  
  static bool removeBoardLabel(String boardId, String label) {
    final bPtr = boardId.toNativeUtf8();
    final lPtr = label.toNativeUtf8();
    try {
      return _b.removeBoardLabel(bPtr, lPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(lPtr);
    }
  }
  
  static bool setBoardModel(String boardId, String model) {
    final bPtr = boardId.toNativeUtf8();
    final mPtr = model.toNativeUtf8();
    try {
      return _b.setBoardModel(bPtr, mPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(mPtr);
    }
  }
  
  static bool setBoardSkills(String boardId, List<String> skills) {
    final bPtr = boardId.toNativeUtf8();
    final sPtr = jsonEncode(skills).toNativeUtf8();
    try {
      return _b.setBoardSkills(bPtr, sPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(sPtr);
    }
  }
  
  // ==========================================================================
  // PEERS
  // ==========================================================================
  
  static String? getGroupPeers(String groupId) {
    final ptr = groupId.toNativeUtf8();
    try {
      final result = _b.getGroupPeers(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getAllPeers() {
    final ptr = _b.getAllPeers();
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
  
  static bool updatePeerStatus(String peerId, Map<String, dynamic> status) {
    final pPtr = peerId.toNativeUtf8();
    final sPtr = jsonEncode(status).toNativeUtf8();
    try {
      return _b.updatePeerStatus(pPtr, sPtr);
    } finally {
      calloc.free(pPtr);
      calloc.free(sPtr);
    }
  }
  
  // ==========================================================================
  // PROFILE
  // ==========================================================================
  
  static String? getUserProfile(String nodeId) {
    final ptr = nodeId.toNativeUtf8();
    try {
      final result = _b.getUserProfile(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getProfilesBatch(List<String> nodeIds) {
    final json = jsonEncode(nodeIds);
    final ptr = json.toNativeUtf8();
    try {
      final result = _b.getProfilesBatch(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  // ==========================================================================
  // CHAT
  // ==========================================================================
  
  static void sendChat(String workspaceId, String message, {String? parentId}) {
    final wPtr = workspaceId.toNativeUtf8();
    final mPtr = message.toNativeUtf8();
    final pPtr = parentId?.toNativeUtf8() ?? nullptr;
    try {
      _b.sendChat(wPtr, mPtr, pPtr);
    } finally {
      calloc.free(wPtr);
      calloc.free(mPtr);
      if (pPtr != nullptr) calloc.free(pPtr);
    }
  }
  
  static void deleteChat(String id) {
    final ptr = id.toNativeUtf8();
    try {
      _b.deleteChat(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool startDirectChat(String peerId, String workspaceId) {
    final pPtr = peerId.toNativeUtf8();
    final wPtr = workspaceId.toNativeUtf8();
    try {
      return _b.startDirectChat(pPtr, wPtr);
    } finally {
      calloc.free(pPtr);
      calloc.free(wPtr);
    }
  }
  
  static bool sendDirectChat(String peerId, String message) {
    final pPtr = peerId.toNativeUtf8();
    final mPtr = message.toNativeUtf8();
    try {
      return _b.sendDirectChat(pPtr, mPtr);
    } finally {
      calloc.free(pPtr);
      calloc.free(mPtr);
    }
  }
  
  // ==========================================================================
  // FILES
  // ==========================================================================
  
  static String? uploadFile(String path, Map<String, dynamic> scope) {
    final pPtr = path.toNativeUtf8();
    final sPtr = jsonEncode(scope).toNativeUtf8();
    try {
      final result = _b.uploadFile(pPtr, sPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(pPtr);
      calloc.free(sPtr);
    }
  }
  
  static String? uploadFileToGroup(String path, String groupId) {
    final pPtr = path.toNativeUtf8();
    final gPtr = groupId.toNativeUtf8();
    try {
      final result = _b.uploadFileToGroup(pPtr, gPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(pPtr);
      calloc.free(gPtr);
    }
  }
  
  static String? uploadFileToWorkspace(String path, String workspaceId) {
    final pPtr = path.toNativeUtf8();
    final wPtr = workspaceId.toNativeUtf8();
    try {
      final result = _b.uploadFileToWorkspace(pPtr, wPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(pPtr);
      calloc.free(wPtr);
    }
  }
  
  static bool requestFileDownload(String fileId) {
    final ptr = fileId.toNativeUtf8();
    try {
      return _b.requestFileDownload(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getFileStatus(String fileId) {
    final ptr = fileId.toNativeUtf8();
    try {
      final result = _b.getFileStatus(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getFiles(Map<String, dynamic> scope) {
    final ptr = jsonEncode(scope).toNativeUtf8();
    try {
      final result = _b.getFiles(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getFileLocalPath(String fileId) {
    final ptr = fileId.toNativeUtf8();
    try {
      final result = _b.getFileLocalPath(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  // ==========================================================================
  // WHITEBOARD
  // ==========================================================================
  
  static String? loadWhiteboardElements(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.loadWhiteboardElements(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool saveWhiteboardElement(String boardId, Map<String, dynamic> element) {
    final bPtr = boardId.toNativeUtf8();
    final ePtr = jsonEncode(element).toNativeUtf8();
    try {
      return _b.saveWhiteboardElement(bPtr, ePtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(ePtr);
    }
  }
  
  static bool deleteWhiteboardElement(String boardId, String elementId) {
    final bPtr = boardId.toNativeUtf8();
    final ePtr = elementId.toNativeUtf8();
    try {
      return _b.deleteWhiteboardElement(bPtr, ePtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(ePtr);
    }
  }
  
  static bool clearWhiteboard(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      return _b.clearWhiteboard(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static int getWhiteboardElementCount(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      return _b.getWhiteboardElementCount(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  // ==========================================================================
  // NOTEBOOK
  // ==========================================================================
  
  static String? loadNotebookCells(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.loadNotebookCells(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool saveNotebookCell(String boardId, Map<String, dynamic> cell) {
    final bPtr = boardId.toNativeUtf8();
    final cPtr = jsonEncode(cell).toNativeUtf8();
    try {
      return _b.saveNotebookCell(bPtr, cPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(cPtr);
    }
  }
  
  static bool deleteNotebookCell(String boardId, String cellId) {
    final bPtr = boardId.toNativeUtf8();
    final cPtr = cellId.toNativeUtf8();
    try {
      return _b.deleteNotebookCell(bPtr, cPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(cPtr);
    }
  }
  
  static bool reorderNotebookCells(String boardId, List<String> order) {
    final bPtr = boardId.toNativeUtf8();
    final oPtr = jsonEncode(order).toNativeUtf8();
    try {
      return _b.reorderNotebookCells(bPtr, oPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(oPtr);
    }
  }
  
  static String? loadCellElements(String cellId) {
    final ptr = cellId.toNativeUtf8();
    try {
      final result = _b.loadCellElements(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  // ==========================================================================
  // INTEGRATION
  // ==========================================================================
  
  static bool integrationCommand(Map<String, dynamic> command) {
    final ptr = jsonEncode(command).toNativeUtf8();
    try {
      return _b.integrationCommand(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? pollIntegrationEvents() {
    final ptr = _b.pollIntegrationEvents();
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
  
  static String? getConnectedIntegrations(String scopeId) {
    final ptr = scopeId.toNativeUtf8();
    try {
      final result = _b.getConnectedIntegrations(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? getIntegrationGraph(String scopeId) {
    final ptr = scopeId.toNativeUtf8();
    try {
      final result = _b.getIntegrationGraph(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  static bool setGraphFocus(String scopeId, Map<String, dynamic> focus) {
    final sPtr = scopeId.toNativeUtf8();
    final fPtr = jsonEncode(focus).toNativeUtf8();
    try {
      return _b.setGraphFocus(sPtr, fPtr);
    } finally {
      calloc.free(sPtr);
      calloc.free(fPtr);
    }
  }
  
  // ==========================================================================
  // AI
  // ==========================================================================
  
  static bool aiCommand(Map<String, dynamic> command) {
    final ptr = jsonEncode(command).toNativeUtf8();
    try {
      return _b.aiCommand(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  static String? pollAiResponse() {
    final ptr = _b.pollAiResponse();
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
  
  static String? pollAiInsights() {
    final ptr = _b.pollAiInsights();
    if (ptr == nullptr) return null;
    return ptr.toDartStringAndFree();
  }
}
