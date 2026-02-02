// ffi/cyan_bindings.dart
// Complete FFI bindings for all 87 cyan_* functions
// Generated from: nm -gU libcyan_backend_macos.a | grep " T _cyan_"

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

// Lifecycle
typedef CyanInitNative = Bool Function(Pointer<Utf8> dbPath);
typedef CyanInitDart = bool Function(Pointer<Utf8> dbPath);

typedef CyanInitWithIdentityNative = Bool Function(
  Pointer<Utf8> dbPath, Pointer<Utf8> secretKeyHex, 
  Pointer<Utf8> relayUrl, Pointer<Utf8> discoveryKey);
typedef CyanInitWithIdentityDart = bool Function(
  Pointer<Utf8> dbPath, Pointer<Utf8> secretKeyHex,
  Pointer<Utf8> relayUrl, Pointer<Utf8> discoveryKey);

typedef CyanSetDataDirNative = Bool Function(Pointer<Utf8> path);
typedef CyanSetDataDirDart = bool Function(Pointer<Utf8> path);

typedef CyanSetDiscoveryKeyNative = Bool Function(Pointer<Utf8> key);
typedef CyanSetDiscoveryKeyDart = bool Function(Pointer<Utf8> key);

typedef CyanIsReadyNative = Bool Function();
typedef CyanIsReadyDart = bool Function();

typedef CyanFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef CyanFreeStringDart = void Function(Pointer<Utf8> ptr);

// Identity
typedef CyanGetNodeIdNative = Pointer<Utf8> Function();
typedef CyanGetNodeIdDart = Pointer<Utf8> Function();

typedef CyanGetXaeroIdNative = Pointer<Utf8> Function();
typedef CyanGetXaeroIdDart = Pointer<Utf8> Function();

typedef CyanSetXaeroIdNative = Bool Function(Pointer<Utf8> id);
typedef CyanSetXaeroIdDart = bool Function(Pointer<Utf8> id);

// Identity generation/derivation
typedef CyanGenerateIdentityJsonNative = Pointer<Utf8> Function();
typedef CyanGenerateIdentityJsonDart = Pointer<Utf8> Function();

typedef CyanDeriveIdentityNative = Pointer<Utf8> Function(Pointer<Utf8> secretKeyHex);
typedef CyanDeriveIdentityDart = Pointer<Utf8> Function(Pointer<Utf8> secretKeyHex);

typedef CyanGetMyNodeIdNative = Pointer<Utf8> Function();
typedef CyanGetMyNodeIdDart = Pointer<Utf8> Function();

typedef CyanGetMyProfileNative = Pointer<Utf8> Function();
typedef CyanGetMyProfileDart = Pointer<Utf8> Function();

typedef CyanSetMyProfileNative = Bool Function(Pointer<Utf8> json);
typedef CyanSetMyProfileDart = bool Function(Pointer<Utf8> json);

// Command/Event (ComponentActor pattern)
typedef CyanSendCommandNative = Bool Function(Pointer<Utf8> component, Pointer<Utf8> json);
typedef CyanSendCommandDart = bool Function(Pointer<Utf8> component, Pointer<Utf8> json);

typedef CyanPollEventsNative = Pointer<Utf8> Function(Pointer<Utf8> component);
typedef CyanPollEventsDart = Pointer<Utf8> Function(Pointer<Utf8> component);

typedef CyanSeedDemoIfEmptyNative = Bool Function();
typedef CyanSeedDemoIfEmptyDart = bool Function();

// Stats
typedef CyanGetObjectCountNative = Int32 Function();
typedef CyanGetObjectCountDart = int Function();

typedef CyanGetTotalPeerCountNative = Int32 Function();
typedef CyanGetTotalPeerCountDart = int Function();

typedef CyanGetGroupPeerCountNative = Int32 Function(Pointer<Utf8> groupId);
typedef CyanGetGroupPeerCountDart = int Function(Pointer<Utf8> groupId);

// Groups
typedef CyanCreateGroupNative = Void Function(Pointer<Utf8> name, Pointer<Utf8> icon, Pointer<Utf8> color);
typedef CyanCreateGroupDart = void Function(Pointer<Utf8> name, Pointer<Utf8> icon, Pointer<Utf8> color);

typedef CyanRenameGroupNative = Void Function(Pointer<Utf8> id, Pointer<Utf8> name);
typedef CyanRenameGroupDart = void Function(Pointer<Utf8> id, Pointer<Utf8> name);

typedef CyanDeleteGroupNative = Void Function(Pointer<Utf8> id);
typedef CyanDeleteGroupDart = void Function(Pointer<Utf8> id);

typedef CyanLeaveGroupNative = Void Function(Pointer<Utf8> id);
typedef CyanLeaveGroupDart = void Function(Pointer<Utf8> id);

typedef CyanIsGroupOwnerNative = Bool Function(Pointer<Utf8> id);
typedef CyanIsGroupOwnerDart = bool Function(Pointer<Utf8> id);

// Workspaces
typedef CyanCreateWorkspaceNative = Void Function(Pointer<Utf8> groupId, Pointer<Utf8> name);
typedef CyanCreateWorkspaceDart = void Function(Pointer<Utf8> groupId, Pointer<Utf8> name);

typedef CyanRenameWorkspaceNative = Void Function(Pointer<Utf8> id, Pointer<Utf8> name);
typedef CyanRenameWorkspaceDart = void Function(Pointer<Utf8> id, Pointer<Utf8> name);

typedef CyanDeleteWorkspaceNative = Void Function(Pointer<Utf8> id);
typedef CyanDeleteWorkspaceDart = void Function(Pointer<Utf8> id);

typedef CyanLeaveWorkspaceNative = Void Function(Pointer<Utf8> id);
typedef CyanLeaveWorkspaceDart = void Function(Pointer<Utf8> id);

