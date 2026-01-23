// ffi/cyan_ffi.dart
// Core FFI bindings to Rust backend - matches Swift's ComponentActor pattern

import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'package:ffi/ffi.dart';

// Native typedefs
typedef _CyanIsReadyNative = Bool Function();
typedef _CyanIsReady = bool Function();

typedef _CyanSendCommandNative = Bool Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _CyanSendCommand = bool Function(Pointer<Utf8>, Pointer<Utf8>);

typedef _CyanPollEventsNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _CyanPollEvents = Pointer<Utf8> Function(Pointer<Utf8>);

typedef _CyanFreeStringNative = Void Function(Pointer<Utf8>);
typedef _CyanFreeString = void Function(Pointer<Utf8>);

typedef _CyanSeedDemoNative = Bool Function();
typedef _CyanSeedDemo = bool Function();

/// Singleton FFI wrapper - matches Swift's FFI pattern
class CyanFFI {
  static CyanFFI? _instance;
  static CyanFFI get instance => _instance ??= CyanFFI._();
  
  DynamicLibrary? _lib;
  _CyanIsReady? _isReadyFn;
  _CyanSendCommand? _sendCommand;
  _CyanPollEvents? _pollEvents;
  _CyanFreeString? _freeString;
  _CyanSeedDemo? _seedDemoFn;
  
  bool _initialized = false;
  
  CyanFFI._() {
    _tryLoadLibrary();
  }
  
  void _tryLoadLibrary() {
    try {
      _lib = _loadLibrary();
      _bindFunctions();
      _initialized = true;
      print('✅ CyanFFI: Library loaded successfully');
    } catch (e) {
      print('⚠️ CyanFFI: Library not loaded - $e');
      _initialized = false;
    }
  }
  
  DynamicLibrary _loadLibrary() {
    if (Platform.isMacOS) {
      // For Flutter macOS, the dylib should be in Frameworks
      return DynamicLibrary.process();
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libcyan_core.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('cyan_core.dll');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libcyan_core.so');
    }
    throw UnsupportedError('Unsupported platform');
  }
  
  void _bindFunctions() {
    final lib = _lib!;
    _isReadyFn = lib.lookupFunction<_CyanIsReadyNative, _CyanIsReady>('cyan_is_ready');
    _sendCommand = lib.lookupFunction<_CyanSendCommandNative, _CyanSendCommand>('cyan_send_command');
    _pollEvents = lib.lookupFunction<_CyanPollEventsNative, _CyanPollEvents>('cyan_poll_events');
    _freeString = lib.lookupFunction<_CyanFreeStringNative, _CyanFreeString>('cyan_free_string');
    _seedDemoFn = lib.lookupFunction<_CyanSeedDemoNative, _CyanSeedDemo>('cyan_seed_demo_if_empty');
  }
  
  /// Check if backend is ready (instance method)
  bool _checkReady() {
    if (!_initialized) return false;
    try {
      return _isReadyFn?.call() ?? false;
    } catch (_) {
      return false;
    }
  }
  
  /// Seed demo data (instance method)
  bool _seedDemo() {
    if (!_initialized || _seedDemoFn == null) return false;
    return _seedDemoFn!();
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // STATIC API - Called by existing code as CyanFFI.methodName()
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Check if backend is ready - STATIC for CyanFFI.isReady()
  static bool isReady() {
    return CyanFFI.instance._checkReady();
  }
  
  /// Seed demo data if database is empty - STATIC for CyanFFI.seedDemoIfEmpty()
  static void seedDemoIfEmpty() {
    CyanFFI.instance._seedDemo();
  }
  
  /// Initialize backend with identity - called after login
  static bool initWithIdentity(String dbPath, String secretKeyHex, String relayUrl, String discoveryKey) {
    final ffi = CyanFFI.instance;
    if (!ffi._initialized) {
      print('⚠️ CyanFFI.initWithIdentity: Not initialized');
      return false;
    }
    
    try {
      final initFn = ffi._lib!.lookupFunction<
        Bool Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
        bool Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)
      >('cyan_init_with_identity');
      
      final dbPathPtr = dbPath.toNativeUtf8();
      final keyPtr = secretKeyHex.toNativeUtf8();
      final relayPtr = relayUrl.toNativeUtf8();
      final discoveryPtr = discoveryKey.toNativeUtf8();
      
      try {
        return initFn(dbPathPtr, keyPtr, relayPtr, discoveryPtr);
      } finally {
        calloc.free(dbPathPtr);
        calloc.free(keyPtr);
        calloc.free(relayPtr);
        calloc.free(discoveryPtr);
      }
    } catch (e) {
      print('⚠️ CyanFFI.initWithIdentity error: $e');
      return false;
    }
  }
  
  /// Get node ID as hex string
  static String? getNodeId() {
    final ffi = CyanFFI.instance;
    if (!ffi._initialized) return null;
    
    try {
      final getFn = ffi._lib!.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('cyan_get_node_id_hex');
      
      final ptr = getFn();
      if (ptr == nullptr) return null;
      
      final result = ptr.toDartString();
      ffi._freeString!(ptr);
      return result;
    } catch (e) {
      print('⚠️ CyanFFI.getNodeId error: $e');
      return null;
    }
  }
  
