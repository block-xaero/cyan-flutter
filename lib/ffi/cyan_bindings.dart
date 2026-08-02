// ffi/cyan_bindings.dart
// Complete FFI bindings for all 87 cyan_* functions
// Generated from: nm -gU libcyan_backend_macos.a | grep " T _cyan_"

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'cyan_engine_library.dart';

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

typedef CyanSetMyProfileNative = Bool Function(Pointer<Utf8> displayName, Pointer<Utf8> avatarPath);
typedef CyanSetMyProfileDart = bool Function(Pointer<Utf8> displayName, Pointer<Utf8> avatarPath);

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

// The pin flag as ONE verb (the engine queues it; nothing comes back), and the
// summary a lens promotes onto a board of its own.
typedef CyanPinSetNative = Void Function(Pointer<Utf8> boardId, Bool pinned);
typedef CyanPinSetDart = void Function(Pointer<Utf8> boardId, bool pinned);

typedef CyanPinSummaryAsBoardNative = Pointer<Utf8> Function(
  Pointer<Utf8> workspaceId, Pointer<Utf8> boardName,
  Pointer<Utf8> markdownContent);
typedef CyanPinSummaryAsBoardDart = Pointer<Utf8> Function(
  Pointer<Utf8> workspaceId, Pointer<Utf8> boardName,
  Pointer<Utf8> markdownContent);

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

typedef CyanLoadChatHistoryNative = Void Function(Pointer<Utf8> boardId);
typedef CyanLoadChatHistoryDart = void Function(Pointer<Utf8> boardId);

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

typedef CyanDeleteFileNative = Void Function(Pointer<Utf8> fileId);
typedef CyanDeleteFileDart = void Function(Pointer<Utf8> fileId);

typedef CyanResolveFileHandleNative = Pointer<Utf8> Function(
  Pointer<Utf8> groupId, Pointer<Utf8> workspaceId,
  Pointer<Utf8> boardId, Pointer<Utf8> fileName);
typedef CyanResolveFileHandleDart = Pointer<Utf8> Function(
  Pointer<Utf8> groupId, Pointer<Utf8> workspaceId,
  Pointer<Utf8> boardId, Pointer<Utf8> fileName);

typedef CyanExtractFileTextNative = Pointer<Utf8> Function(Pointer<Utf8> path);
typedef CyanExtractFileTextDart = Pointer<Utf8> Function(Pointer<Utf8> path);

// Unread / notifications
typedef CyanUnreadCountsNative = Pointer<Utf8> Function();
typedef CyanUnreadCountsDart = Pointer<Utf8> Function();

typedef CyanMarkReadNative = Void Function(Pointer<Utf8> scopeId);
typedef CyanMarkReadDart = void Function(Pointer<Utf8> scopeId);

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

// Pipeline (compile / run / gate)
typedef CyanPipelineCompileNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanPipelineCompileDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanRunPipelineNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanRunPipelineDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanPipelineStatusNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanPipelineStatusDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanPipelineApproveNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> stepId);
typedef CyanPipelineApproveDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> stepId);

typedef CyanPipelineApproveAsNative = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> stepId, Pointer<Utf8> reviewer);
typedef CyanPipelineApproveAsDart = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> stepId, Pointer<Utf8> reviewer);

typedef CyanPipelineRejectNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> stepId);
typedef CyanPipelineRejectDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> stepId);

typedef CyanPipelineRejectAsNative = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> stepId, Pointer<Utf8> reviewer);
typedef CyanPipelineRejectAsDart = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> stepId, Pointer<Utf8> reviewer);

typedef CyanPipelineRetryNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> stepId);
typedef CyanPipelineRetryDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> stepId);

typedef CyanPipelineResetNative = Bool Function(Pointer<Utf8> boardId);
typedef CyanPipelineResetDart = bool Function(Pointer<Utf8> boardId);

typedef CyanPipelineResetStepNative = Bool Function(Pointer<Utf8> boardId, Pointer<Utf8> stepId);
typedef CyanPipelineResetStepDart = bool Function(Pointer<Utf8> boardId, Pointer<Utf8> stepId);

typedef CyanPipelineRunStepLocalNative = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> stepId);
typedef CyanPipelineRunStepLocalDart = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> stepId);

typedef CyanStepEditTravelNative = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> cellId, Int32 direction);
typedef CyanStepEditTravelDart = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> cellId, int direction);

typedef CyanBoardWorkflowStateNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanBoardWorkflowStateDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

// Identity + device prefs
typedef CyanBuildCommitNative = Pointer<Utf8> Function();
typedef CyanBuildCommitDart = Pointer<Utf8> Function();

typedef CyanDeleteIdentityNative = Bool Function();
typedef CyanDeleteIdentityDart = bool Function();

typedef CyanGetProductionRoleNative = Pointer<Utf8> Function();
typedef CyanGetProductionRoleDart = Pointer<Utf8> Function();