typedef CyanIsWorkspaceOwnerNative = Bool Function(Pointer<Utf8> id);
typedef CyanIsWorkspaceOwnerDart = bool Function(Pointer<Utf8> id);

typedef CyanGetWorkspacesForGroupNative = Pointer<Utf8> Function(Pointer<Utf8> groupId);
typedef CyanGetWorkspacesForGroupDart = Pointer<Utf8> Function(Pointer<Utf8> groupId);

// Boards
typedef CyanCreateBoardNative = Void Function(Pointer<Utf8> workspaceId, Pointer<Utf8> name);
typedef CyanCreateBoardDart = void Function(Pointer<Utf8> workspaceId, Pointer<Utf8> name);

typedef CyanRenameBoardNative = Void Function(Pointer<Utf8> id, Pointer<Utf8> name);
typedef CyanRenameBoardDart = void Function(Pointer<Utf8> id, Pointer<Utf8> name);

typedef CyanDeleteBoardNative = Void Function(Pointer<Utf8> id);
typedef CyanDeleteBoardDart = void Function(Pointer<Utf8> id);

typedef CyanLeaveBoardNative = Void Function(Pointer<Utf8> id);
typedef CyanLeaveBoardDart = void Function(Pointer<Utf8> id);

typedef CyanIsBoardOwnerNative = Bool Function(Pointer<Utf8> id);
typedef CyanIsBoardOwnerDart = bool Function(Pointer<Utf8> id);

typedef CyanGetAllBoardsNative = Pointer<Utf8> Function();
typedef CyanGetAllBoardsDart = Pointer<Utf8> Function();

typedef CyanGetBoardsForGroupNative = Pointer<Utf8> Function(Pointer<Utf8> groupId);
typedef CyanGetBoardsForGroupDart = Pointer<Utf8> Function(Pointer<Utf8> groupId);

typedef CyanGetBoardsForWorkspaceNative = Pointer<Utf8> Function(Pointer<Utf8> workspaceId);
typedef CyanGetBoardsForWorkspaceDart = Pointer<Utf8> Function(Pointer<Utf8> workspaceId);

typedef CyanGetBoardModeNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanGetBoardModeDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanSetBoardModeNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> mode);
typedef CyanSetBoardModeDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> mode);

typedef CyanIsBoardPinnedNative = Bool Function(Pointer<Utf8> boardId);
typedef CyanIsBoardPinnedDart = bool Function(Pointer<Utf8> boardId);

typedef CyanPinBoardNative = Bool Function(Pointer<Utf8> boardId);
typedef CyanPinBoardDart = bool Function(Pointer<Utf8> boardId);

typedef CyanUnpinBoardNative = Bool Function(Pointer<Utf8> boardId);
typedef CyanUnpinBoardDart = bool Function(Pointer<Utf8> boardId);

typedef CyanRateBoardNative = Bool Function(Pointer<Utf8> boardId, Int32 rating);
typedef CyanRateBoardDart = bool Function(Pointer<Utf8> boardId, int rating);

typedef CyanRecordBoardViewNative = Bool Function(Pointer<Utf8> boardId);
typedef CyanRecordBoardViewDart = bool Function(Pointer<Utf8> boardId);

// Board Metadata
typedef CyanGetBoardMetadataNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanGetBoardMetadataDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanGetBoardsMetadataNative = Pointer<Utf8> Function(Pointer<Utf8> boardIdsJson);
typedef CyanGetBoardsMetadataDart = Pointer<Utf8> Function(Pointer<Utf8> boardIdsJson);

typedef CyanGetTopBoardsNative = Pointer<Utf8> Function(Int32 limit);
typedef CyanGetTopBoardsDart = Pointer<Utf8> Function(int limit);

typedef CyanGetBoardLinkNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanGetBoardLinkDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanSearchBoardsByLabelNative = Pointer<Utf8> Function(Pointer<Utf8> label);
typedef CyanSearchBoardsByLabelDart = Pointer<Utf8> Function(Pointer<Utf8> label);

typedef CyanSetBoardLabelsNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> labelsJson);
typedef CyanSetBoardLabelsDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> labelsJson);

typedef CyanAddBoardLabelNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> label);
typedef CyanAddBoardLabelDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> label);

typedef CyanRemoveBoardLabelNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> label);
typedef CyanRemoveBoardLabelDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> label);

typedef CyanSetBoardModelNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> model);
typedef CyanSetBoardModelDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> model);

typedef CyanSetBoardSkillsNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> skillsJson);
typedef CyanSetBoardSkillsDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> skillsJson);

// Peers
typedef CyanGetGroupPeersNative = Pointer<Utf8> Function(Pointer<Utf8> groupId);
typedef CyanGetGroupPeersDart = Pointer<Utf8> Function(Pointer<Utf8> groupId);

typedef CyanGetAllPeersNative = Pointer<Utf8> Function();
typedef CyanGetAllPeersDart = Pointer<Utf8> Function();

typedef CyanUpdatePeerStatusNative = Bool Function(Pointer<Utf8> peerId, Pointer<Utf8> statusJson);
typedef CyanUpdatePeerStatusDart = bool Function(Pointer<Utf8> peerId, Pointer<Utf8> statusJson);

// Profile
typedef CyanGetUserProfileNative = Pointer<Utf8> Function(Pointer<Utf8> nodeId);
typedef CyanGetUserProfileDart = Pointer<Utf8> Function(Pointer<Utf8> nodeId);

typedef CyanGetProfilesBatchNative = Pointer<Utf8> Function(Pointer<Utf8> nodeIdsJson);
typedef CyanGetProfilesBatchDart = Pointer<Utf8> Function(Pointer<Utf8> nodeIdsJson);

