// ffi/ffi_helpers.dart
// Safe Dart wrappers for all FFI functions
// Handles memory allocation/deallocation, null checks, string conversion
//
// NOTE: Requires path_provider package in pubspec.yaml:
//   dependencies:
//     path_provider: ^2.1.0

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'cyan_bindings.dart';

// ============================================================================
// IN-MEMORY FALLBACK CACHE WITH FILE PERSISTENCE
// ============================================================================
import 'package:path_provider/path_provider.dart';

/// In-memory cache for notebook cells with file persistence
class _NotebookCache {
  static final Map<String, List<Map<String, dynamic>>> _cells = {};
  static final Map<String, String> _boardModes = {};
  static bool _initialized = false;
  static String? _cacheDir;
  
  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _cacheDir = '${dir.path}/cyan_cache';
      await Directory(_cacheDir!).create(recursive: true);
      await _loadFromDisk();
      _initialized = true;
    } catch (e) {
      debugPrint('_NotebookCache init error: $e');
      _initialized = true; // Mark as initialized even on error to avoid retries
    }
  }
  
  static Future<void> _loadFromDisk() async {
    if (_cacheDir == null) return;
    try {
      final cellsFile = File('$_cacheDir/cells.json');
      if (await cellsFile.exists()) {
        final content = await cellsFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        data.forEach((boardId, cells) {
          _cells[boardId] = (cells as List).cast<Map<String, dynamic>>();
        });
        debugPrint('_NotebookCache: Loaded ${_cells.length} boards from disk');
      }
      
      final modesFile = File('$_cacheDir/modes.json');
      if (await modesFile.exists()) {
        final content = await modesFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        data.forEach((boardId, mode) {
          _boardModes[boardId] = mode as String;
        });
      }
    } catch (e) {
      debugPrint('_NotebookCache load error: $e');
    }
  }
  
  static Future<void> _saveToDisk() async {
    if (_cacheDir == null) return;
    try {
      // Save cells
      final cellsFile = File('$_cacheDir/cells.json');
      await cellsFile.writeAsString(jsonEncode(_cells));
      
      // Save modes
      final modesFile = File('$_cacheDir/modes.json');
      await modesFile.writeAsString(jsonEncode(_boardModes));
      
      debugPrint('_NotebookCache: Saved to disk');
    } catch (e) {
      debugPrint('_NotebookCache save error: $e');
    }
  }
  
  static void saveCell(String boardId, Map<String, dynamic> cell) {
    _cells.putIfAbsent(boardId, () => []);
    final cellId = cell['id'] as String?;
    if (cellId != null) {
      final idx = _cells[boardId]!.indexWhere((c) => c['id'] == cellId);
      if (idx >= 0) {
        _cells[boardId]![idx] = Map<String, dynamic>.from(cell);
      } else {
        _cells[boardId]!.add(Map<String, dynamic>.from(cell));
      }
    }
    debugPrint('_NotebookCache: Saved cell for $boardId, total cells: ${_cells[boardId]!.length}');
    _saveToDisk(); // Persist immediately
  }
  
  static Future<List<Map<String, dynamic>>?> getCellsAsync(String boardId) async {
    await _ensureInitialized();
    return _cells[boardId];
  }
  
  static List<Map<String, dynamic>>? getCells(String boardId) {
    // Synchronous version - may miss data if not initialized
    return _cells[boardId];
  }
  
  static void deleteCell(String boardId, String cellId) {
    _cells[boardId]?.removeWhere((c) => c['id'] == cellId);
    _saveToDisk();
  }
  
  static void setBoardMode(String boardId, String mode) {
    _boardModes[boardId] = mode;
    _saveToDisk();
  }
  
  static Future<String?> getBoardModeAsync(String boardId) async {
    await _ensureInitialized();
    return _boardModes[boardId];
  }
  
  static String? getBoardMode(String boardId) {
    return _boardModes[boardId];
  }
  
  /// Initialize cache - call this early in app startup
  static Future<void> initialize() async {
    await _ensureInitialized();
  }
}

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
  // CACHE INITIALIZATION
  // ==========================================================================
  
  /// Initialize the notebook cache - call early in app startup
  static Future<void> initializeCache() async {
    await _NotebookCache.initialize();
  }
  
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
  
  /// Generate new XaeroID via FFI
  /// Returns JSON: {"secret_key":"hex","pubkey":"hex","did":"..."}
  static String? generateIdentityJson() {
    try {
      final ptr = _b.generateIdentityJson();
      if (ptr == nullptr) return null;
      return ptr.toDartStringAndFree();
    } catch (e) {
      debugPrint('⚠️ FFI generateIdentityJson not available: $e');
      return null;
    }
  }
  
  /// Derive pubkey and DID from secret key hex
  /// Returns JSON: {"pubkey":"hex","did":"..."}
  static String? deriveIdentity(String secretKeyHex) {
    try {
      final ptr = secretKeyHex.toNativeUtf8();
      try {
        final resultPtr = _b.deriveIdentity(ptr);
        if (resultPtr == nullptr) return null;
        return resultPtr.toDartStringAndFree();
      } finally {
        calloc.free(ptr);
      }
    } catch (e) {
      debugPrint('⚠️ FFI deriveIdentity not available: $e');
      return null;
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
  
  static bool setMyProfile(String displayName, {String? avatarPath}) {
    final namePtr = displayName.toNativeUtf8();
    final avatarPtr = (avatarPath ?? '').toNativeUtf8();
    try {
      return _b.setMyProfile(namePtr, avatarPtr);
    } finally {
      calloc.free(namePtr);
      calloc.free(avatarPtr);
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
  
  /// INERT in this engine — the command it queues is a no-op kept for ABI
  /// stability ("R10FB §D: demo seeding has been REMOVED"). The verb that
  /// really seeds is [seedDemo]. Void on the wire, so there is nothing to
  /// return and a bool here could only have been invented.
  static void seedDemoIfEmpty() => _b.seedDemoIfEmpty();
  
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
      if (ptr != nullptr) {
        final mode = ptr.toDartStringAndFree();
        if (mode.isNotEmpty) return mode;
      }
    } catch (e) {
      debugPrint('CyanFFI.getBoardMode FFI error: $e');
    } finally {
      calloc.free(bPtr);
    }
    
    // Fallback to in-memory cache
    return _NotebookCache.getBoardMode(boardId);
  }
  
  static bool setBoardMode(String boardId, String mode) {
    // Always save to in-memory cache
    _NotebookCache.setBoardMode(boardId, mode);
    
    final bPtr = boardId.toNativeUtf8();
    final mPtr = mode.toNativeUtf8();
    try {
      return _b.setBoardMode(bPtr, mPtr);
    } catch (e) {
      debugPrint('CyanFFI.setBoardMode FFI error: $e');
      return true; // Return true since we saved to cache
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

  /// Set the pin flag in ONE verb. Void on the wire — the engine queues a
  /// SetPin command and acknowledges nothing, so the caller re-reads the board.
  static void pinSet(String boardId, bool pinned) {
    final ptr = boardId.toNativeUtf8();
    try {
      _b.pinSet(ptr, pinned);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Promote a markdown summary into a board of its own: the engine mints the
  /// board in [workspaceId] and drops [markdownContent] in as its opening cell.
  /// Returns the engine's deterministic board id.
  static String? pinSummaryAsBoard(
      String workspaceId, String boardName, String markdownContent) {
    final wsPtr = workspaceId.toNativeUtf8();
    final namePtr = boardName.toNativeUtf8();
    final contentPtr = markdownContent.toNativeUtf8();
    try {
      final result = _b.pinSummaryAsBoard(wsPtr, namePtr, contentPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(wsPtr);
      calloc.free(namePtr);
      calloc.free(contentPtr);
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
  
  /// Board metadata for a SCOPE — `scopeType` is the engine's own vocabulary
  /// (`workspace` / `group` / …) and `scopeId` the id under it. It has never
  /// taken a list of board ids; the old wrapper sent it one and the engine read
  /// the JSON array as a scope kind that matches nothing.
  static String? getBoardsMetadata(String scopeType, String scopeId) {
    final tPtr = scopeType.toNativeUtf8();
    final iPtr = scopeId.toNativeUtf8();
    try {
      final result = _b.getBoardsMetadata(tPtr, iPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(tPtr);
      calloc.free(iPtr);
    }
  }

  /// The group's top boards. The GROUP is the first argument — the old wrapper
  /// passed the limit into that slot, and the engine dereferenced the integer
  /// as a string pointer.
  static String? getTopBoards(String groupId, int limit) {
    final gPtr = groupId.toNativeUtf8();
    try {
      final ptr = _b.getTopBoards(gPtr, limit);
      if (ptr == nullptr) return null;
      return ptr.toDartStringAndFree();
    } finally {
      calloc.free(gPtr);
    }
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
  
  /// Send a message to a BOARD's chat. The parameter used to be called
  /// `workspaceId` — a leftover from before R11 §1 made chat board-scoped. The
  /// engine's `cyan_send_chat` takes a board id and always has here; only the
  /// name was stale, which is the kind of thing that gets a workspace id passed
  /// in eventually.
  static void sendChat(String boardId, String message, {String? parentId}) {
    final bPtr = boardId.toNativeUtf8();
    final mPtr = message.toNativeUtf8();
    final pPtr = parentId?.toNativeUtf8() ?? nullptr;
    try {
      _b.sendChat(bPtr, mPtr, pPtr);
    } finally {
      calloc.free(bPtr);
      calloc.free(mPtr);
      if (pPtr != nullptr) calloc.free(pPtr);
    }
  }
  
  /// Replay a BOARD's stored chat onto the chat-panel event buffer. Void on the
  /// wire — the engine queues the replay and answers with `ChatSent` frames
  /// followed by `ChatHistoryComplete`, so the caller drains `pollEvents`
  /// rather than waiting on a return value.
  static void loadChatHistory(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      _b.loadChatHistory(ptr);
    } finally {
      calloc.free(ptr);
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

  // ==========================================================================
  // UNREAD / NOTIFICATIONS
  // ==========================================================================

  /// Unread counts as a JSON object `{board_id: count}` — BOARD-level only, no
  /// workspace/group rollup. Sum the map for the dock badge total.
  static String? unreadCounts() {
    final result = _b.unreadCounts();
    if (result == nullptr) return null;
    return result.toDartStringAndFree();
  }

  /// Mark a board read. [scopeId] is a board id; void on the wire because the
  /// engine clears the board's unread items and emits `UnreadChanged` rather
  /// than answering a receipt.
  static void markRead(String scopeId) {
    final ptr = scopeId.toNativeUtf8();
    try {
      _b.markRead(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  /// Open a direct-chat stream with a peer. Void on the wire — the engine
  /// queues the command and answers with a `ChatStreamReady` event, not a
  /// return value.
  static void startDirectChat(String peerId, String workspaceId) {
    final pPtr = peerId.toNativeUtf8();
    final wPtr = workspaceId.toNativeUtf8();
    try {
      _b.startDirectChat(pPtr, wPtr);
    } finally {
      calloc.free(pPtr);
      calloc.free(wPtr);
    }
  }
  
  /// A direct message to a peer, in a WORKSPACE — the engine files the DM under
  /// one, so there is no peer-only send. Void on the wire (it queues a command),
  /// which is why nothing is returned: a bool here could only be invented.
  /// [parentId] threads the message under an existing one.
  static void sendDirectChat(String peerId, String workspaceId, String message,
      {String? parentId}) {
    final pPtr = peerId.toNativeUtf8();
    final wPtr = workspaceId.toNativeUtf8();
    final mPtr = message.toNativeUtf8();
    final parentPtr = (parentId ?? '').toNativeUtf8();
    try {
      _b.sendDirectChat(pPtr, wPtr, mPtr, parentPtr);
    } finally {
      calloc.free(pPtr);
      calloc.free(wPtr);
      calloc.free(mPtr);
      calloc.free(parentPtr);
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
  
  /// Upload a local file into a GROUP. Void on the wire: the engine queues the
  /// upload and the file appears through the tree/file events, so there is no
  /// id to hand back. The old wrapper read a `Pointer<Utf8>` out of a function
  /// that returns nothing, then dereferenced and freed it — and passed the
  /// arguments in the opposite order to the one the engine declares.
  static void uploadFileToGroup(String path, String groupId) {
    final gPtr = groupId.toNativeUtf8();
    final pPtr = path.toNativeUtf8();
    try {
      _b.uploadFileToGroup(gPtr, pPtr);
    } finally {
      calloc.free(gPtr);
      calloc.free(pPtr);
    }
  }

  /// Upload a local file into a WORKSPACE. Same shape as [uploadFileToGroup].
  static void uploadFileToWorkspace(String path, String workspaceId) {
    final wPtr = workspaceId.toNativeUtf8();
    final pPtr = path.toNativeUtf8();
    try {
      _b.uploadFileToWorkspace(wPtr, pPtr);
    } finally {
      calloc.free(wPtr);
      calloc.free(pPtr);
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

  /// User-initiated file delete. Void on the wire: the engine soft-deletes and
  /// gossips the tombstone, so the caller re-reads rather than waiting.
  static void deleteFile(String fileId) {
    final ptr = fileId.toNativeUtf8();
    try {
      _b.deleteFile(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Resolve a file by its stable workflow handle
  /// `group_id:workspace_id:board_id:file_name`. Returns the FileDTO as JSON,
  /// or null when no ACTIVE file matches (a tombstoned one never does).
  static String? resolveFileHandle(
      String groupId, String workspaceId, String boardId, String fileName) {
    final gPtr = groupId.toNativeUtf8();
    final wPtr = workspaceId.toNativeUtf8();
    final bPtr = boardId.toNativeUtf8();
    final nPtr = fileName.toNativeUtf8();
    try {
      final result = _b.resolveFileHandle(gPtr, wPtr, bPtr, nPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(gPtr);
      calloc.free(wPtr);
      calloc.free(bPtr);
      calloc.free(nPtr);
    }
  }

  /// Extract text from the file at [path] (PDF, TXT, MD, CSV, JSON, code). The
  /// ENGINE truncates to its own token budget; null means it could not read the
  /// file, never an empty document.
  static String? extractFileText(String path) {
    final ptr = path.toNativeUtf8();
    try {
      final result = _b.extractFileText(ptr);
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
  
  /// The board id travels INSIDE the element JSON — the engine refuses a
  /// payload whose `board_id` is empty, so the wrapper stamps its own argument
  /// in rather than trusting every caller to remember it.
  static bool saveWhiteboardElement(String boardId, Map<String, dynamic> element) {
    final ePtr = jsonEncode(_withBoardId(boardId, element)).toNativeUtf8();
    try {
      return _b.saveWhiteboardElement(ePtr);
    } finally {
      calloc.free(ePtr);
    }
  }

  static bool deleteWhiteboardElement(String boardId, String elementId) {
    final ePtr = elementId.toNativeUtf8();
    try {
      return _b.deleteWhiteboardElement(ePtr);
    } finally {
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
      if (result != nullptr) {
        final json = result.toDartStringAndFree();
        if (json.isNotEmpty && json != '[]') {
          debugPrint('CyanFFI.loadNotebookCells: FFI returned $json');
          return json;
        }
      }
    } catch (e) {
      debugPrint('CyanFFI.loadNotebookCells FFI error: $e');
    } finally {
      calloc.free(ptr);
    }
    
    // Fallback to in-memory cache
    final cached = _NotebookCache.getCells(boardId);
    if (cached != null && cached.isNotEmpty) {
      debugPrint('CyanFFI.loadNotebookCells: Using cached data for $boardId');
      return jsonEncode(cached);
    }
    
    return null;
  }
  
  /// The board id travels INSIDE the cell JSON — the verb takes the cell alone,
  /// and the engine refuses a payload whose `board_id` is empty. Stamping the
  /// wrapper's own argument in is what lets callers that only ever passed it
  /// positionally (board_detail_view's `_saveCell`) keep working.
  static bool saveNotebookCell(String boardId, Map<String, dynamic> cell) {
    // Always save to in-memory cache first
    _NotebookCache.saveCell(boardId, cell);

    final cPtr = jsonEncode(_withBoardId(boardId, cell)).toNativeUtf8();
    try {
      final result = _b.saveNotebookCell(cPtr);
      debugPrint('CyanFFI.saveNotebookCell: FFI result=$result for $boardId');
      return result;
    } catch (e) {
      // NOT true. The cache is a read fallback, not a write: reporting a save
      // the engine never made is how an author face looks like it works and
      // loses the operator's writes on the next launch.
      debugPrint('CyanFFI.saveNotebookCell FFI error: $e');
      return false;
    } finally {
      calloc.free(cPtr);
    }
  }

  static bool deleteNotebookCell(String boardId, String cellId) {
    // Delete from in-memory cache
    _NotebookCache.deleteCell(boardId, cellId);

    final cPtr = cellId.toNativeUtf8();
    try {
      return _b.deleteNotebookCell(cPtr);
    } catch (e) {
      debugPrint('CyanFFI.deleteNotebookCell FFI error: $e');
      return false; // same reason as the save above
    } finally {
      calloc.free(cPtr);
    }
  }

  /// A payload with its `board_id` filled in from [boardId] when the caller did
  /// not carry one. Never overwrites a board id the caller DID set — a cell
  /// that names its own board is the authority, and silently re-homing it would
  /// move the operator's work.
  static Map<String, dynamic> _withBoardId(
      String boardId, Map<String, dynamic> payload) {
    final existing = payload['board_id'];
    if (existing is String && existing.isNotEmpty) return payload;
    return {...payload, 'board_id': boardId};
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
  
  // INTEGRATION — deleted, not stubbed.
  //
  // Integrations moved to MCP servers in cyan-backend/Lens; the client owns no
  // integration logic. The engine dropped the cyan_integration_* symbols and iOS
  // deleted its declarations in the same change. These five wrappers were the
  // last references to them, called by nothing, and they kept five dead lookups
  // alive in the binder — which threw inside _bindAllUnsafe and no-opped all 155
  // verbs. "Delete, don't abstract", exactly as the iOS removal plan said.

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
  
  // ==========================================================================
  // PIPELINE
  // ==========================================================================
  
  /// Kick a background compile of the board's authored steps.
  /// Returns JSON: {"status":"compiling","board_id":"...","message":"..."}
  static String? pipelineCompile(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.pipelineCompile(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  /// Kick a background run of the compiled DAG.
  /// Returns JSON: {"status":"started","board_id":"...","message":"..."}
  static String? runPipeline(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.runPipeline(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  /// The persisted single-run snapshot: run_id, derived status, per-step state
  /// + cost, the awaiting-approval step. Pure read.
  static String? pipelineStatus(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.pipelineStatus(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }
  
  /// AUTOPILOT (design §1) — set a board's mode (`off` | `assist` |
  /// `autopilot`). Returns the engine's JSON envelope; both verbs answer
  /// `{"success":…,"mode":"…"}` rather than a bare bool, so the caller can tell
  /// a refusal from a mode.
  static String? autopilotSet(String boardId, String mode) {
    final boardPtr = boardId.toNativeUtf8();
    final modePtr = mode.toNativeUtf8();
    try {
      final result = _b.autopilotSet(boardPtr, modePtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(boardPtr);
      calloc.free(modePtr);
    }
  }

  /// AUTOPILOT — read a board's mode. The engine defaults to `off`.
  static String? autopilotGet(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.autopilotGet(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  static bool pipelineApprove(String boardId, String stepId) {
    final boardPtr = boardId.toNativeUtf8();
    final stepPtr = stepId.toNativeUtf8();
    try {
      return _b.pipelineApprove(boardPtr, stepPtr);
    } finally {
      calloc.free(boardPtr);
      calloc.free(stepPtr);
    }
  }
  
  /// Approve AS a named reviewer. A review_hold step clears ONLY when the
  /// reviewer matches its `waiting_on` user.
  /// Returns JSON: {"success":true} | {"success":false,"error":"..."}
  static String? pipelineApproveAs(String boardId, String stepId, String reviewer) {
    final boardPtr = boardId.toNativeUtf8();
    final stepPtr = stepId.toNativeUtf8();
    final reviewerPtr = reviewer.toNativeUtf8();
    try {
      final result = _b.pipelineApproveAs(boardPtr, stepPtr, reviewerPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(boardPtr);
      calloc.free(stepPtr);
      calloc.free(reviewerPtr);
    }
  }
  
  static bool pipelineReject(String boardId, String stepId) {
    final boardPtr = boardId.toNativeUtf8();
    final stepPtr = stepId.toNativeUtf8();
    try {
      return _b.pipelineReject(boardPtr, stepPtr);
    } finally {
      calloc.free(boardPtr);
      calloc.free(stepPtr);
    }
  }
  
  /// Reject AS a named reviewer — the review-hold twin of [pipelineApproveAs].
  /// Returns JSON: {"success":true} | {"success":false,"error":"..."}
  static String? pipelineRejectAs(String boardId, String stepId, String reviewer) {
    final boardPtr = boardId.toNativeUtf8();
    final stepPtr = stepId.toNativeUtf8();
    final reviewerPtr = reviewer.toNativeUtf8();
    try {
      final result = _b.pipelineRejectAs(boardPtr, stepPtr, reviewerPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(boardPtr);
      calloc.free(stepPtr);
      calloc.free(reviewerPtr);
    }
  }
  
  /// Retry a step (reset to pending, preserve metadata).
  static bool pipelineRetry(String boardId, String stepId) {
    final boardPtr = boardId.toNativeUtf8();
    final stepPtr = stepId.toNativeUtf8();
    try {
      return _b.pipelineRetry(boardPtr, stepPtr);
    } finally {
      calloc.free(boardPtr);
      calloc.free(stepPtr);
    }
  }
  
  /// Reset every step on the board back to pending.
  static bool pipelineReset(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      return _b.pipelineReset(ptr);
    } finally {
      calloc.free(ptr);
    }
  }
  
  /// Reset ONE step back to pending.
  static bool pipelineResetStep(String boardId, String stepId) {
    final boardPtr = boardId.toNativeUtf8();
    final stepPtr = stepId.toNativeUtf8();
    try {
      return _b.pipelineResetStep(boardPtr, stepPtr);
    } finally {
      calloc.free(boardPtr);
      calloc.free(stepPtr);
    }
  }
  
  /// Dispatch ONE step against its locally-bound plugin (no DAG walk).
  /// Returns JSON: {"success":true,"summary":"...","findings":N} |
  /// {"success":false,"gated":bool,"error":"...","parked":bool,"awaiting":"..."}
  static String? pipelineRunStepLocal(String boardId, String stepId) {
    final boardPtr = boardId.toNativeUtf8();
    final stepPtr = stepId.toNativeUtf8();
    try {
      final result = _b.pipelineRunStepLocal(boardPtr, stepPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(boardPtr);
      calloc.free(stepPtr);
    }
  }
  
  /// Walk a step cell's edit history. `direction` is the engine's int:
  /// 0 = undo, anything else = redo.
  /// Returns JSON: {"content":"...","undo_depth":N,"redo_depth":N} |
  /// {"error":"..."}
  static String? stepEditTravel(String boardId, String cellId, int direction) {
    final boardPtr = boardId.toNativeUtf8();
    final cellPtr = cellId.toNativeUtf8();
    try {
      final result = _b.stepEditTravel(boardPtr, cellPtr, direction);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(boardPtr);
      calloc.free(cellPtr);
    }
  }
  
  /// The board's deploy state row.
  /// Returns JSON: {"board_id":"...","deployed":bool,"dashboard_available":bool,
  /// "locked":bool,"updated_at":N}
  static String? boardWorkflowState(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.boardWorkflowState(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  // ---- identity + device prefs ---------------------------------------------

  /// The commit the loaded engine was built from. A STATIC string owned by the
  /// engine — read, never freed.
  static String? buildCommit() {
    final result = _b.buildCommit();
    if (result == nullptr) return null;
    return result.toDartString();
  }

  /// Wipe this device's identity from the vault. Destructive and final.
  static bool deleteIdentity() => _b.deleteIdentity();

  /// The device's craft-role pref, or "" when unset. Device-LOCAL, never synced.
  static String? getProductionRole() {
    final result = _b.getProductionRole();
    if (result == nullptr) return null;
    return result.toDartStringAndFree();
  }

  /// Set the craft-role pref. The empty string CLEARS it; a role outside the
  /// engine's vocabulary is REFUSED and the pref is left untouched.
  static bool setProductionRole(String role) {
    final ptr = role.toNativeUtf8();
    try {
      return _b.setProductionRole(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Resolve a {tenant, role, format} selector. A refusal answers with the
  /// vocabulary it WOULD have accepted:
  /// {"error":"unknown_role","given":"…","allowed":[…]}
  static String? selectorResolve(String tenantId, String role, String formatType) {
    final tenantPtr = tenantId.toNativeUtf8();
    final rolePtr = role.toNativeUtf8();
    final formatPtr = formatType.toNativeUtf8();
    try {
      final result = _b.selectorResolve(tenantPtr, rolePtr, formatPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(tenantPtr);
      calloc.free(rolePtr);
      calloc.free(formatPtr);
    }
  }

  /// The engine's display fallback for a raw node id — "User-A3F2". An id too
  /// short to abbreviate comes back unchanged.
  static String? friendlyNodeId(String nodeId) {
    final ptr = nodeId.toNativeUtf8();
    try {
      final result = _b.friendlyNodeId(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  // ---- SSO session grants ----------------------------------------------------

  /// Install a broker-minted session grant, verified against `trustJson`:
  /// {"tenant":"…","org_did":…|null,"legacy_rsa_public_pem":…|null,
  /// "grace_secs":N}
  /// Returns JSON: {"active":true,"tenant":"…","role":"…","exp":N} |
  /// {"active":false,"reason":"…"} — a refusal leaves any installed session
  /// UNTOUCHED.
  static String? ssoInstallGrant(String grantToken, String trustJson) {
    final tokenPtr = grantToken.toNativeUtf8();
    final trustPtr = trustJson.toNativeUtf8();
    try {
      final result = _b.ssoInstallGrant(tokenPtr, trustPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(tokenPtr);
      calloc.free(trustPtr);
    }
  }

  /// Clear the installed session — RBAC returns to its no-session default.
  static void ssoSignOut() => _b.ssoSignOut();

  // ---- anonymous sessions ---------------------------------------------------

  /// Mint an ephemeral session for one scope. The ENGINE mints the handle.
  /// Returns JSON: {"ephemeral_key":"…","handle":"…","scope_id":"…",…}
  static String? createAnonymousSession(String scopeId) {
    final ptr = scopeId.toNativeUtf8();
    try {
      final result = _b.createAnonymousSession(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Bind the handle back to this device's real identity. ONE WAY — a session
  /// already revealed answers null.
  static String? revealAnonymousIdentity(String scopeId) {
    final ptr = scopeId.toNativeUtf8();
    try {
      final result = _b.revealAnonymousIdentity(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Returns JSON: {"anonymous":bool,"handle":"…"|null,"revealed":bool}
  static String? getAnonymousStatus(String scopeId) {
    final ptr = scopeId.toNativeUtf8();
    try {
      final result = _b.getAnonymousStatus(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Drop the scope's session — this device is visible there again.
  static bool exitAnonymousMode(String scopeId) {
    final ptr = scopeId.toNativeUtf8();
    try {
      return _b.exitAnonymousMode(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  // ---- groups: roster, grants, portable bundles ------------------------------

  /// The group's PERSISTENT roster with a live-online overlay.
  /// Returns JSON: [{"peer_id":"…","name":…,"avatar":…,"online":bool,
  /// "last_seen":N},…]
  static String? getGroupMembers(String groupId) {
    final ptr = groupId.toNativeUtf8();
    try {
      final result = _b.getGroupMembers(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Mint a signed capability grant. `ttlSeconds` of 0 takes the engine's own
  /// default (24h). Only the group Owner/Admin may issue one.
  /// Returns JSON: {"success":true,"qr":"…","nonce":"…","expiry":N,"role":"…"}
  /// | {"success":false,"error":"…"}
  static String? issueGrantQr(String groupId, String role, int ttlSeconds) {
    final groupPtr = groupId.toNativeUtf8();
    final rolePtr = role.toNativeUtf8();
    try {
      final result = _b.issueGrantQr(groupPtr, rolePtr, ttlSeconds);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(groupPtr);
      calloc.free(rolePtr);
    }
  }

  /// Verify a grant QR and JOIN the group it grants.
  /// Returns JSON: {"success":true,"group_id":"…","group_name":"…"} |
  /// {"success":false,"error":"Grant rejected: …"}
  static String? scanGrantQr(String qrPayload) {
    final ptr = qrPayload.toNativeUtf8();
    try {
      final result = _b.scanGrantQr(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// This device's X25519 bundle public key — the recipient key an inviter
  /// seals a `.cyangroup` export to.
  static String? bundlePubkey() {
    final result = _b.bundlePubkey();
    if (result == nullptr) return null;
    return result.toDartStringAndFree();
  }

  /// Seal a portable group bundle TO one recipient key.
  /// Returns JSON: {"success":true,"group_id":"…","bundle":"…","path":"…"} |
  /// {"success":false,"error":"…"}
  static String? exportGroup(String groupId, String inviteePubkey) {
    final groupPtr = groupId.toNativeUtf8();
    final pubkeyPtr = inviteePubkey.toNativeUtf8();
    try {
      final result = _b.exportGroup(groupPtr, pubkeyPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(groupPtr);
      calloc.free(pubkeyPtr);
    }
  }

  /// Verify + decrypt a `.cyangroup` bundle and seed it into storage.
  /// Returns JSON: {"success":true,"group_id":"…"} |
  /// {"success":false,"error":"…"}
  static String? importGroup(String bundle) {
    final ptr = bundle.toNativeUtf8();
    try {
      final result = _b.importGroup(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  // ---- board notes: the unscoped CRUD the review rail writes through --------

  /// List a board's notes as a JSON array of NoteDTO. The ENGINE derives the
  /// tenant from the board's group, so a read finds what a write put there.
  static String? noteList(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.noteList(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Write a note on a board. A null [noteId] mints a new note and a null
  /// [tenantId] lets the ENGINE derive the tenant from the board's group — both
  /// are passed as null pointers when omitted, which is what the engine reads
  /// as "not given".
  static void notePut(
    String boardId,
    String text, {
    String? noteId,
    String? tenantId,
  }) {
    final boardPtr = boardId.toNativeUtf8();
    final notePtr = noteId == null ? nullptr : noteId.toNativeUtf8();
    final tenantPtr = tenantId == null ? nullptr : tenantId.toNativeUtf8();
    final textPtr = text.toNativeUtf8();
    try {
      _b.notePut(boardPtr, notePtr, tenantPtr, textPtr);
    } finally {
      calloc.free(boardPtr);
      if (notePtr != nullptr) calloc.free(notePtr);
      if (tenantPtr != nullptr) calloc.free(tenantPtr);
      calloc.free(textPtr);
    }
  }

  /// Delete a note by id. Void on the wire — the engine queues the delete and
  /// acknowledges nothing, so the caller re-reads the list.
  static void noteDelete(String id) {
    final ptr = id.toNativeUtf8();
    try {
      _b.noteDelete(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  // ---- timecoded notes: the review rail's own store -------------------------

  /// Save a timecoded note. The WHOLE note travels as JSON; the engine parses
  /// it into its `TimecodeNote` and persists it as a notebook cell, so a bad
  /// shape comes back as `false` rather than a partial write.
  static bool saveTimecodeNote(String noteJson) {
    final ptr = noteJson.toNativeUtf8();
    try {
      return _b.saveTimecodeNote(ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  /// A board's timecoded notes as a JSON array of TimecodeNote, engine-ordered
  /// by timecode. Returns {"error":"…"} when the notes store is busy.
  static String? loadTimecodeNotes(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.loadTimecodeNotes(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Send a timecoded note to the engine's AI rail and get its answer back.
  /// The engine re-saves the note with the result attached, so the caller
  /// re-reads the list rather than patching its own copy.
  /// Returns JSON: {"success":true,"result":"…"} | {"error":"…"}
  static String? actOnTimecodeNote(String noteJson) {
    final ptr = noteJson.toNativeUtf8();
    try {
      final result = _b.actOnTimecodeNote(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// The same rail as a markdown timeline: the board's threads grouped by
  /// pipeline step, each root note with its AI result and its replies under it.
  /// Raw MARKDOWN on the wire, not JSON. Null when the notes store could not be
  /// read.
  static String? exportNotesMarkdown(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.exportNotesMarkdown(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  // ---- scoped notes + the constitution chain they feed ----------------------

  /// List an anchor's notes in ONE scope. An empty [kind] reads EVERY kind —
  /// the engine takes a null pointer for that, so it is passed as one.
  /// Returns a JSON array of NoteDTO, or {"error":"…"}.
  static String? noteListScoped(String boardId, String scope, {String kind = ''}) {
    final boardPtr = boardId.toNativeUtf8();
    final scopePtr = scope.toNativeUtf8();
    final kindPtr = kind.isEmpty ? nullptr : kind.toNativeUtf8();
    try {
      final result = _b.noteListScoped(boardPtr, scopePtr, kindPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(boardPtr);
      calloc.free(scopePtr);
      if (kindPtr != nullptr) calloc.free(kindPtr);
    }
  }

  /// Write a note at one scope. A null [noteId] mints a new note and a null
  /// [tenantId] lets the ENGINE derive the tenant from the anchor's group, so
  /// reads match writes — both are passed as null pointers when omitted.
  static void notePutScoped(
    String boardId,
    String text, {
    String? noteId,
    String? tenantId,
    String scope = 'board',
    String kind = 'editor-note',
  }) {
    final boardPtr = boardId.toNativeUtf8();
    final notePtr = noteId == null ? nullptr : noteId.toNativeUtf8();
    final tenantPtr = tenantId == null ? nullptr : tenantId.toNativeUtf8();
    final textPtr = text.toNativeUtf8();
    final scopePtr = scope.toNativeUtf8();
    final kindPtr = kind.toNativeUtf8();
    try {
      _b.notePutScoped(
          boardPtr, notePtr, tenantPtr, textPtr, scopePtr, kindPtr);
    } finally {
      calloc.free(boardPtr);
      if (notePtr != nullptr) calloc.free(notePtr);
      if (tenantPtr != nullptr) calloc.free(tenantPtr);
      calloc.free(textPtr);
      calloc.free(scopePtr);
      calloc.free(kindPtr);
    }
  }

  /// The on-device PREVIEW resolve. Takes a JSON request — the user scope is
  /// included here because the caller IS the device owner.
  /// Returns JSON: {"markdown","preferences","hash","contributing":[…]} |
  /// {"error":"…"}
  static String? constitutionResolved(String requestJson) {
    final ptr = requestJson.toNativeUtf8();
    try {
      final result = _b.constitutionResolved(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// The cloud-bound read, with the HARD rules classified off the same chain.
  /// Returns JSON: {"markdown","hash","contributing_ids":[…],"hard":[…]} |
  /// {"error":"…"}
  static String? constitutionEffective(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.constitutionEffective(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  // ---- templates + the workflows cloned from them ---------------------------

  /// The templates visible to a tenant: the built-in seeds (always) plus the
  /// tenant's own save-as-template results. An empty [tenantId] is the engine's
  /// null — seeds only — so it is passed as a null pointer.
  /// Returns a JSON array of Template.
  static String? templateList({String tenantId = ''}) {
    final ptr = tenantId.isEmpty ? nullptr : tenantId.toNativeUtf8();
    try {
      final result = _b.templateList(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      if (ptr != nullptr) calloc.free(ptr);
    }
  }

  /// Clone a template into a board as real authorable step cells. FIRE-AND-
  /// FORGET (it queues a command), so the caller polls [templateCloneOutcome]
  /// for what the clone produced. An empty [tenantId] lets the ENGINE derive
  /// the tenant from the board's group, so it is passed as a null pointer.
  static void workflowFromTemplate(String templateId, String boardId,
      {String tenantId = ''}) {
    final templatePtr = templateId.toNativeUtf8();
    final boardPtr = boardId.toNativeUtf8();
    final tenantPtr = tenantId.isEmpty ? nullptr : tenantId.toNativeUtf8();
    try {
      _b.workflowFromTemplate(templatePtr, boardPtr, tenantPtr);
    } finally {
      calloc.free(templatePtr);
      calloc.free(boardPtr);
      if (tenantPtr != nullptr) calloc.free(tenantPtr);
    }
  }

  /// The board's LAST clone outcome, or null when no clone has finished for it
  /// since launch — null is the engine's own answer here, not a failure.
  /// Returns JSON: {"template_id","board_id","tenant_id","steps",
  /// "plugin_installs":[…]}
  static String? templateCloneOutcome(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.templateCloneOutcome(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Save steps as a reusable user template, tenant-scoped. [stepsJson] is a
  /// JSON array of TemplateStep. Returns the created Template as JSON, or null
  /// on bad input — this verb has no error channel.
  static String? templateSave(
      String tenantId, String name, String description, String stepsJson) {
    final tenantPtr = tenantId.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    final descPtr = description.toNativeUtf8();
    final stepsPtr = stepsJson.toNativeUtf8();
    try {
      final result = _b.templateSave(tenantPtr, namePtr, descPtr, stepsPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(tenantPtr);
      calloc.free(namePtr);
      calloc.free(descPtr);
      calloc.free(stepsPtr);
    }
  }

  /// The same save FROM a board, so the board's STANDING notes travel with the
  /// template. Returns the created Template as JSON, or null on bad input.
  static String? templateSaveFromBoard(String tenantId, String name,
      String description, String stepsJson, String boardId) {
    final tenantPtr = tenantId.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    final descPtr = description.toNativeUtf8();
    final stepsPtr = stepsJson.toNativeUtf8();
    final boardPtr = boardId.toNativeUtf8();
    try {
      final result = _b.templateSaveFromBoard(
          tenantPtr, namePtr, descPtr, stepsPtr, boardPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(tenantPtr);
      calloc.free(namePtr);
      calloc.free(descPtr);
      calloc.free(stepsPtr);
      calloc.free(boardPtr);
    }
  }

  /// The roletype (v2) template save. ANY violation rejects the WHOLE save
  /// with an error envelope — never null, deliberately unlike the v1 verb.
  /// Returns JSON: the created Template | {"error","given","allowed":[…]}
  static String? templateSaveV2(String tenantId, String templateJson) {
    final tenantPtr = tenantId.toNativeUtf8();
    final bodyPtr = templateJson.toNativeUtf8();
    try {
      final result = _b.templateSaveV2(tenantPtr, bodyPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(tenantPtr);
      calloc.free(bodyPtr);
    }
  }

  /// The step composer's tenant-scoped autocomplete index, filtered by the
  /// trailing `@`/`#`/`/` trigger in [partial]. No active trigger returns the
  /// full index.
  /// Returns JSON: {"tenant_id","plugins":[…],"artifacts":[…],"actions":[…]}
  static String? workflowAutocomplete(String boardId, String partial) {
    final boardPtr = boardId.toNativeUtf8();
    final partialPtr = partial.toNativeUtf8();
    try {
      final result = _b.workflowAutocomplete(boardPtr, partialPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(boardPtr);
      calloc.free(partialPtr);
    }
  }

  // ---- producer review: assignee, board media, comments ---------------------

  /// The REAL user this board's review gates wait on, as a BARE string — the
  /// engine stamps it into review-hold steps as `waiting_on`. Empty when unset,
  /// which is a real answer (no assignee), not a failure.
  static String? boardReviewAssignee(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.boardReviewAssignee(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Set the board's review assignee. False when the engine refused the write —
  /// it is never a partial one.
  static bool boardSetReviewAssignee(String boardId, String user) {
    final boardPtr = boardId.toNativeUtf8();
    final userPtr = user.toNativeUtf8();
    try {
      return _b.boardSetReviewAssignee(boardPtr, userPtr);
    } finally {
      calloc.free(boardPtr);
      calloc.free(userPtr);
    }
  }

  /// The board's playable video, resolved through the SAME rails the cyan-media
  /// tools use, so the player and the tool inputs can never disagree.
  /// Returns JSON: {"proxy_path","master_uri","preview_path","media_root"} —
  /// with "busy":true instead when the store is under contention.
  static String? boardVideoMedia(String boardId) {
    final ptr = boardId.toNativeUtf8();
    try {
      final result = _b.boardVideoMedia(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Post a frame-anchored comment on the board's current review proxy and echo
  /// it locally as a timecoded note. [cmdJson] is
  /// {"board_id","text","at_seconds","author"}. BLOCKING engine-side (it spawns
  /// the plugin).
  /// Returns JSON: {"success":true,"comment":{…}} | {"success":false,"error":"…"}
  static String? reviewAddComment(String cmdJson) {
    final ptr = cmdJson.toNativeUtf8();
    try {
      final result = _b.reviewAddComment(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// The review-loop state machine's ONE entrypoint. [cmdJson] is
  /// {"op":<name>,"actor":"auto|agent|human",…}; the three-actor authority model
  /// is enforced INSIDE the engine, so a refusal comes back as an envelope.
  /// Returns the op's own JSON (an object for most ops, an array for
  /// `nudges_for` / `loop_runs`) | {"error":"…"}.
  static String? reviewCommand(String cmdJson) {
    final ptr = cmdJson.toNativeUtf8();
    try {
      final result = _b.reviewCommand(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// The ingest surface's ONE entrypoint: the watched sources and the per-asset
  /// workflow runs a scan materializes. [cmdJson] is `{"op":<name>,…}` with op
  /// one of source_add, source_list, source_remove, scan_now, scan_due,
  /// runs_for_board, produce_master_plan. `scan_now` / `scan_due` walk the
  /// watched location, so they are BLOCKING engine-side.
  /// Returns the op's own JSON (an object for most ops, an array for
  /// `source_list` / `scan_due` / `runs_for_board`) | {"error":"…"}.
  static String? ingestCommand(String cmdJson) {
    final ptr = cmdJson.toNativeUtf8();
    try {
      final result = _b.ingestCommand(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// The plugin bundles installed on THIS device, with each bundle's declared
  /// tools. A bundle whose manifest will not parse is skipped engine-side, so
  /// it never appears here.
  /// Returns JSON: {"plugins":[{"id","version","tools":[{"name",
  /// "side_effects"}]}]}
  static String? pluginCatalog() {
    final result = _b.pluginCatalog();
    if (result == nullptr) return null;
    return result.toDartStringAndFree();
  }

  /// Install a `.cyanplugin` bundle from its base64 bytes. The engine admits
  /// the bundle on layout + signature policy BEFORE anything lands, so a
  /// refusal comes back here rather than a partial install.
  /// Returns JSON: {"success":true,"plugin_id":"…","file_id":"…"} |
  /// {"success":false,"error":"…"}
  static String? installPluginBundle(
      String groupId, String pluginId, String bundleBytesB64) {
    final groupPtr = groupId.toNativeUtf8();
    final pluginPtr = pluginId.toNativeUtf8();
    final bundlePtr = bundleBytesB64.toNativeUtf8();
    try {
      final result = _b.installPluginBundle(groupPtr, pluginPtr, bundlePtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(groupPtr);
      calloc.free(pluginPtr);
      calloc.free(bundlePtr);
    }
  }

  /// Read a plugin's NON-SECRET config. [cmdJson] is
  /// `{"plugin_id","board_id"?,"tenant_id"?,"key"?}`; with `key` the reply
  /// carries a single `value`, without it every row as `values`.
  /// Returns JSON: {"ok":true,"values":{k:v}} | {"ok":true,"value":"…"|null} |
  /// {"ok":false,"error":"…"}
  static String? pluginConfigGet(String cmdJson) {
    final ptr = cmdJson.toNativeUtf8();
    try {
      final result = _b.pluginConfigGet(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Upsert one NON-SECRET config row. [cmdJson] is
  /// `{"plugin_id","key","value","board_id"?,"tenant_id"?}`. The ENGINE refuses
  /// a secret-looking key outright — credentials belong to the device vault.
  /// Returns JSON: {"ok":true} | {"ok":false,"error":"…"}
  static String? pluginConfigSet(String cmdJson) {
    final ptr = cmdJson.toNativeUtf8();
    try {
      final result = _b.pluginConfigSet(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Drive the content-addressed ChangeList store — the review-&-conform
  /// ledger. [cmdJson] is `{"op":<name>,…}` with op one of append, set_state,
  /// set_active, supersede, snapshot, branch, diff, conform_plan, get,
  /// get_version, set_outcome (plus the board dialect's `list`).
  /// Returns the op's own JSON | {"error":"…"}.
  static String? changelistCommand(String cmdJson) {
    final ptr = cmdJson.toNativeUtf8();
    try {
      final result = _b.changelistCommand(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  // ---- lens command bar -----------------------------------------------------

  /// Complete a partial `g\Group\Workspace\Board` path, ten rows at a time.
  /// The engine takes a BOUNDED read here because this fires per keystroke —
  /// a busy store answers null, meaning "no suggestions this keystroke", and
  /// the next one retries.
  /// Returns a JSON array of {name, path}.
  static String? autocompletePath(String partial) {
    final ptr = partial.toNativeUtf8();
    try {
      final result = _b.autocompletePath(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  /// Parse one `/verb` line. The engine resolves the path it names AND already
  /// runs the read-only verbs (`/pipeline status` comes back carrying its
  /// status payload), so the reply is dispatched on rather than re-parsed.
  /// Returns JSON: {"type":"help|import|pipeline|natural_language|pin|
  /// summarize|summarize_file|grep|status|pulse", …}
  static String? parseLensCommand(String input) {
    final ptr = input.toNativeUtf8();
    try {
      final result = _b.parseLensCommand(ptr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(ptr);
    }
  }

  // ---- demo seeding ---------------------------------------------------------

  /// Seed the coherent demo set under this device's OWN identity. Idempotent
  /// (truncate-then-seed of the managed group ids) and fire-and-forget: the
  /// engine queues it and emits a tree snapshot when it lands.
  static void seedDemo() => _b.seedDemo();

  /// Seed the six-role persona cast and get the routing manifest back. GATED
  /// engine-side: a build without `CYAN_SEED_DEMO=1` answers
  /// {"error":"seed_disabled"} and seeds nothing.
  /// Returns JSON: {"personas":[…]} | {"error":"…"}
  static String? seedPersonas(String tenantId, String ownerNodeId) {
    final tenantPtr = tenantId.toNativeUtf8();
    final ownerPtr = ownerNodeId.toNativeUtf8();
    try {
      final result = _b.seedPersonas(tenantPtr, ownerPtr);
      if (result == nullptr) return null;
      return result.toDartStringAndFree();
    } finally {
      calloc.free(tenantPtr);
      calloc.free(ownerPtr);
    }
  }
}