typedef CyanSetProductionRoleNative = Bool Function(Pointer<Utf8> role);
typedef CyanSetProductionRoleDart = bool Function(Pointer<Utf8> role);

typedef CyanSelectorResolveNative = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> role, Pointer<Utf8> formatType);
typedef CyanSelectorResolveDart = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> role, Pointer<Utf8> formatType);

typedef CyanFriendlyNodeIdNative = Pointer<Utf8> Function(Pointer<Utf8> nodeId);
typedef CyanFriendlyNodeIdDart = Pointer<Utf8> Function(Pointer<Utf8> nodeId);

// SSO session grants: the install carries the broker token plus the trust
// material it must verify against; the sign-out takes nothing and answers
// nothing (the engine clears its own process-global session).
typedef CyanSsoInstallGrantNative = Pointer<Utf8> Function(
  Pointer<Utf8> grantToken, Pointer<Utf8> trustJson);
typedef CyanSsoInstallGrantDart = Pointer<Utf8> Function(
  Pointer<Utf8> grantToken, Pointer<Utf8> trustJson);

typedef CyanSsoSignOutNative = Void Function();
typedef CyanSsoSignOutDart = void Function();

// Anonymous sessions
typedef CyanCreateAnonymousSessionNative = Pointer<Utf8> Function(Pointer<Utf8> scopeId);
typedef CyanCreateAnonymousSessionDart = Pointer<Utf8> Function(Pointer<Utf8> scopeId);

typedef CyanRevealAnonymousIdentityNative = Pointer<Utf8> Function(Pointer<Utf8> scopeId);
typedef CyanRevealAnonymousIdentityDart = Pointer<Utf8> Function(Pointer<Utf8> scopeId);

typedef CyanGetAnonymousStatusNative = Pointer<Utf8> Function(Pointer<Utf8> scopeId);
typedef CyanGetAnonymousStatusDart = Pointer<Utf8> Function(Pointer<Utf8> scopeId);

typedef CyanExitAnonymousModeNative = Bool Function(Pointer<Utf8> scopeId);
typedef CyanExitAnonymousModeDart = bool Function(Pointer<Utf8> scopeId);

// Groups: roster, grants, portable bundles
typedef CyanGetGroupMembersNative = Pointer<Utf8> Function(Pointer<Utf8> groupId);
typedef CyanGetGroupMembersDart = Pointer<Utf8> Function(Pointer<Utf8> groupId);

typedef CyanIssueGrantQrNative = Pointer<Utf8> Function(
  Pointer<Utf8> groupId, Pointer<Utf8> role, Uint64 ttlSeconds);
typedef CyanIssueGrantQrDart = Pointer<Utf8> Function(
  Pointer<Utf8> groupId, Pointer<Utf8> role, int ttlSeconds);

typedef CyanScanGrantQrNative = Pointer<Utf8> Function(Pointer<Utf8> qrPayload);
typedef CyanScanGrantQrDart = Pointer<Utf8> Function(Pointer<Utf8> qrPayload);

typedef CyanBundlePubkeyNative = Pointer<Utf8> Function();
typedef CyanBundlePubkeyDart = Pointer<Utf8> Function();

typedef CyanExportGroupNative = Pointer<Utf8> Function(
  Pointer<Utf8> groupId, Pointer<Utf8> inviteePubkey);
typedef CyanExportGroupDart = Pointer<Utf8> Function(
  Pointer<Utf8> groupId, Pointer<Utf8> inviteePubkey);

typedef CyanImportGroupNative = Pointer<Utf8> Function(Pointer<Utf8> bundle);
typedef CyanImportGroupDart = Pointer<Utf8> Function(Pointer<Utf8> bundle);

// Board notes (the unscoped CRUD the review rail writes through)
typedef CyanNoteListNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanNoteListDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanNotePutNative = Void Function(
  Pointer<Utf8> boardId, Pointer<Utf8> noteId, Pointer<Utf8> tenantId,
  Pointer<Utf8> text);
typedef CyanNotePutDart = void Function(
  Pointer<Utf8> boardId, Pointer<Utf8> noteId, Pointer<Utf8> tenantId,
  Pointer<Utf8> text);

typedef CyanNoteDeleteNative = Void Function(Pointer<Utf8> id);
typedef CyanNoteDeleteDart = void Function(Pointer<Utf8> id);

// Timecoded notes (review rail): the whole note travels as JSON both ways
typedef CyanSaveTimecodeNoteNative = Bool Function(Pointer<Utf8> noteJson);
typedef CyanSaveTimecodeNoteDart = bool Function(Pointer<Utf8> noteJson);

typedef CyanLoadTimecodeNotesNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanLoadTimecodeNotesDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanActOnTimecodeNoteNative = Pointer<Utf8> Function(Pointer<Utf8> noteJson);
typedef CyanActOnTimecodeNoteDart = Pointer<Utf8> Function(Pointer<Utf8> noteJson);