// Chat
typedef CyanSendChatNative = Void Function(Pointer<Utf8> workspaceId, Pointer<Utf8> message, Pointer<Utf8> parentId);
typedef CyanSendChatDart = void Function(Pointer<Utf8> workspaceId, Pointer<Utf8> message, Pointer<Utf8> parentId);

typedef CyanDeleteChatNative = Void Function(Pointer<Utf8> id);
typedef CyanDeleteChatDart = void Function(Pointer<Utf8> id);

typedef CyanStartDirectChatNative = Bool Function(Pointer<Utf8> peerId, Pointer<Utf8> workspaceId);
typedef CyanStartDirectChatDart = bool Function(Pointer<Utf8> peerId, Pointer<Utf8> workspaceId);

typedef CyanSendDirectChatNative = Bool Function(Pointer<Utf8> peerId, Pointer<Utf8> message);
typedef CyanSendDirectChatDart = bool Function(Pointer<Utf8> peerId, Pointer<Utf8> message);

// Files
typedef CyanUploadFileNative = Pointer<Utf8> Function(Pointer<Utf8> path, Pointer<Utf8> scopeJson);
typedef CyanUploadFileDart = Pointer<Utf8> Function(Pointer<Utf8> path, Pointer<Utf8> scopeJson);

typedef CyanUploadFileToGroupNative = Pointer<Utf8> Function(Pointer<Utf8> path, Pointer<Utf8> groupId);
typedef CyanUploadFileToGroupDart = Pointer<Utf8> Function(Pointer<Utf8> path, Pointer<Utf8> groupId);

typedef CyanUploadFileToWorkspaceNative = Pointer<Utf8> Function(Pointer<Utf8> path, Pointer<Utf8> workspaceId);
typedef CyanUploadFileToWorkspaceDart = Pointer<Utf8> Function(Pointer<Utf8> path, Pointer<Utf8> workspaceId);

typedef CyanRequestFileDownloadNative = Bool Function(Pointer<Utf8> fileId);
typedef CyanRequestFileDownloadDart = bool Function(Pointer<Utf8> fileId);

typedef CyanGetFileStatusNative = Pointer<Utf8> Function(Pointer<Utf8> fileId);
typedef CyanGetFileStatusDart = Pointer<Utf8> Function(Pointer<Utf8> fileId);

typedef CyanGetFilesNative = Pointer<Utf8> Function(Pointer<Utf8> scopeJson);
typedef CyanGetFilesDart = Pointer<Utf8> Function(Pointer<Utf8> scopeJson);

typedef CyanGetFileLocalPathNative = Pointer<Utf8> Function(Pointer<Utf8> fileId);
typedef CyanGetFileLocalPathDart = Pointer<Utf8> Function(Pointer<Utf8> fileId);

// Whiteboard
typedef CyanLoadWhiteboardElementsNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanLoadWhiteboardElementsDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanSaveWhiteboardElementNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> elementJson);
typedef CyanSaveWhiteboardElementDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> elementJson);

typedef CyanDeleteWhiteboardElementNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> elementId);
typedef CyanDeleteWhiteboardElementDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> elementId);

typedef CyanClearWhiteboardNative = Bool Function(Pointer<Utf8> boardId);
typedef CyanClearWhiteboardDart = bool Function(Pointer<Utf8> boardId);

typedef CyanGetWhiteboardElementCountNative = Int32 Function(Pointer<Utf8> boardId);
typedef CyanGetWhiteboardElementCountDart = int Function(Pointer<Utf8> boardId);

// Notebook
typedef CyanLoadNotebookCellsNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanLoadNotebookCellsDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanSaveNotebookCellNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> cellJson);
typedef CyanSaveNotebookCellDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> cellJson);

typedef CyanDeleteNotebookCellNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> cellId);
typedef CyanDeleteNotebookCellDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> cellId);

typedef CyanReorderNotebookCellsNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> orderJson);
typedef CyanReorderNotebookCellsDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> orderJson);

typedef CyanLoadCellElementsNative = Pointer<Utf8> Function(Pointer<Utf8> cellId);
typedef CyanLoadCellElementsDart = Pointer<Utf8> Function(Pointer<Utf8> cellId);

// Integration
typedef CyanIntegrationCommandNative = Bool Function(Pointer<Utf8> json);
typedef CyanIntegrationCommandDart = bool Function(Pointer<Utf8> json);

typedef CyanPollIntegrationEventsNative = Pointer<Utf8> Function();
typedef CyanPollIntegrationEventsDart = Pointer<Utf8> Function();

typedef CyanGetConnectedIntegrationsNative = Pointer<Utf8> Function(Pointer<Utf8> scopeId);
typedef CyanGetConnectedIntegrationsDart = Pointer<Utf8> Function(Pointer<Utf8> scopeId);

typedef CyanGetIntegrationGraphNative = Pointer<Utf8> Function(Pointer<Utf8> scopeId);
typedef CyanGetIntegrationGraphDart = Pointer<Utf8> Function(Pointer<Utf8> scopeId);

typedef CyanSetGraphFocusNative = Bool Function(Pointer<Utf8> scopeId, Pointer<Utf8> focusJson);
typedef CyanSetGraphFocusDart = bool Function(Pointer<Utf8> scopeId, Pointer<Utf8> focusJson);

// AI
typedef CyanAiCommandNative = Bool Function(Pointer<Utf8> json);
typedef CyanAiCommandDart = bool Function(Pointer<Utf8> json);

typedef CyanPollAiResponseNative = Pointer<Utf8> Function();
typedef CyanPollAiResponseDart = Pointer<Utf8> Function();

typedef CyanPollAiInsightsNative = Pointer<Utf8> Function();
typedef CyanPollAiInsightsDart = Pointer<Utf8> Function();


// ============================================================================
// BINDINGS CLASS
// ============================================================================

final Pointer<Utf8> _nullptr = Pointer<Utf8>.fromAddress(0);

class CyanBindings {
  static CyanBindings? _instance;
  late final DynamicLibrary _lib;
  