  /// Get total object count from database
  static int getObjectCount() {
    final ffi = CyanFFI.instance;
    if (!ffi._initialized) return 0;
    
    try {
      final getFn = ffi._lib!.lookupFunction<
        Int32 Function(),
        int Function()
      >('cyan_get_object_count');
      return getFn();
    } catch (e) {
      return 0;
    }
  }
  
  /// Get total connected peer count
  static int getTotalPeerCount() {
    final ffi = CyanFFI.instance;
    if (!ffi._initialized) return 0;
    
    try {
      final getFn = ffi._lib!.lookupFunction<
        Int32 Function(),
        int Function()
      >('cyan_get_total_peer_count');
      return getFn();
    } catch (e) {
      return 0;
    }
  }
  
  /// Get current user's profile as map (NOT as JSON string)
  static Map<String, dynamic>? getMyProfile() {
    final ffi = CyanFFI.instance;
    if (!ffi._initialized) {
      return {
        'node_id': 'unknown',
        'display_name': 'Me',
      };
    }
    
    try {
      final getFn = ffi._lib!.lookupFunction<
        Pointer<Utf8> Function(),
        Pointer<Utf8> Function()
      >('cyan_get_my_profile');
      
      final ptr = getFn();
      if (ptr == nullptr) {
        return {
          'node_id': getNodeId() ?? 'unknown',
          'display_name': 'Me',
        };
      }
      
      final jsonStr = ptr.toDartString();
      ffi._freeString!(ptr);
      
      return jsonDecode(jsonStr) as Map<String, dynamic>?;
    } catch (e) {
      return {
        'node_id': getNodeId() ?? 'unknown',
        'display_name': 'Me',
      };
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // INSTANCE METHODS - Used by providers for command/event flow
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Send command to a component (matches Swift's sendCommand)
  bool sendCommand(String component, String json) {
    if (!_initialized || _sendCommand == null) {
      print('⚠️ CyanFFI.sendCommand: Not initialized');
      return false;
    }
    
    final componentPtr = component.toNativeUtf8();
    final jsonPtr = json.toNativeUtf8();
    
    try {
      final result = _sendCommand!(componentPtr, jsonPtr);
      return result;
    } finally {
      calloc.free(componentPtr);
      calloc.free(jsonPtr);
    }
  }
  
  /// Poll events from a component (matches Swift's pollEvents)
  String? pollEvents(String component) {
    if (!_initialized || _pollEvents == null || _freeString == null) {
      return null;
    }
    
    final componentPtr = component.toNativeUtf8();
    
    try {
      final resultPtr = _pollEvents!(componentPtr);
      if (resultPtr == nullptr) return null;
      
      final result = resultPtr.toDartString();
      _freeString!(resultPtr);
      return result;
    } finally {
      calloc.free(componentPtr);
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // HIGH-LEVEL COMMAND HELPERS (matches Swift's ComponentActor pattern)
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Create a group - sends CreateGroup command to file_tree component
  bool createGroup(String name, {String icon = '📁', String color = '#FD971F'}) {
    final cmd = jsonEncode({
      'type': 'CreateGroup',
      'name': name,
      'icon': icon,
      'color': color,
    });
    return sendCommand('file_tree', cmd);
  }
  
  /// Create a workspace in a group
  bool createWorkspace(String groupId, String name) {
    final cmd = jsonEncode({
      'type': 'CreateWorkspace',
      'group_id': groupId,
      'name': name,
    });
    return sendCommand('file_tree', cmd);
  }
  
  /// Create a board in a workspace
  bool createBoard(String workspaceId, String name) {
    final cmd = jsonEncode({
      'type': 'CreateBoard',
      'workspace_id': workspaceId,
      'name': name,
    });
    return sendCommand('file_tree', cmd);
  }
  
  /// Rename a group
  bool renameGroup(String id, String name) {
    final cmd = jsonEncode({
      'type': 'RenameGroup',
      'id': id,
      'name': name,
    });
    return sendCommand('file_tree', cmd);
  }
  
  /// Rename a workspace
  bool renameWorkspace(String id, String name) {
    final cmd = jsonEncode({
      'type': 'RenameWorkspace',
      'id': id,
      'name': name,
    });
    return sendCommand('file_tree', cmd);
  }
  
  /// Rename a board
  bool renameBoard(String id, String name) {
    final cmd = jsonEncode({
      'type': 'RenameBoard',
      'id': id,
      'name': name,
    });
    return sendCommand('file_tree', cmd);
  }
  
  /// Delete a group
  bool deleteGroup(String id) {
    final cmd = jsonEncode({
      'type': 'DeleteGroup',
      'id': id,
    });
    return sendCommand('file_tree', cmd);
  }
  
  /// Delete a workspace
  bool deleteWorkspace(String id) {
    final cmd = jsonEncode({
      'type': 'DeleteWorkspace',
      'id': id,
    });
    return sendCommand('file_tree', cmd);
  }

  /// Delete a board
  bool deleteBoard(String id) {
    final cmd = jsonEncode({
      'type': 'DeleteBoard',
      'id': id,
    });
    return sendCommand('file_tree', cmd);
  }

  /// Request snapshot (tree reload)
  bool requestSnapshot() {
    final cmd = jsonEncode({'type': 'Snapshot'});
    return sendCommand('file_tree', cmd);
  }
}