// The same rail exported as a markdown timeline — raw markdown, not JSON
typedef CyanExportNotesMarkdownNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanExportNotesMarkdownDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

// Scoped notes + the constitution chain they feed
typedef CyanNoteListScopedNative = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> scope, Pointer<Utf8> kind);
typedef CyanNoteListScopedDart = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> scope, Pointer<Utf8> kind);

typedef CyanNotePutScopedNative = Void Function(
  Pointer<Utf8> boardId, Pointer<Utf8> noteId, Pointer<Utf8> tenantId,
  Pointer<Utf8> text, Pointer<Utf8> scope, Pointer<Utf8> kind);
typedef CyanNotePutScopedDart = void Function(
  Pointer<Utf8> boardId, Pointer<Utf8> noteId, Pointer<Utf8> tenantId,
  Pointer<Utf8> text, Pointer<Utf8> scope, Pointer<Utf8> kind);

typedef CyanConstitutionResolvedNative = Pointer<Utf8> Function(Pointer<Utf8> requestJson);
typedef CyanConstitutionResolvedDart = Pointer<Utf8> Function(Pointer<Utf8> requestJson);

typedef CyanConstitutionEffectiveNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanConstitutionEffectiveDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

// Templates + the workflows cloned from them
typedef CyanTemplateListNative = Pointer<Utf8> Function(Pointer<Utf8> tenantId);
typedef CyanTemplateListDart = Pointer<Utf8> Function(Pointer<Utf8> tenantId);

typedef CyanWorkflowFromTemplateNative = Void Function(
  Pointer<Utf8> templateId, Pointer<Utf8> boardId, Pointer<Utf8> tenantId);
typedef CyanWorkflowFromTemplateDart = void Function(
  Pointer<Utf8> templateId, Pointer<Utf8> boardId, Pointer<Utf8> tenantId);

typedef CyanTemplateCloneOutcomeNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanTemplateCloneOutcomeDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanTemplateSaveNative = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> name,
  Pointer<Utf8> description, Pointer<Utf8> stepsJson);
typedef CyanTemplateSaveDart = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> name,
  Pointer<Utf8> description, Pointer<Utf8> stepsJson);

typedef CyanTemplateSaveFromBoardNative = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> name, Pointer<Utf8> description,
  Pointer<Utf8> stepsJson, Pointer<Utf8> boardId);
typedef CyanTemplateSaveFromBoardDart = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> name, Pointer<Utf8> description,
  Pointer<Utf8> stepsJson, Pointer<Utf8> boardId);

typedef CyanTemplateSaveV2Native = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> templateJson);
typedef CyanTemplateSaveV2Dart = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> templateJson);

typedef CyanWorkflowAutocompleteNative = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> partial);
typedef CyanWorkflowAutocompleteDart = Pointer<Utf8> Function(
  Pointer<Utf8> boardId, Pointer<Utf8> partial);

// Producer review: the assignee a gate waits on, the board's playable media,
// and the comment rail. The two command verbs take a whole JSON envelope.
typedef CyanBoardReviewAssigneeNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanBoardReviewAssigneeDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanBoardSetReviewAssigneeNative = Bool Function(
  Pointer<Utf8> boardId, Pointer<Utf8> user);
typedef CyanBoardSetReviewAssigneeDart = bool Function(
  Pointer<Utf8> boardId, Pointer<Utf8> user);

typedef CyanBoardVideoMediaNative = Pointer<Utf8> Function(Pointer<Utf8> boardId);
typedef CyanBoardVideoMediaDart = Pointer<Utf8> Function(Pointer<Utf8> boardId);

typedef CyanReviewAddCommentNative = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);
typedef CyanReviewAddCommentDart = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);

typedef CyanReviewCommandNative = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);
typedef CyanReviewCommandDart = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);

// Ingest: the watched-source sensors and the per-asset runs they materialize.
// One JSON envelope, like the review verb.
typedef CyanIngestCommandNative = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);
typedef CyanIngestCommandDart = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);

// Plugins: what this device has installed, and how a bundle lands. The install
// takes its three arguments positionally (the engine gates layout + signature
// before anything is written); the config pair takes a JSON envelope.
typedef CyanPluginCatalogNative = Pointer<Utf8> Function();
typedef CyanPluginCatalogDart = Pointer<Utf8> Function();

typedef CyanInstallPluginBundleNative = Pointer<Utf8> Function(
  Pointer<Utf8> groupId, Pointer<Utf8> pluginId, Pointer<Utf8> bundleBytesB64);
typedef CyanInstallPluginBundleDart = Pointer<Utf8> Function(
  Pointer<Utf8> groupId, Pointer<Utf8> pluginId, Pointer<Utf8> bundleBytesB64);

typedef CyanPluginConfigGetNative = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);
typedef CyanPluginConfigGetDart = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);

typedef CyanPluginConfigSetNative = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);
typedef CyanPluginConfigSetDart = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);