  // Lifecycle
  late final CyanInitDart init;
  late final CyanInitWithIdentityDart initWithIdentity;
  late final CyanSetDataDirDart setDataDir;
  late final CyanSetDiscoveryKeyDart setDiscoveryKey;
  late final CyanIsReadyDart isReady;
  late final CyanFreeStringDart freeString;
  
  // Identity
  late final CyanGetNodeIdDart getNodeId;
  late final CyanGetXaeroIdDart getXaeroId;
  late final CyanSetXaeroIdDart setXaeroId;
  late final CyanGenerateIdentityJsonDart generateIdentityJson;
  late final CyanDeriveIdentityDart deriveIdentity;
  late final CyanGetMyNodeIdDart getMyNodeId;
  late final CyanGetMyProfileDart getMyProfile;
  late final CyanSetMyProfileDart setMyProfile;
  
  // Command/Event (ComponentActor pattern)
  late final CyanSendCommandDart sendCommand;
  late final CyanPollEventsDart pollEvents;
  late final CyanSeedDemoIfEmptyDart seedDemoIfEmpty;
  
  // Stats
  late final CyanGetObjectCountDart getObjectCount;
  late final CyanGetTotalPeerCountDart getTotalPeerCount;
  late final CyanGetGroupPeerCountDart getGroupPeerCount;
  
  // Groups
  late final CyanCreateGroupDart createGroup;
  late final CyanRenameGroupDart renameGroup;
  late final CyanDeleteGroupDart deleteGroup;
  late final CyanLeaveGroupDart leaveGroup;
  late final CyanIsGroupOwnerDart isGroupOwner;
  
  // Workspaces
  late final CyanCreateWorkspaceDart createWorkspace;
  late final CyanRenameWorkspaceDart renameWorkspace;
  late final CyanDeleteWorkspaceDart deleteWorkspace;
  late final CyanLeaveWorkspaceDart leaveWorkspace;
  late final CyanIsWorkspaceOwnerDart isWorkspaceOwner;
  late final CyanGetWorkspacesForGroupDart getWorkspacesForGroup;
  
  // Boards
  late final CyanCreateBoardDart createBoard;
  late final CyanRenameBoardDart renameBoard;
  late final CyanDeleteBoardDart deleteBoard;
  late final CyanLeaveBoardDart leaveBoard;
  late final CyanIsBoardOwnerDart isBoardOwner;
  late final CyanGetAllBoardsDart getAllBoards;
  late final CyanGetBoardsForGroupDart getBoardsForGroup;
  late final CyanGetBoardsForWorkspaceDart getBoardsForWorkspace;
  late final CyanGetBoardModeDart getBoardMode;
  late final CyanSetBoardModeDart setBoardMode;
  late final CyanIsBoardPinnedDart isBoardPinned;
  late final CyanPinBoardDart pinBoard;
  late final CyanUnpinBoardDart unpinBoard;
  late final CyanRateBoardDart rateBoard;
  late final CyanRecordBoardViewDart recordBoardView;
  
  // Board Metadata
  late final CyanGetBoardMetadataDart getBoardMetadata;
  late final CyanGetBoardsMetadataDart getBoardsMetadata;
  late final CyanGetTopBoardsDart getTopBoards;
  late final CyanGetBoardLinkDart getBoardLink;
  late final CyanSearchBoardsByLabelDart searchBoardsByLabel;
  late final CyanSetBoardLabelsDart setBoardLabels;
  late final CyanAddBoardLabelDart addBoardLabel;
  late final CyanRemoveBoardLabelDart removeBoardLabel;
  late final CyanSetBoardModelDart setBoardModel;
  late final CyanSetBoardSkillsDart setBoardSkills;
  
  // Peers
  late final CyanGetGroupPeersDart getGroupPeers;
  late final CyanGetAllPeersDart getAllPeers;
  late final CyanUpdatePeerStatusDart updatePeerStatus;
  
  // Profile
  late final CyanGetUserProfileDart getUserProfile;
  late final CyanGetProfilesBatchDart getProfilesBatch;
  
  // Chat
  late final CyanSendChatDart sendChat;
  late final CyanDeleteChatDart deleteChat;
  late final CyanStartDirectChatDart startDirectChat;
  late final CyanSendDirectChatDart sendDirectChat;
  
  // Files
  late final CyanUploadFileDart uploadFile;
  late final CyanUploadFileToGroupDart uploadFileToGroup;
  late final CyanUploadFileToWorkspaceDart uploadFileToWorkspace;
  late final CyanRequestFileDownloadDart requestFileDownload;
  late final CyanGetFileStatusDart getFileStatus;
  late final CyanGetFilesDart getFiles;
  late final CyanGetFileLocalPathDart getFileLocalPath;
  
  // Whiteboard
  late final CyanLoadWhiteboardElementsDart loadWhiteboardElements;
  late final CyanSaveWhiteboardElementDart saveWhiteboardElement;
  late final CyanDeleteWhiteboardElementDart deleteWhiteboardElement;
  late final CyanClearWhiteboardDart clearWhiteboard;
  late final CyanGetWhiteboardElementCountDart getWhiteboardElementCount;
  
  // Notebook
  late final CyanLoadNotebookCellsDart loadNotebookCells;
  late final CyanSaveNotebookCellDart saveNotebookCell;
  late final CyanDeleteNotebookCellDart deleteNotebookCell;
  late final CyanReorderNotebookCellsDart reorderNotebookCells;
  late final CyanLoadCellElementsDart loadCellElements;
  
  // Integration
  late final CyanIntegrationCommandDart integrationCommand;
  late final CyanPollIntegrationEventsDart pollIntegrationEvents;
  late final CyanGetConnectedIntegrationsDart getConnectedIntegrations;
  late final CyanGetIntegrationGraphDart getIntegrationGraph;
  late final CyanSetGraphFocusDart setGraphFocus;
  
