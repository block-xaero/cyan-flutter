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
  
  void _load() {
    _lib = _loadLibrary();
    _bindFunctions();
  }
  
  DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libcyan_backend.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      // Static library linked at build time
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('cyan_backend.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libcyan_backend.so');
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
  }
  
  void _bindFunctions() {
    // Lifecycle
    init = _lib.lookup<NativeFunction<CyanInitNative>>('cyan_init').asFunction();
    initWithIdentity = _lib.lookup<NativeFunction<CyanInitWithIdentityNative>>('cyan_init_with_identity').asFunction();
    setDataDir = _lib.lookup<NativeFunction<CyanSetDataDirNative>>('cyan_set_data_dir').asFunction();
    setDiscoveryKey = _lib.lookup<NativeFunction<CyanSetDiscoveryKeyNative>>('cyan_set_discovery_key').asFunction();
    isReady = _lib.lookup<NativeFunction<CyanIsReadyNative>>('cyan_is_ready').asFunction();
    freeString = _lib.lookup<NativeFunction<CyanFreeStringNative>>('cyan_free_string').asFunction();
    
    // Identity
    getNodeId = _lib.lookup<NativeFunction<CyanGetNodeIdNative>>('cyan_get_node_id').asFunction();
    getXaeroId = _lib.lookup<NativeFunction<CyanGetXaeroIdNative>>('cyan_get_xaero_id').asFunction();
    setXaeroId = _lib.lookup<NativeFunction<CyanSetXaeroIdNative>>('cyan_set_xaero_id').asFunction();
    getMyNodeId = _lib.lookup<NativeFunction<CyanGetMyNodeIdNative>>('cyan_get_my_node_id').asFunction();
    getMyProfile = _lib.lookup<NativeFunction<CyanGetMyProfileNative>>('cyan_get_my_profile').asFunction();
    setMyProfile = _lib.lookup<NativeFunction<CyanSetMyProfileNative>>('cyan_set_my_profile').asFunction();
    
    // Command/Event
    sendCommand = _lib.lookup<NativeFunction<CyanSendCommandNative>>('cyan_send_command').asFunction();
    pollEvents = _lib.lookup<NativeFunction<CyanPollEventsNative>>('cyan_poll_events').asFunction();
    seedDemoIfEmpty = _lib.lookup<NativeFunction<CyanSeedDemoIfEmptyNative>>('cyan_seed_demo_if_empty').asFunction();
    
    // Stats
    getObjectCount = _lib.lookup<NativeFunction<CyanGetObjectCountNative>>('cyan_get_object_count').asFunction();
    getTotalPeerCount = _lib.lookup<NativeFunction<CyanGetTotalPeerCountNative>>('cyan_get_total_peer_count').asFunction();
    getGroupPeerCount = _lib.lookup<NativeFunction<CyanGetGroupPeerCountNative>>('cyan_get_group_peer_count').asFunction();
    
    // Groups
    createGroup = _lib.lookup<NativeFunction<CyanCreateGroupNative>>('cyan_create_group').asFunction();
    renameGroup = _lib.lookup<NativeFunction<CyanRenameGroupNative>>('cyan_rename_group').asFunction();
    deleteGroup = _lib.lookup<NativeFunction<CyanDeleteGroupNative>>('cyan_delete_group').asFunction();
    leaveGroup = _lib.lookup<NativeFunction<CyanLeaveGroupNative>>('cyan_leave_group').asFunction();
    isGroupOwner = _lib.lookup<NativeFunction<CyanIsGroupOwnerNative>>('cyan_is_group_owner').asFunction();
    
    // Workspaces
    createWorkspace = _lib.lookup<NativeFunction<CyanCreateWorkspaceNative>>('cyan_create_workspace').asFunction();
    renameWorkspace = _lib.lookup<NativeFunction<CyanRenameWorkspaceNative>>('cyan_rename_workspace').asFunction();
    deleteWorkspace = _lib.lookup<NativeFunction<CyanDeleteWorkspaceNative>>('cyan_delete_workspace').asFunction();
    leaveWorkspace = _lib.lookup<NativeFunction<CyanLeaveWorkspaceNative>>('cyan_leave_workspace').asFunction();
    isWorkspaceOwner = _lib.lookup<NativeFunction<CyanIsWorkspaceOwnerNative>>('cyan_is_workspace_owner').asFunction();
    getWorkspacesForGroup = _lib.lookup<NativeFunction<CyanGetWorkspacesForGroupNative>>('cyan_get_workspaces_for_group').asFunction();
    
    // Boards
    createBoard = _lib.lookup<NativeFunction<CyanCreateBoardNative>>('cyan_create_board').asFunction();
    renameBoard = _lib.lookup<NativeFunction<CyanRenameBoardNative>>('cyan_rename_board').asFunction();
    deleteBoard = _lib.lookup<NativeFunction<CyanDeleteBoardNative>>('cyan_delete_board').asFunction();
    leaveBoard = _lib.lookup<NativeFunction<CyanLeaveBoardNative>>('cyan_leave_board').asFunction();
    isBoardOwner = _lib.lookup<NativeFunction<CyanIsBoardOwnerNative>>('cyan_is_board_owner').asFunction();
    getAllBoards = _lib.lookup<NativeFunction<CyanGetAllBoardsNative>>('cyan_get_all_boards').asFunction();
    getBoardsForGroup = _lib.lookup<NativeFunction<CyanGetBoardsForGroupNative>>('cyan_get_boards_for_group').asFunction();
    getBoardsForWorkspace = _lib.lookup<NativeFunction<CyanGetBoardsForWorkspaceNative>>('cyan_get_boards_for_workspace').asFunction();
    getBoardMode = _lib.lookup<NativeFunction<CyanGetBoardModeNative>>('cyan_get_board_mode').asFunction();
    setBoardMode = _lib.lookup<NativeFunction<CyanSetBoardModeNative>>('cyan_set_board_mode').asFunction();
    isBoardPinned = _lib.lookup<NativeFunction<CyanIsBoardPinnedNative>>('cyan_is_board_pinned').asFunction();
    pinBoard = _lib.lookup<NativeFunction<CyanPinBoardNative>>('cyan_pin_board').asFunction();
    unpinBoard = _lib.lookup<NativeFunction<CyanUnpinBoardNative>>('cyan_unpin_board').asFunction();
    rateBoard = _lib.lookup<NativeFunction<CyanRateBoardNative>>('cyan_rate_board').asFunction();
    recordBoardView = _lib.lookup<NativeFunction<CyanRecordBoardViewNative>>('cyan_record_board_view').asFunction();
    
    // Board Metadata
    getBoardMetadata = _lib.lookup<NativeFunction<CyanGetBoardMetadataNative>>('cyan_get_board_metadata').asFunction();
    getBoardsMetadata = _lib.lookup<NativeFunction<CyanGetBoardsMetadataNative>>('cyan_get_boards_metadata').asFunction();
    getTopBoards = _lib.lookup<NativeFunction<CyanGetTopBoardsNative>>('cyan_get_top_boards').asFunction();
    getBoardLink = _lib.lookup<NativeFunction<CyanGetBoardLinkNative>>('cyan_get_board_link').asFunction();
    searchBoardsByLabel = _lib.lookup<NativeFunction<CyanSearchBoardsByLabelNative>>('cyan_search_boards_by_label').asFunction();
    setBoardLabels = _lib.lookup<NativeFunction<CyanSetBoardLabelsNative>>('cyan_set_board_labels').asFunction();
    addBoardLabel = _lib.lookup<NativeFunction<CyanAddBoardLabelNative>>('cyan_add_board_label').asFunction();
    removeBoardLabel = _lib.lookup<NativeFunction<CyanRemoveBoardLabelNative>>('cyan_remove_board_label').asFunction();
    setBoardModel = _lib.lookup<NativeFunction<CyanSetBoardModelNative>>('cyan_set_board_model').asFunction();
    setBoardSkills = _lib.lookup<NativeFunction<CyanSetBoardSkillsNative>>('cyan_set_board_skills').asFunction();
    
    // Peers
    getGroupPeers = _lib.lookup<NativeFunction<CyanGetGroupPeersNative>>('cyan_get_group_peers').asFunction();
    getAllPeers = _lib.lookup<NativeFunction<CyanGetAllPeersNative>>('cyan_get_all_peers').asFunction();
    updatePeerStatus = _lib.lookup<NativeFunction<CyanUpdatePeerStatusNative>>('cyan_update_peer_status').asFunction();
    
    // Profile
    getUserProfile = _lib.lookup<NativeFunction<CyanGetUserProfileNative>>('cyan_get_user_profile').asFunction();
    getProfilesBatch = _lib.lookup<NativeFunction<CyanGetProfilesBatchNative>>('cyan_get_profiles_batch').asFunction();
    
    // Chat
    sendChat = _lib.lookup<NativeFunction<CyanSendChatNative>>('cyan_send_chat').asFunction();
    deleteChat = _lib.lookup<NativeFunction<CyanDeleteChatNative>>('cyan_delete_chat').asFunction();
    startDirectChat = _lib.lookup<NativeFunction<CyanStartDirectChatNative>>('cyan_start_direct_chat').asFunction();
    sendDirectChat = _lib.lookup<NativeFunction<CyanSendDirectChatNative>>('cyan_send_direct_chat').asFunction();
    
    // Files
    uploadFile = _lib.lookup<NativeFunction<CyanUploadFileNative>>('cyan_upload_file').asFunction();
    uploadFileToGroup = _lib.lookup<NativeFunction<CyanUploadFileToGroupNative>>('cyan_upload_file_to_group').asFunction();
    uploadFileToWorkspace = _lib.lookup<NativeFunction<CyanUploadFileToWorkspaceNative>>('cyan_upload_file_to_workspace').asFunction();
    requestFileDownload = _lib.lookup<NativeFunction<CyanRequestFileDownloadNative>>('cyan_request_file_download').asFunction();
    getFileStatus = _lib.lookup<NativeFunction<CyanGetFileStatusNative>>('cyan_get_file_status').asFunction();
    getFiles = _lib.lookup<NativeFunction<CyanGetFilesNative>>('cyan_get_files').asFunction();
    getFileLocalPath = _lib.lookup<NativeFunction<CyanGetFileLocalPathNative>>('cyan_get_file_local_path').asFunction();
    
    // Whiteboard
    loadWhiteboardElements = _lib.lookup<NativeFunction<CyanLoadWhiteboardElementsNative>>('cyan_load_whiteboard_elements').asFunction();
    saveWhiteboardElement = _lib.lookup<NativeFunction<CyanSaveWhiteboardElementNative>>('cyan_save_whiteboard_element').asFunction();
    deleteWhiteboardElement = _lib.lookup<NativeFunction<CyanDeleteWhiteboardElementNative>>('cyan_delete_whiteboard_element').asFunction();
    clearWhiteboard = _lib.lookup<NativeFunction<CyanClearWhiteboardNative>>('cyan_clear_whiteboard').asFunction();
    getWhiteboardElementCount = _lib.lookup<NativeFunction<CyanGetWhiteboardElementCountNative>>('cyan_get_whiteboard_element_count').asFunction();
    
    // Notebook
    loadNotebookCells = _lib.lookup<NativeFunction<CyanLoadNotebookCellsNative>>('cyan_load_notebook_cells').asFunction();
    saveNotebookCell = _lib.lookup<NativeFunction<CyanSaveNotebookCellNative>>('cyan_save_notebook_cell').asFunction();
    deleteNotebookCell = _lib.lookup<NativeFunction<CyanDeleteNotebookCellNative>>('cyan_delete_notebook_cell').asFunction();
    reorderNotebookCells = _lib.lookup<NativeFunction<CyanReorderNotebookCellsNative>>('cyan_reorder_notebook_cells').asFunction();
    loadCellElements = _lib.lookup<NativeFunction<CyanLoadCellElementsNative>>('cyan_load_cell_elements').asFunction();
    
    // Integration
    integrationCommand = _lib.lookup<NativeFunction<CyanIntegrationCommandNative>>('cyan_integration_command').asFunction();
    pollIntegrationEvents = _lib.lookup<NativeFunction<CyanPollIntegrationEventsNative>>('cyan_poll_integration_events').asFunction();
    getConnectedIntegrations = _lib.lookup<NativeFunction<CyanGetConnectedIntegrationsDart>>('cyan_get_connected_integrations').asFunction();
    getIntegrationGraph = _lib.lookup<NativeFunction<CyanGetIntegrationGraphNative>>('cyan_get_integration_graph').asFunction();
    setGraphFocus = _lib.lookup<NativeFunction<CyanSetGraphFocusNative>>('cyan_set_graph_focus').asFunction();
    
    // AI
    aiCommand = _lib.lookup<NativeFunction<CyanAiCommandNative>>('cyan_ai_command').asFunction();
    pollAiResponse = _lib.lookup<NativeFunction<CyanPollAiResponseNative>>('cyan_poll_ai_response').asFunction();
    pollAiInsights = _lib.lookup<NativeFunction<CyanPollAiInsightsNative>>('cyan_poll_ai_insights').asFunction();
  }
}