// ChangeList store: the content-addressed review-&-conform ledger. One JSON
// envelope, like the review and ingest verbs.
typedef CyanChangelistCommandNative = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);
typedef CyanChangelistCommandDart = Pointer<Utf8> Function(Pointer<Utf8> cmdJson);

// Lens command bar: the path completer that fires per keystroke, and the parser
// that answers a whole `/verb` line already partly executed.
typedef CyanAutocompletePathNative = Pointer<Utf8> Function(Pointer<Utf8> partial);
typedef CyanAutocompletePathDart = Pointer<Utf8> Function(Pointer<Utf8> partial);

typedef CyanParseLensCommandNative = Pointer<Utf8> Function(Pointer<Utf8> input);
typedef CyanParseLensCommandDart = Pointer<Utf8> Function(Pointer<Utf8> input);

// Demo seeding: the coherent demo set is queued on the command channel and
// acknowledged with nothing; the GATED persona cast answers a routing manifest.
typedef CyanSeedDemoNative = Void Function();
typedef CyanSeedDemoDart = void Function();

typedef CyanSeedPersonasNative = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> ownerNodeId);
typedef CyanSeedPersonasDart = Pointer<Utf8> Function(
  Pointer<Utf8> tenantId, Pointer<Utf8> ownerNodeId);


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
  late final CyanPinSetDart pinSet;
  late final CyanPinSummaryAsBoardDart pinSummaryAsBoard;
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
  late final CyanLoadChatHistoryDart loadChatHistory;
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
  late final CyanDeleteFileDart deleteFile;
  late final CyanResolveFileHandleDart resolveFileHandle;
  late final CyanExtractFileTextDart extractFileText;

  // Unread / notifications
  late final CyanUnreadCountsDart unreadCounts;
  late final CyanMarkReadDart markRead;

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

  // Pipeline
  late final CyanPipelineCompileDart pipelineCompile;
  late final CyanRunPipelineDart runPipeline;
  late final CyanPipelineStatusDart pipelineStatus;
  late final CyanPipelineApproveDart pipelineApprove;
  late final CyanPipelineApproveAsDart pipelineApproveAs;
  late final CyanPipelineRejectDart pipelineReject;
  late final CyanPipelineRejectAsDart pipelineRejectAs;
  late final CyanPipelineRetryDart pipelineRetry;
  late final CyanPipelineResetDart pipelineReset;
  late final CyanPipelineResetStepDart pipelineResetStep;
  late final CyanPipelineRunStepLocalDart pipelineRunStepLocal;
  late final CyanStepEditTravelDart stepEditTravel;
  late final CyanBoardWorkflowStateDart boardWorkflowState;

  // Identity + device prefs
  late final CyanBuildCommitDart buildCommit;
  late final CyanDeleteIdentityDart deleteIdentity;
  late final CyanGetProductionRoleDart getProductionRole;
  late final CyanSetProductionRoleDart setProductionRole;
  late final CyanSelectorResolveDart selectorResolve;
  late final CyanFriendlyNodeIdDart friendlyNodeId;
  late final CyanSsoInstallGrantDart ssoInstallGrant;
  late final CyanSsoSignOutDart ssoSignOut;

  // Anonymous sessions
  late final CyanCreateAnonymousSessionDart createAnonymousSession;
  late final CyanRevealAnonymousIdentityDart revealAnonymousIdentity;
  late final CyanGetAnonymousStatusDart getAnonymousStatus;
  late final CyanExitAnonymousModeDart exitAnonymousMode;

  // Groups
  late final CyanGetGroupMembersDart getGroupMembers;
  late final CyanIssueGrantQrDart issueGrantQr;
  late final CyanScanGrantQrDart scanGrantQr;
  late final CyanBundlePubkeyDart bundlePubkey;
  late final CyanExportGroupDart exportGroup;
  late final CyanImportGroupDart importGroup;

  // Board notes + timecoded review notes
  late final CyanNoteListDart noteList;
  late final CyanNotePutDart notePut;
  late final CyanNoteDeleteDart noteDelete;
  late final CyanSaveTimecodeNoteDart saveTimecodeNote;
  late final CyanLoadTimecodeNotesDart loadTimecodeNotes;
  late final CyanActOnTimecodeNoteDart actOnTimecodeNote;
  late final CyanExportNotesMarkdownDart exportNotesMarkdown;

  // Scoped notes + constitution
  late final CyanNoteListScopedDart noteListScoped;
  late final CyanNotePutScopedDart notePutScoped;
  late final CyanConstitutionResolvedDart constitutionResolved;
  late final CyanConstitutionEffectiveDart constitutionEffective;

  // Templates
  late final CyanTemplateListDart templateList;
  late final CyanWorkflowFromTemplateDart workflowFromTemplate;
  late final CyanTemplateCloneOutcomeDart templateCloneOutcome;
  late final CyanTemplateSaveDart templateSave;
  late final CyanTemplateSaveFromBoardDart templateSaveFromBoard;
  late final CyanTemplateSaveV2Dart templateSaveV2;
  late final CyanWorkflowAutocompleteDart workflowAutocomplete;

  // Producer review
  late final CyanBoardReviewAssigneeDart boardReviewAssignee;
  late final CyanBoardSetReviewAssigneeDart boardSetReviewAssignee;
  late final CyanBoardVideoMediaDart boardVideoMedia;
  late final CyanReviewAddCommentDart reviewAddComment;
  late final CyanReviewCommandDart reviewCommand;

  // Ingest
  late final CyanIngestCommandDart ingestCommand;

  // Plugins
  late final CyanPluginCatalogDart pluginCatalog;
  late final CyanInstallPluginBundleDart installPluginBundle;
  late final CyanPluginConfigGetDart pluginConfigGet;
  late final CyanPluginConfigSetDart pluginConfigSet;

  // ChangeList store
  late final CyanChangelistCommandDart changelistCommand;

  // Lens command bar
  late final CyanAutocompletePathDart autocompletePath;
  late final CyanParseLensCommandDart parseLensCommand;

  // Demo seeding
  late final CyanSeedDemoDart seedDemo;
  late final CyanSeedPersonasDart seedPersonas;

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
  
  // Walks the per-target plan from `CyanEngineLibrary` — Windows, Linux and
  // macOS all take this one path. There is no `else { throw }` arm: an OS with
  // no engine binary resolves to an empty candidate list and lands on the
  // process symbols, so the app entrypoint never aborts on a platform check.
  DynamicLibrary _loadLibrary() {
    final plan = CyanEngineLibrary.resolve(
      Platform.operatingSystem,
      home: Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '',
      resolvedExecutable: Platform.resolvedExecutable,
    );

    for (final path in plan.candidatePaths) {
      // A bare file name is resolved by the OS loader, not the filesystem, so
      // only existence-check the paths that actually name a location.
      final isPath = path.contains('/') || path.contains('\\');
      if (isPath && !File(path).existsSync()) continue;
      try {
        print('🔗 Loading engine: $path');
        return DynamicLibrary.open(path);
      } catch (e) {
        print('⚠️ Failed to open $path: $e');
      }
    }

    // Static lib linked into the binary (iOS/macOS xcframework), or nothing at
    // all — `_bindFunctions` falls back to no-ops when the symbols are absent.
    print('🔗 Falling back to DynamicLibrary.process()');
    return DynamicLibrary.process();
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
    pinSet = _lib.lookupFunction<CyanPinSetNative, CyanPinSetDart>('cyan_pin_set');
    pinSummaryAsBoard = _lib.lookupFunction<CyanPinSummaryAsBoardNative, CyanPinSummaryAsBoardDart>('cyan_pin_summary_as_board');
    rateBoard =_lib.lookupFunction<CyanRateBoardNative, CyanRateBoardDart>('cyan_rate_board');
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
    loadChatHistory = _lib.lookupFunction<CyanLoadChatHistoryNative, CyanLoadChatHistoryDart>('cyan_load_chat_history');
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
    deleteFile = _lib.lookupFunction<CyanDeleteFileNative, CyanDeleteFileDart>('cyan_delete_file');
    resolveFileHandle = _lib.lookupFunction<CyanResolveFileHandleNative, CyanResolveFileHandleDart>('cyan_resolve_file_handle');
    extractFileText = _lib.lookupFunction<CyanExtractFileTextNative, CyanExtractFileTextDart>('cyan_extract_file_text');

    // Unread / notifications
    unreadCounts = _lib.lookupFunction<CyanUnreadCountsNative, CyanUnreadCountsDart>('cyan_unread_counts');
    markRead = _lib.lookupFunction<CyanMarkReadNative, CyanMarkReadDart>('cyan_mark_read');

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

    // Pipeline
    pipelineCompile = _lib.lookupFunction<CyanPipelineCompileNative, CyanPipelineCompileDart>('cyan_pipeline_compile');
    runPipeline = _lib.lookupFunction<CyanRunPipelineNative, CyanRunPipelineDart>('cyan_run_pipeline');
    pipelineStatus = _lib.lookupFunction<CyanPipelineStatusNative, CyanPipelineStatusDart>('cyan_pipeline_status');
    pipelineApprove = _lib.lookupFunction<CyanPipelineApproveNative, CyanPipelineApproveDart>('cyan_pipeline_approve');
    pipelineApproveAs = _lib.lookupFunction<CyanPipelineApproveAsNative, CyanPipelineApproveAsDart>('cyan_pipeline_approve_as');
    pipelineReject = _lib.lookupFunction<CyanPipelineRejectNative, CyanPipelineRejectDart>('cyan_pipeline_reject');
    pipelineRejectAs = _lib.lookupFunction<CyanPipelineRejectAsNative, CyanPipelineRejectAsDart>('cyan_pipeline_reject_as');
    pipelineRetry = _lib.lookupFunction<CyanPipelineRetryNative, CyanPipelineRetryDart>('cyan_pipeline_retry');
    pipelineReset = _lib.lookupFunction<CyanPipelineResetNative, CyanPipelineResetDart>('cyan_pipeline_reset');
    pipelineResetStep = _lib.lookupFunction<CyanPipelineResetStepNative, CyanPipelineResetStepDart>('cyan_pipeline_reset_step');
    pipelineRunStepLocal = _lib.lookupFunction<CyanPipelineRunStepLocalNative, CyanPipelineRunStepLocalDart>('cyan_pipeline_run_step_local');
    stepEditTravel = _lib.lookupFunction<CyanStepEditTravelNative, CyanStepEditTravelDart>('cyan_step_edit_travel');
    boardWorkflowState = _lib.lookupFunction<CyanBoardWorkflowStateNative, CyanBoardWorkflowStateDart>('cyan_board_workflow_state');

    // Identity + device prefs
    buildCommit = _lib.lookupFunction<CyanBuildCommitNative, CyanBuildCommitDart>('cyan_build_commit');
    deleteIdentity = _lib.lookupFunction<CyanDeleteIdentityNative, CyanDeleteIdentityDart>('cyan_delete_identity');
    getProductionRole = _lib.lookupFunction<CyanGetProductionRoleNative, CyanGetProductionRoleDart>('cyan_get_production_role');
    setProductionRole = _lib.lookupFunction<CyanSetProductionRoleNative, CyanSetProductionRoleDart>('cyan_set_production_role');
    selectorResolve = _lib.lookupFunction<CyanSelectorResolveNative, CyanSelectorResolveDart>('cyan_selector_resolve');
    friendlyNodeId = _lib.lookupFunction<CyanFriendlyNodeIdNative, CyanFriendlyNodeIdDart>('cyan_friendly_node_id');
    ssoInstallGrant = _lib.lookupFunction<CyanSsoInstallGrantNative, CyanSsoInstallGrantDart>('cyan_sso_install_grant');
    ssoSignOut = _lib.lookupFunction<CyanSsoSignOutNative, CyanSsoSignOutDart>('cyan_sso_sign_out');

    // Anonymous sessions
    createAnonymousSession = _lib.lookupFunction<CyanCreateAnonymousSessionNative, CyanCreateAnonymousSessionDart>('cyan_create_anonymous_session');
    revealAnonymousIdentity = _lib.lookupFunction<CyanRevealAnonymousIdentityNative, CyanRevealAnonymousIdentityDart>('cyan_reveal_anonymous_identity');
    getAnonymousStatus = _lib.lookupFunction<CyanGetAnonymousStatusNative, CyanGetAnonymousStatusDart>('cyan_get_anonymous_status');
    exitAnonymousMode = _lib.lookupFunction<CyanExitAnonymousModeNative, CyanExitAnonymousModeDart>('cyan_exit_anonymous_mode');

    // Groups
    getGroupMembers = _lib.lookupFunction<CyanGetGroupMembersNative, CyanGetGroupMembersDart>('cyan_get_group_members');
    issueGrantQr = _lib.lookupFunction<CyanIssueGrantQrNative, CyanIssueGrantQrDart>('cyan_issue_grant_qr');
    scanGrantQr = _lib.lookupFunction<CyanScanGrantQrNative, CyanScanGrantQrDart>('cyan_scan_grant_qr');
    bundlePubkey = _lib.lookupFunction<CyanBundlePubkeyNative, CyanBundlePubkeyDart>('cyan_bundle_pubkey');
    exportGroup = _lib.lookupFunction<CyanExportGroupNative, CyanExportGroupDart>('cyan_export_group');
    importGroup = _lib.lookupFunction<CyanImportGroupNative, CyanImportGroupDart>('cyan_import_group');

    // Board notes + timecoded review notes
    noteList = _lib.lookupFunction<CyanNoteListNative, CyanNoteListDart>('cyan_note_list');
    notePut = _lib.lookupFunction<CyanNotePutNative, CyanNotePutDart>('cyan_note_put');
    noteDelete = _lib.lookupFunction<CyanNoteDeleteNative, CyanNoteDeleteDart>('cyan_note_delete');
    saveTimecodeNote = _lib.lookupFunction<CyanSaveTimecodeNoteNative, CyanSaveTimecodeNoteDart>('cyan_save_timecode_note');
    loadTimecodeNotes = _lib.lookupFunction<CyanLoadTimecodeNotesNative, CyanLoadTimecodeNotesDart>('cyan_load_timecode_notes');
    actOnTimecodeNote = _lib.lookupFunction<CyanActOnTimecodeNoteNative, CyanActOnTimecodeNoteDart>('cyan_act_on_timecode_note');
    exportNotesMarkdown = _lib.lookupFunction<CyanExportNotesMarkdownNative, CyanExportNotesMarkdownDart>('cyan_export_notes_markdown');

    // Scoped notes + constitution
    noteListScoped = _lib.lookupFunction<CyanNoteListScopedNative, CyanNoteListScopedDart>('cyan_note_list_scoped');
    notePutScoped = _lib.lookupFunction<CyanNotePutScopedNative, CyanNotePutScopedDart>('cyan_note_put_scoped');
    constitutionResolved = _lib.lookupFunction<CyanConstitutionResolvedNative, CyanConstitutionResolvedDart>('cyan_constitution_resolved');
    constitutionEffective = _lib.lookupFunction<CyanConstitutionEffectiveNative, CyanConstitutionEffectiveDart>('cyan_constitution_effective');

    // Templates
    templateList = _lib.lookupFunction<CyanTemplateListNative, CyanTemplateListDart>('cyan_template_list');
    workflowFromTemplate = _lib.lookupFunction<CyanWorkflowFromTemplateNative, CyanWorkflowFromTemplateDart>('cyan_workflow_from_template');
    templateCloneOutcome = _lib.lookupFunction<CyanTemplateCloneOutcomeNative, CyanTemplateCloneOutcomeDart>('cyan_template_clone_outcome');
    templateSave = _lib.lookupFunction<CyanTemplateSaveNative, CyanTemplateSaveDart>('cyan_template_save');
    templateSaveFromBoard = _lib.lookupFunction<CyanTemplateSaveFromBoardNative, CyanTemplateSaveFromBoardDart>('cyan_template_save_from_board');
    templateSaveV2 = _lib.lookupFunction<CyanTemplateSaveV2Native, CyanTemplateSaveV2Dart>('cyan_template_save_v2');
    workflowAutocomplete = _lib.lookupFunction<CyanWorkflowAutocompleteNative, CyanWorkflowAutocompleteDart>('cyan_workflow_autocomplete');

    // Producer review
    boardReviewAssignee = _lib.lookupFunction<CyanBoardReviewAssigneeNative, CyanBoardReviewAssigneeDart>('cyan_board_review_assignee');
    boardSetReviewAssignee = _lib.lookupFunction<CyanBoardSetReviewAssigneeNative, CyanBoardSetReviewAssigneeDart>('cyan_board_set_review_assignee');
    boardVideoMedia = _lib.lookupFunction<CyanBoardVideoMediaNative, CyanBoardVideoMediaDart>('cyan_board_video_media');
    reviewAddComment = _lib.lookupFunction<CyanReviewAddCommentNative, CyanReviewAddCommentDart>('cyan_review_add_comment');
    reviewCommand = _lib.lookupFunction<CyanReviewCommandNative, CyanReviewCommandDart>('cyan_review_command');

    // Ingest
    ingestCommand = _lib.lookupFunction<CyanIngestCommandNative, CyanIngestCommandDart>('cyan_ingest_command');

    // Plugins
    pluginCatalog = _lib.lookupFunction<CyanPluginCatalogNative, CyanPluginCatalogDart>('cyan_plugin_catalog');
    installPluginBundle = _lib.lookupFunction<CyanInstallPluginBundleNative, CyanInstallPluginBundleDart>('cyan_install_plugin_bundle');
    pluginConfigGet = _lib.lookupFunction<CyanPluginConfigGetNative, CyanPluginConfigGetDart>('cyan_plugin_config_get');
    pluginConfigSet = _lib.lookupFunction<CyanPluginConfigSetNative, CyanPluginConfigSetDart>('cyan_plugin_config_set');

    // ChangeList store
    changelistCommand = _lib.lookupFunction<CyanChangelistCommandNative, CyanChangelistCommandDart>('cyan_changelist_command');

    // Lens command bar
    autocompletePath = _lib.lookupFunction<CyanAutocompletePathNative, CyanAutocompletePathDart>('cyan_autocomplete_path');
    parseLensCommand = _lib.lookupFunction<CyanParseLensCommandNative, CyanParseLensCommandDart>('cyan_parse_lens_command');

    // Demo seeding
    seedDemo = _lib.lookupFunction<CyanSeedDemoNative, CyanSeedDemoDart>('cyan_seed_demo');
    seedPersonas = _lib.lookupFunction<CyanSeedPersonasNative, CyanSeedPersonasDart>('cyan_seed_personas');
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
    setMyProfile = (Pointer<Utf8> name, Pointer<Utf8> avatar) => false;
    
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
    pinSet = (Pointer<Utf8> a, bool b) {};
    pinSummaryAsBoard = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c) => _nullptr;
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
    loadChatHistory = (Pointer<Utf8> p) {};
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
    deleteFile = (Pointer<Utf8> p) {};
    resolveFileHandle = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c,
        Pointer<Utf8> d) => _nullptr;
    extractFileText = (Pointer<Utf8> p) => _nullptr;

    // Unread / notifications
    unreadCounts = () => _nullptr;
    markRead = (Pointer<Utf8> p) {};

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

    // Pipeline
    pipelineCompile = (Pointer<Utf8> p) => _nullptr;
    runPipeline = (Pointer<Utf8> p) => _nullptr;
    pipelineStatus = (Pointer<Utf8> p) => _nullptr;
    pipelineApprove = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    pipelineApproveAs = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c) => _nullptr;
    pipelineReject = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    pipelineRejectAs = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c) => _nullptr;
    pipelineRetry = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    pipelineReset = (Pointer<Utf8> p) => false;
    pipelineResetStep = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    pipelineRunStepLocal = (Pointer<Utf8> a, Pointer<Utf8> b) => _nullptr;
    stepEditTravel = (Pointer<Utf8> a, Pointer<Utf8> b, int c) => _nullptr;
    boardWorkflowState = (Pointer<Utf8> p) => _nullptr;

    // Identity + device prefs
    buildCommit = () => _nullptr;
    deleteIdentity = () => false;
    getProductionRole = () => _nullptr;
    setProductionRole = (Pointer<Utf8> p) => false;
    selectorResolve = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c) => _nullptr;
    friendlyNodeId = (Pointer<Utf8> p) => _nullptr;
    ssoInstallGrant = (Pointer<Utf8> a, Pointer<Utf8> b) => _nullptr;
    ssoSignOut = () {};

    // Anonymous sessions
    createAnonymousSession = (Pointer<Utf8> p) => _nullptr;
    revealAnonymousIdentity = (Pointer<Utf8> p) => _nullptr;
    getAnonymousStatus = (Pointer<Utf8> p) => _nullptr;
    exitAnonymousMode = (Pointer<Utf8> p) => false;

    // Groups
    getGroupMembers = (Pointer<Utf8> p) => _nullptr;
    issueGrantQr = (Pointer<Utf8> a, Pointer<Utf8> b, int c) => _nullptr;
    scanGrantQr = (Pointer<Utf8> p) => _nullptr;
    bundlePubkey = () => _nullptr;
    exportGroup = (Pointer<Utf8> a, Pointer<Utf8> b) => _nullptr;
    importGroup = (Pointer<Utf8> p) => _nullptr;

    // Board notes + timecoded review notes
    noteList = (Pointer<Utf8> p) => _nullptr;
    notePut = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c,
        Pointer<Utf8> d) {};
    noteDelete = (Pointer<Utf8> p) {};
    saveTimecodeNote = (Pointer<Utf8> p) => false;
    loadTimecodeNotes = (Pointer<Utf8> p) => _nullptr;
    actOnTimecodeNote = (Pointer<Utf8> p) => _nullptr;
    exportNotesMarkdown = (Pointer<Utf8> p) => _nullptr;

    // Scoped notes + constitution
    noteListScoped = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c) => _nullptr;
    notePutScoped = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c,
        Pointer<Utf8> d, Pointer<Utf8> e, Pointer<Utf8> f) {};
    constitutionResolved = (Pointer<Utf8> p) => _nullptr;
    constitutionEffective = (Pointer<Utf8> p) => _nullptr;

    // Templates
    templateList = (Pointer<Utf8> p) => _nullptr;
    workflowFromTemplate = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c) {};
    templateCloneOutcome = (Pointer<Utf8> p) => _nullptr;
    templateSave = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c,
        Pointer<Utf8> d) => _nullptr;
    templateSaveFromBoard = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c,
        Pointer<Utf8> d, Pointer<Utf8> e) => _nullptr;
    templateSaveV2 = (Pointer<Utf8> a, Pointer<Utf8> b) => _nullptr;
    workflowAutocomplete = (Pointer<Utf8> a, Pointer<Utf8> b) => _nullptr;

    // Producer review
    boardReviewAssignee = (Pointer<Utf8> p) => _nullptr;
    boardSetReviewAssignee = (Pointer<Utf8> a, Pointer<Utf8> b) => false;
    boardVideoMedia = (Pointer<Utf8> p) => _nullptr;
    reviewAddComment = (Pointer<Utf8> p) => _nullptr;
    reviewCommand = (Pointer<Utf8> p) => _nullptr;

    // Ingest
    ingestCommand = (Pointer<Utf8> p) => _nullptr;

    // Plugins
    pluginCatalog = () => _nullptr;
    installPluginBundle = (Pointer<Utf8> a, Pointer<Utf8> b, Pointer<Utf8> c) => _nullptr;
    pluginConfigGet = (Pointer<Utf8> p) => _nullptr;
    pluginConfigSet = (Pointer<Utf8> p) => _nullptr;

    // ChangeList store
    changelistCommand = (Pointer<Utf8> p) => _nullptr;

    // Lens command bar
    autocompletePath = (Pointer<Utf8> p) => _nullptr;
    parseLensCommand = (Pointer<Utf8> p) => _nullptr;

    // Demo seeding
    seedDemo = () {};
    seedPersonas = (Pointer<Utf8> a, Pointer<Utf8> b) => _nullptr;
  }
}