  // AI
  late final CyanAiCommandDart aiCommand;
  late final CyanPollAiResponseDart pollAiResponse;
  late final CyanPollAiInsightsDart pollAiInsights;
  
  CyanBindings._();
  
  static CyanBindings get instance {
    _instance ??= CyanBindings._().._load();
    return _instance!;
  }
  
  bool _loaded = false;
  bool get isLoaded => _loaded;
  
  void _load() {
    try {
      _lib = _loadLibrary();
      _bindFunctions();
      _loaded = true;
      print('✅ Cyan FFI bindings loaded');
    } catch (e) {
      print('⚠️ Cyan FFI library not available: $e');
      print('   App will run with local-only fallbacks');
      _setNoOps();
      _loaded = false;
    }
  }
  
  DynamicLibrary _loadLibrary() {
    if (Platform.isMacOS) {
      // Try loading dylib from known locations
      final home = Platform.environment['HOME'] ?? '';
      final exe = Platform.resolvedExecutable;
      // exe is like .../cyan_flutter.app/Contents/MacOS/cyan_flutter
      final appDir = exe.substring(0, exe.lastIndexOf('/MacOS/'));
      
      final dylibPaths = [
        // App bundle Frameworks (where Xcode copies it)
        '$appDir/Frameworks/libcyan_core.dylib',
        // Source location
        '$home/cyan_flutter/macos/Libraries/libcyan_core.dylib',
      ];
      
      for (final path in dylibPaths) {
        if (File(path).existsSync()) {
          try {
            print('🔗 Loading dylib: $path');
            return DynamicLibrary.open(path);
          } catch (e) {
            print('⚠️ Failed to open $path: $e');
          }
        }
      }
      
      // Fall back to process symbols (static lib linked via xcframework)
      print('🔗 Falling back to DynamicLibrary.process()');
      return DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libcyan_backend.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('cyan_backend.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libcyan_backend.so');
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }
  
  // Safe lookup helper - returns null on failure
  CyanInitDart? _lookupInit(String s) { try { return _lib.lookupFunction<CyanInitNative, CyanInitDart>(s); } catch(_) { return null; } }
  CyanInitWithIdentityDart? _lookupInitId(String s) { try { return _lib.lookupFunction<CyanInitWithIdentityNative, CyanInitWithIdentityDart>(s); } catch(_) { return null; } }
  CyanSetDataDirDart? _lookupSetDataDir(String s) { try { return _lib.lookupFunction<CyanSetDataDirNative, CyanSetDataDirDart>(s); } catch(_) { return null; } }

  void _bindFunctions() {
    // Instead of individual safe lookups for 87 functions, we wrap the whole
    // thing. If any critical symbol is missing, we fall back to all no-ops.
    // This is safe because DynamicLibrary.process() will have either ALL
    // the cyan_* symbols (static lib linked) or NONE of them.
    try {
      _bindAllUnsafe();
    } catch (e) {
      print('⚠️ Some FFI symbols missing, using no-ops: $e');
      _setNoOps();
    }
  }
  
  void _bindAllUnsafe() {
    // Lifecycle
    init = _lib.lookupFunction<CyanInitNative, CyanInitDart>('cyan_init');
    initWithIdentity = _lib.lookupFunction<CyanInitWithIdentityNative, CyanInitWithIdentityDart>('cyan_init_with_identity');
    setDataDir = _lib.lookupFunction<CyanSetDataDirNative, CyanSetDataDirDart>('cyan_set_data_dir');
    setDiscoveryKey = _lib.lookupFunction<CyanSetDiscoveryKeyNative, CyanSetDiscoveryKeyDart>('cyan_set_discovery_key');
    isReady = _lib.lookupFunction<CyanIsReadyNative, CyanIsReadyDart>('cyan_is_ready');
    freeString = _lib.lookupFunction<CyanFreeStringNative, CyanFreeStringDart>('cyan_free_string');
    
    // Identity
    getNodeId = _lib.lookupFunction<CyanGetNodeIdNative, CyanGetNodeIdDart>('cyan_get_node_id');
    getXaeroId = _lib.lookupFunction<CyanGetXaeroIdNative, CyanGetXaeroIdDart>('cyan_get_xaero_id');
    setXaeroId = _lib.lookupFunction<CyanSetXaeroIdNative, CyanSetXaeroIdDart>('cyan_set_xaero_id');
    getMyNodeId = _lib.lookupFunction<CyanGetMyNodeIdNative, CyanGetMyNodeIdDart>('cyan_get_my_node_id');
    getMyProfile = _lib.lookupFunction<CyanGetMyProfileNative, CyanGetMyProfileDart>('cyan_get_my_profile');
    setMyProfile = _lib.lookupFunction<CyanSetMyProfileNative, CyanSetMyProfileDart>('cyan_set_my_profile');
    
    // Identity generation (these may not exist in all builds)
    try { generateIdentityJson = _lib.lookupFunction<CyanGenerateIdentityJsonNative, CyanGenerateIdentityJsonDart>('xaero_generate_json'); } catch(_) { generateIdentityJson = () => _nullptr; }
    try { deriveIdentity = _lib.lookupFunction<CyanDeriveIdentityNative, CyanDeriveIdentityDart>('xaero_derive_identity'); } catch(_) { deriveIdentity = (Pointer<Utf8> k) => _nullptr; }
    
    // Command/Event
    sendCommand = _lib.lookupFunction<CyanSendCommandNative, CyanSendCommandDart>('cyan_send_command');
    pollEvents = _lib.lookupFunction<CyanPollEventsNative, CyanPollEventsDart>('cyan_poll_events');
    seedDemoIfEmpty = _lib.lookupFunction<CyanSeedDemoIfEmptyNative, CyanSeedDemoIfEmptyDart>('cyan_seed_demo_if_empty');
    
    // Stats
    getObjectCount = _lib.lookupFunction<CyanGetObjectCountNative, CyanGetObjectCountDart>('cyan_get_object_count');
    getTotalPeerCount = _lib.lookupFunction<CyanGetTotalPeerCountNative, CyanGetTotalPeerCountDart>('cyan_get_total_peer_count');
    getGroupPeerCount = _lib.lookupFunction<CyanGetGroupPeerCountNative, CyanGetGroupPeerCountDart>('cyan_get_group_peer_count');
    
    // Groups
    createGroup = _lib.lookupFunction<CyanCreateGroupNative, CyanCreateGroupDart>('cyan_create_group');
    renameGroup = _lib.lookupFunction<CyanRenameGroupNative, CyanRenameGroupDart>('cyan_rename_group');
    deleteGroup = _lib.lookupFunction<CyanDeleteGroupNative, CyanDeleteGroupDart>('cyan_delete_group');
    leaveGroup = _lib.lookupFunction<CyanLeaveGroupNative, CyanLeaveGroupDart>('cyan_leave_group');
    isGroupOwner = _lib.lookupFunction<CyanIsGroupOwnerNative, CyanIsGroupOwnerDart>('cyan_is_group_owner');
    
    // Workspaces
    createWorkspace = _lib.lookupFunction<CyanCreateWorkspaceNative, CyanCreateWorkspaceDart>('cyan_create_workspace');
    renameWorkspace = _lib.lookupFunction<CyanRenameWorkspaceNative, CyanRenameWorkspaceDart>('cyan_rename_workspace');
    deleteWorkspace = _lib.lookupFunction<CyanDeleteWorkspaceNative, CyanDeleteWorkspaceDart>('cyan_delete_workspace');
    leaveWorkspace = _lib.lookupFunction<CyanLeaveWorkspaceNative, CyanLeaveWorkspaceDart>('cyan_leave_workspace');
    isWorkspaceOwner = _lib.lookupFunction<CyanIsWorkspaceOwnerNative, CyanIsWorkspaceOwnerDart>('cyan_is_workspace_owner');
    getWorkspacesForGroup = _lib.lookupFunction<CyanGetWorkspacesForGroupNative, CyanGetWorkspacesForGroupDart>('cyan_get_workspaces_for_group');
    
    // Boards
    createBoard = _lib.lookupFunction<CyanCreateBoardNative, CyanCreateBoardDart>('cyan_create_board');
    renameBoard = _lib.lookupFunction<CyanRenameBoardNative, CyanRenameBoardDart>('cyan_rename_board');
    deleteBoard = _lib.lookupFunction<CyanDeleteBoardNative, CyanDeleteBoardDart>('cyan_delete_board');
    leaveBoard = _lib.lookupFunction<CyanLeaveBoardNative, CyanLeaveBoardDart>('cyan_leave_board');
    isBoardOwner = _lib.lookupFunction<CyanIsBoardOwnerNative, CyanIsBoardOwnerDart>('cyan_is_board_owner');
    getAllBoards = _lib.lookupFunction<CyanGetAllBoardsNative, CyanGetAllBoardsDart>('cyan_get_all_boards');
    getBoardsForGroup = _lib.lookupFunction<CyanGetBoardsForGroupNative, CyanGetBoardsForGroupDart>('cyan_get_boards_for_group');
    getBoardsForWorkspace = _lib.lookupFunction<CyanGetBoardsForWorkspaceNative, CyanGetBoardsForWorkspaceDart>('cyan_get_boards_for_workspace');
    getBoardMode = _lib.lookupFunction<CyanGetBoardModeNative, CyanGetBoardModeDart>('cyan_get_board_mode');
    setBoardMode = _lib.lookupFunction<CyanSetBoardModeNative, CyanSetBoardModeDart>('cyan_set_board_mode');
    isBoardPinned = _lib.lookupFunction<CyanIsBoardPinnedNative, CyanIsBoardPinnedDart>('cyan_is_board_pinned');
    pinBoard = _lib.lookupFunction<CyanPinBoardNative, CyanPinBoardDart>('cyan_pin_board');
    unpinBoard = _lib.lookupFunction<CyanUnpinBoardNative, CyanUnpinBoardDart>('cyan_unpin_board');
    rateBoard = _lib.lookupFunction<CyanRateBoardNative, CyanRateBoardDart>('cyan_rate_board');
    recordBoardView = _lib.lookupFunction<CyanRecordBoardViewNative, CyanRecordBoardViewDart>('cyan_record_board_view');
    
    // Board Metadata
    getBoardMetadata = _lib.lookupFunction<CyanGetBoardMetadataNative, CyanGetBoardMetadataDart>('cyan_get_board_metadata');
    getBoardsMetadata = _lib.lookupFunction<CyanGetBoardsMetadataNative, CyanGetBoardsMetadataDart>('cyan_get_boards_metadata');
    getTopBoards = _lib.lookupFunction<CyanGetTopBoardsNative, CyanGetTopBoardsDart>('cyan_get_top_boards');
    getBoardLink = _lib.lookupFunction<CyanGetBoardLinkNative, CyanGetBoardLinkDart>('cyan_get_board_link');
    searchBoardsByLabel = _lib.lookupFunction<CyanSearchBoardsByLabelNative, CyanSearchBoardsByLabelDart>('cyan_search_boards_by_label');
    setBoardLabels = _lib.lookupFunction<CyanSetBoardLabelsNative, CyanSetBoardLabelsDart>('cyan_set_board_labels');
    addBoardLabel = _lib.lookupFunction<CyanAddBoardLabelNative, CyanAddBoardLabelDart>('cyan_add_board_label');
    removeBoardLabel = _lib.lookupFunction<CyanRemoveBoardLabelNative, CyanRemoveBoardLabelDart>('cyan_remove_board_label');
    setBoardModel = _lib.lookupFunction<CyanSetBoardModelNative, CyanSetBoardModelDart>('cyan_set_board_model');
    setBoardSkills = _lib.lookupFunction<CyanSetBoardSkillsNative, CyanSetBoardSkillsDart>('cyan_set_board_skills');
    
    // Peers
    getGroupPeers = _lib.lookupFunction<CyanGetGroupPeersNative, CyanGetGroupPeersDart>('cyan_get_group_peers');
    getAllPeers = _lib.lookupFunction<CyanGetAllPeersNative, CyanGetAllPeersDart>('cyan_get_all_peers');
    updatePeerStatus = _lib.lookupFunction<CyanUpdatePeerStatusNative, CyanUpdatePeerStatusDart>('cyan_update_peer_status');
    
    // Profile
    getUserProfile = _lib.lookupFunction<CyanGetUserProfileNative, CyanGetUserProfileDart>('cyan_get_user_profile');
    getProfilesBatch = _lib.lookupFunction<CyanGetProfilesBatchNative, CyanGetProfilesBatchDart>('cyan_get_profiles_batch');
    
    // Chat
    sendChat = _lib.lookupFunction<CyanSendChatNative, CyanSendChatDart>('cyan_send_chat');
    deleteChat = _lib.lookupFunction<CyanDeleteChatNative, CyanDeleteChatDart>('cyan_delete_chat');
    startDirectChat = _lib.lookupFunction<CyanStartDirectChatNative, CyanStartDirectChatDart>('cyan_start_direct_chat');
    sendDirectChat = _lib.lookupFunction<CyanSendDirectChatNative, CyanSendDirectChatDart>('cyan_send_direct_chat');
    
    // Files
    uploadFile = _lib.lookupFunction<CyanUploadFileNative, CyanUploadFileDart>('cyan_upload_file');
    uploadFileToGroup = _lib.lookupFunction<CyanUploadFileToGroupNative, CyanUploadFileToGroupDart>('cyan_upload_file_to_group');
    uploadFileToWorkspace = _lib.lookupFunction<CyanUploadFileToWorkspaceNative, CyanUploadFileToWorkspaceDart>('cyan_upload_file_to_workspace');
    requestFileDownload = _lib.lookupFunction<CyanRequestFileDownloadNative, CyanRequestFileDownloadDart>('cyan_request_file_download');
    getFileStatus = _lib.lookupFunction<CyanGetFileStatusNative, CyanGetFileStatusDart>('cyan_get_file_status');
    getFiles = _lib.lookupFunction<CyanGetFilesNative, CyanGetFilesDart>('cyan_get_files');
    getFileLocalPath = _lib.lookupFunction<CyanGetFileLocalPathNative, CyanGetFileLocalPathDart>('cyan_get_file_local_path');
    
    // Whiteboard
    loadWhiteboardElements = _lib.lookupFunction<CyanLoadWhiteboardElementsNative, CyanLoadWhiteboardElementsDart>('cyan_load_whiteboard_elements');
    saveWhiteboardElement = _lib.lookupFunction<CyanSaveWhiteboardElementNative, CyanSaveWhiteboardElementDart>('cyan_save_whiteboard_element');
    deleteWhiteboardElement = _lib.lookupFunction<CyanDeleteWhiteboardElementNative, CyanDeleteWhiteboardElementDart>('cyan_delete_whiteboard_element');
    clearWhiteboard = _lib.lookupFunction<CyanClearWhiteboardNative, CyanClearWhiteboardDart>('cyan_clear_whiteboard');
    getWhiteboardElementCount = _lib.lookupFunction<CyanGetWhiteboardElementCountNative, CyanGetWhiteboardElementCountDart>('cyan_get_whiteboard_element_count');
    
    // Notebook
    loadNotebookCells = _lib.lookupFunction<CyanLoadNotebookCellsNative, CyanLoadNotebookCellsDart>('cyan_load_notebook_cells');
    saveNotebookCell = _lib.lookupFunction<CyanSaveNotebookCellNative, CyanSaveNotebookCellDart>('cyan_save_notebook_cell');
    deleteNotebookCell = _lib.lookupFunction<CyanDeleteNotebookCellNative, CyanDeleteNotebookCellDart>('cyan_delete_notebook_cell');
    reorderNotebookCells = _lib.lookupFunction<CyanReorderNotebookCellsNative, CyanReorderNotebookCellsDart>('cyan_reorder_notebook_cells');
    loadCellElements = _lib.lookupFunction<CyanLoadCellElementsNative, CyanLoadCellElementsDart>('cyan_load_cell_elements');
    
    // Integration
    integrationCommand = _lib.lookupFunction<CyanIntegrationCommandNative, CyanIntegrationCommandDart>('cyan_integration_command');
    pollIntegrationEvents = _lib.lookupFunction<CyanPollIntegrationEventsNative, CyanPollIntegrationEventsDart>('cyan_poll_integration_events');
    getConnectedIntegrations = _lib.lookupFunction<CyanGetConnectedIntegrationsNative, CyanGetConnectedIntegrationsDart>('cyan_get_connected_integrations');
    getIntegrationGraph = _lib.lookupFunction<CyanGetIntegrationGraphNative, CyanGetIntegrationGraphDart>('cyan_get_integration_graph');
    setGraphFocus = _lib.lookupFunction<CyanSetGraphFocusNative, CyanSetGraphFocusDart>('cyan_set_graph_focus');
    
    // AI
    aiCommand = _lib.lookupFunction<CyanAiCommandNative, CyanAiCommandDart>('cyan_ai_command');
    pollAiResponse = _lib.lookupFunction<CyanPollAiResponseNative, CyanPollAiResponseDart>('cyan_poll_ai_response');
    pollAiInsights = _lib.lookupFunction<CyanPollAiInsightsNative, CyanPollAiInsightsDart>('cyan_poll_ai_insights');
  }
  
  /// All no-ops with exact type signatures matching the typedefs
  void _setNoOps() {
    // Lifecycle
    init = (Pointer<Utf8> p) => false;
    initWithIdentity = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c, Pointer<Utf8> d) => false;
    setDataDir = (Pointer<Utf8> p) => false;
    setDiscoveryKey = (Pointer<Utf8> p) => false;
    isReady = () => false;
    freeString = (Pointer<Utf8> p) {};
    
    // Identity
    getNodeId = () => _nullptr;
    getXaeroId = () => _nullptr;
    setXaeroId = (Pointer<Utf8> p) => false;
    generateIdentityJson = () => _nullptr;
    deriveIdentity = (Pointer<Utf8> p) => _nullptr;
    getMyNodeId = () => _nullptr;
    getMyProfile = () => _nullptr;
    setMyProfile = (Pointer<Utf8> p) => false;
    
    // Command/Event
    sendCommand = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    pollEvents = (Pointer<Utf8> p) => _nullptr;
    seedDemoIfEmpty = () => false;
    
    // Stats
    getObjectCount = () => 0;
    getTotalPeerCount = () => 0;
    getGroupPeerCount = (Pointer<Utf8> p) => 0;
    
    // Groups
    createGroup = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c) {};
    renameGroup = (Pointer<Utf8> a, Pointer<Utf8> b) {};
    deleteGroup = (Pointer<Utf8> p) {};
    leaveGroup = (Pointer<Utf8> p) {};
    isGroupOwner = (Pointer<Utf8> p) => false;
    
    // Workspaces
    createWorkspace = (Pointer<Utf8> a, Pointer<Utf8> b) {};
    renameWorkspace = (Pointer<Utf8> a, Pointer<Utf8> b) {};
    deleteWorkspace = (Pointer<Utf8> p) {};
    leaveWorkspace = (Pointer<Utf8> p) {};
    isWorkspaceOwner = (Pointer<Utf8> p) => false;
    getWorkspacesForGroup = (Pointer<Utf8> p) => _nullptr;
    
    // Boards
    createBoard = (Pointer<Utf8> a, Pointer<Utf8> b) {};
    renameBoard = (Pointer<Utf8> a, Pointer<Utf8> b) {};
    deleteBoard = (Pointer<Utf8> p) {};
    leaveBoard = (Pointer<Utf8> p) {};
    isBoardOwner = (Pointer<Utf8> p) => false;
    getAllBoards = () => _nullptr;
    getBoardsForGroup = (Pointer<Utf8> p) => _nullptr;
    getBoardsForWorkspace = (Pointer<Utf8> p) => _nullptr;
    getBoardMode = (Pointer<Utf8> p) => _nullptr;
    setBoardMode = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    isBoardPinned = (Pointer<Utf8> p) => false;
    pinBoard = (Pointer<Utf8> p) => false;
    unpinBoard = (Pointer<Utf8> p) => false;
    rateBoard = (Pointer<Utf8> a, int b) => false;
    recordBoardView = (Pointer<Utf8> p) => false;
    
    // Board Metadata
    getBoardMetadata = (Pointer<Utf8> p) => _nullptr;
    getBoardsMetadata = (Pointer<Utf8> p) => _nullptr;
    getTopBoards = (int n) => _nullptr;
    getBoardLink = (Pointer<Utf8> p) => _nullptr;
    searchBoardsByLabel = (Pointer<Utf8> p) => _nullptr;
    setBoardLabels = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    addBoardLabel = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    removeBoardLabel = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    setBoardModel = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    setBoardSkills = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    
    // Peers
    getGroupPeers = (Pointer<Utf8> p) => _nullptr;
    getAllPeers = () => _nullptr;
    updatePeerStatus = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    
    // Profile
    getUserProfile = (Pointer<Utf8> p) => _nullptr;
    getProfilesBatch = (Pointer<Utf8> p) => _nullptr;
    
    // Chat
    sendChat = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c) {};
    deleteChat = (Pointer<Utf8> p) {};
    startDirectChat = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    sendDirectChat = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    
    // Files
    uploadFile = (Pointer<Utf8> a, Pointer<Utf8> b) => _nullptr;
    uploadFileToGroup = (Pointer<Utf8> a, Pointer<Utf8> b) => _nullptr;
    uploadFileToWorkspace = (Pointer<Utf8> a, Pointer<Utf8> b) => _nullptr;
    requestFileDownload = (Pointer<Utf8> p) => false;
    getFileStatus = (Pointer<Utf8> p) => _nullptr;
    getFiles = (Pointer<Utf8> p) => _nullptr;
    getFileLocalPath = (Pointer<Utf8> p) => _nullptr;
    
    // Whiteboard
    loadWhiteboardElements = (Pointer<Utf8> p) => _nullptr;
    saveWhiteboardElement = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    deleteWhiteboardElement = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    clearWhiteboard = (Pointer<Utf8> p) => false;
    getWhiteboardElementCount = (Pointer<Utf8> p) => 0;
    
    // Notebook
    loadNotebookCells = (Pointer<Utf8> p) => _nullptr;
    saveNotebookCell = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    deleteNotebookCell = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    reorderNotebookCells = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    loadCellElements = (Pointer<Utf8> p) => _nullptr;
    
    // Integration
    integrationCommand = (Pointer<Utf8> p) => false;
    pollIntegrationEvents = () => _nullptr;
    getConnectedIntegrations = (Pointer<Utf8> p) => _nullptr;
    getIntegrationGraph = (Pointer<Utf8> p) => _nullptr;
    setGraphFocus = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    
    // AI
    aiCommand = (Pointer<Utf8> p) => false;
    pollAiResponse = () => _nullptr;
    pollAiInsights = () => _nullptr;
  }
}
