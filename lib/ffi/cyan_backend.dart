// ffi/cyan_backend.dart
//
// THE single FFI seam for the Flutter parity port.
//
// Mirrors the SwiftUI app's `CyanBackend` protocol: every interaction with the
// Rust engine goes through this abstraction. No parity screen, view-model, or
// provider talks to `CyanFFI` / `component_bridge` directly — they depend on a
// `CyanBackend` instance.
//
//   - prod  : `CyanBackendFFI` (wraps the real component_bridge / CyanFFI)
//   - test  : `FakeCyanBackend` (lib/ffi/fake_cyan_backend.dart) — seeded demo
//             data, no native library, so Tier-1 widget/golden tests need NO
//             backend.
//
// Keep this surface SMALL and additive. It is a contract; grow it screen by
// screen as the parity port advances. The command/event JSON shapes are owned
// by cyan-backend (frozen at swiftui-parity-baseline-2026-06-29) — match, don't
// invent.

import '../models/mesh_status.dart';
import 'parity_models.dart';

/// The single gateway between Flutter UI and the Cyan engine.
///
/// Methods return plain Dart parity models (see `parity_models.dart`) so the UI
/// layer never has to know whether it is talking to FFI or a fake.
abstract class CyanBackend {
  // ---- lifecycle -----------------------------------------------------------

  /// Idempotent: bring the backend to a ready state. For the fake this seeds
  /// demo data; for FFI this initialises the engine + cache.
  Future<void> initialize();

  /// True once [initialize] has completed and the engine can serve reads.
  bool get isReady;

  // ---- tree (Group -> Workspace -> Board) ----------------------------------

  /// All groups with their nested workspaces and boards.
  Future<List<CyanGroup>> loadGroups();

  /// Flattened list of every board across all groups/workspaces, each carrying
  /// its group + workspace context. This is what the Boards grid / living wall
  /// renders.
  Future<List<BoardWithContext>> loadAllBoards();

  // ---- tree mutation (Explorer) --------------------------------------------
  //
  // The commands `FileTreeViewModel` sends to its component actor when the
  // operator creates / renames / deletes from the Explorer (`.createGroup` /
  // `.createWorkspace` / `.createBoard` / `.renameBoard` / `.deleteBoard`).
  // Fire-and-forget on the Swift side too: the engine answers with a tree
  // event, so callers re-read [loadGroups] rather than trusting a return value.

  /// Create a group named [name].
  ///
  /// The ENGINE seeds the new group's `General` and `Plugins` workspaces
  /// itself — Swift sees them arrive as two `WorkspaceCreated` events right
  /// behind `GroupCreated`, which is why `FileTreeViewModel` never creates
  /// them by hand. A caller here re-reads [loadGroups] and takes the group
  /// that appeared; there is no id to return, exactly as on the Swift seam.
  ///
  /// Icon and colour are not parameters for the same reason they aren't on the
  /// Swift side: `commitRename` always sends `folder.fill` / `#00AEEF`.
  Future<void> createGroup(String name);

  /// Create a workspace named [name] inside [groupId].
  Future<void> createWorkspace(String groupId, String name);

  /// Create a board named [name] inside [workspaceId].
  Future<void> createBoard(String workspaceId, String name);

  /// Rename the board [boardId] to [name].
  Future<void> renameBoard(String boardId, String name);

  /// Delete the board [boardId] (soft delete + tombstone on the engine side).
  Future<void> deleteBoard(String boardId);

  // ---- board pins ------------------------------------------------------------

  /// Set the board's pin flag in ONE verb — [pinned] carries both directions.
  /// Fire-and-forget for the same reason the three above are: the engine queues
  /// a SetPin command and answers with a tree event, not a receipt.
  Future<void> pinSet(String boardId, bool pinned);

  /// Promote a markdown summary into a board of its own inside [workspaceId],
  /// carrying [markdownContent] as its opening cell. Returns the ENGINE's
  /// deterministic board id — the same (workspace, name) always names the same
  /// board — or null when the engine refused to mint one.
  Future<String?> pinSummaryAsBoard(
      String workspaceId, String boardName, String markdownContent);

  // ---- a single workflow run (Dashboard) -----------------------------------

  /// The most recent / sample run for a board, if any. Drives the Dashboard
  /// DAG + gated-run face.
  Future<WorkflowRun?> loadRun(String boardId);

  // ---- board faces ---------------------------------------------------------

  /// The authored workflow (steps + compiled inference chips) for a board's
  /// Workflow face.
  Future<Workflow> loadWorkflow(String boardId);

  /// Append one plain-English step to [boardId]'s workflow. It is filed as a
  /// `step` cell — the SAME cell [pipelineCompile] later stamps its plan onto,
  /// which is why an authored step carries no inference chips until a compile
  /// has run over it.
  ///
  /// Returns the step as it was filed, carrying the id the write minted, or
  /// null when nothing was filed: whitespace-only text is refused here rather
  /// than persisted as a blank step, and a refused write answers null too.
  Future<WorkflowStep?> addWorkflowStep(String boardId, String text);

  /// Rewrite an authored step's English in place, keeping its id and its
  /// position in the board. The step's compile verdict is re-derived from the
  /// new text — binding a plugin with an `@mention` is how an ambiguous step
  /// stops being ambiguous. False when the write was refused.
  Future<bool> updateWorkflowStep(String boardId, String stepId, String text);

  /// Remove one authored step cell from the board
  /// (`cyan_delete_notebook_cell`). False when the engine refused it.
  ///
  /// The one caller that needs it is the template picker's REPLACE clone: a
  /// non-empty board is asked Replace / Append / Cancel, and Replace clears
  /// exactly the ids the operator was shown before the clone dispatches.
  Future<bool> deleteWorkflowStep(String boardId, String stepId);

  /// Every cell of the board's notebook DOCUMENT, oldest-first by `cell_order`
  /// (`cyan_load_notebook_cells` — the same ledger [loadWorkflow] reads its
  /// steps out of, unfiltered).
  ///
  /// [loadWorkflow] answers "what does this board RUN"; this answers "what does
  /// this board SAY" — the step cells plus the markdown, code, image and
  /// diagram cells around them. A cell whose kind this build does not know is
  /// still returned, marked [NotebookCellKind.unknown]: a document that drops
  /// rows it cannot draw silently loses the operator's work.
  Future<List<NotebookCell>> notebookCells(String boardId);

  /// The notes document for a board's Notes face.
  Future<BoardNotes> loadNotes(String boardId);

  /// Save the board's notes DOCUMENT (the reference's `NotesEditorViewModel
  /// .save()`: one markdown cell, created or updated in place).
  ///
  /// The result carries a READ-BACK, not just an acknowledgement, because on
  /// this engine baseline the two differ: `cyan_save_notebook_cell` runs every
  /// authored kind through `workflow::coerce_authoring_cell_type` and `step` is
  /// the only authorable one, so a notes document is accepted, stored, re-kinded
  /// — and then invisible to the markdown filter the editor reads by. A face
  /// that reported that as "Saved" would be lying to the operator every time.
  Future<NotesSaveResult> saveNotes(String boardId, String content);

  /// The board's SAVED face, spelled as the engine stores it
  /// (`cyan_get_board_mode` — Swift `BoardFaceBridge.getActiveFace`). Null when
  /// nothing was ever saved for this board, or when nobody answered: the
  /// container then opens its default face rather than inventing one. Faces the
  /// app no longer has (`canvas`) come back verbatim — migrating them is the
  /// reader's job, not the seam's.
  Future<String?> boardActiveFace(String boardId);

  /// Persist the board's face (`cyan_set_board_mode` — Swift
  /// `BoardFaceBridge.setActiveFace`). False when the engine refused the write;
  /// the container then does NOT move, exactly as `switchToFace` publishes the
  /// new face only after the engine accepts it.
  Future<bool> setBoardActiveFace(String boardId, String face);

  // ---- operations console --------------------------------------------------

  /// All runs across the tenant for the Ops Runs feed.
  Future<List<OpsRun>> loadOpsRuns();

  /// The tenant-wide asset-minute cost meter (Ops Cost face).
  Future<CostMeter> loadCostMeter();

  /// The efficiency report (insight cards + per-step table).
  Future<EfficiencyReport> loadEfficiency();

  /// The per-step AUDIT for one run — what each step processed, billed and
  /// burned, so a figure like "$0.22" is explainable in-app. Null when the run
  /// is unknown or has not been traced; the audit face reports that rather
  /// than inventing a trace.
  Future<RunTrace?> loadRunTrace(String runId);

  // ---- license / entitlement -----------------------------------------------

  /// The CACHED signed entitlement claims as JSON — the grant the engine caches
  /// so the trial banner and the paid-surface locks work OFFLINE. Null when
  /// nothing is cached yet (fresh device); the caller falls back to
  /// [Entitlement.offlineDefault] rather than hard-locking itself.
  Future<String?> cachedEntitlementJson();

  // ---- marketplace ---------------------------------------------------------

  /// All marketplace plugin cards (featured flagged on the card).
  Future<List<PluginCard>> loadMarketplace();

  // ---- plugins -------------------------------------------------------------
  //
  // What this device has installed and how a new bundle lands. Distinct from
  // the marketplace listing ([loadMarketplace]), which is what COULD be
  // installed.

  /// The plugin bundles INSTALLED on this device, ordered by id with each
  /// bundle's tools ordered by name. A bundle with a bad manifest is SKIPPED by
  /// the engine, so it never appears; no plugins at all is empty.
  Future<List<InstalledPlugin>> pluginCatalog();

  /// Install a `.cyanplugin` bundle into [groupId] from its base64 bytes. The
  /// ENGINE gates the install on bundle layout + signature policy BEFORE
  /// anything lands, so a malformed or unadmitted bundle comes back as
  /// [PluginInstallResult.error] rather than being judged here.
  Future<PluginInstallResult> installPluginBundle(
      String groupId, String pluginId, String bundleBytesB64);

  // ---- plugin config -------------------------------------------------------
  //
  // The NON-SECRET half of a plugin's setup: which Frame.io account, which
  // folder, which C2C project. Scoped to a group (the engine's tenant) so one
  // operator serving many producers never shares one global env var.
  //
  // Credentials do NOT come through here. They belong to the device vault and
  // are injected as spawn env, resolved fresh per spawn — the engine's write
  // API refuses a secret-looking key outright. See the engine's
  // `plugin_config.rs` and PLUGIN_CREDENTIAL_ONBOARDING.md.

  /// Every config row the engine holds for ([groupId], [pluginId]) — what the
  /// plugin's settings sheet lists.
  Future<PluginConfig> pluginConfigGet(String groupId, String pluginId);

  /// Upsert one config row. The ENGINE decides whether the key is admissible;
  /// a secret-looking key comes back as [PluginConfigWrite.error] rather than
  /// being judged here.
  Future<PluginConfigWrite> pluginConfigSet(
      String groupId, String pluginId, String key, String value);

  // ---- lens ----------------------------------------------------------------

  /// The Lens intelligence bundle (nudges / asks / decisions).
  Future<LensIntelligence> loadLensIntelligence();

  // ---- chat ----------------------------------------------------------------

  /// The chat transcript for a board.
  Future<List<ChatMessage>> loadChat(String boardId);

  /// Ask the engine to REPLAY the board's stored chat onto the chat-panel event
  /// buffer: one `ChatSent` frame per message, then `ChatHistoryComplete`.
  ///
  /// Fire-and-forget — it acknowledges nothing, because the history IS the
  /// frames. Callers drain [pollEvents] for them rather than awaiting a
  /// transcript here; [loadChat] is the snapshot read.
  Future<void> loadChatHistory(String boardId);

  /// Send [message] to the board [boardId]'s chat. [parentId] threads it under
  /// an existing message; null is the board's general slot.
  ///
  /// Chat is BOARD-SCOPED on the wire — there is no group or workspace chat —
  /// so the board id is the whole address and a caller without one has nothing
  /// to send to.
  ///
  /// Returns the message as it was filed, carrying the id the write minted, or
  /// null when nothing was sent: whitespace-only text is refused HERE rather
  /// than reaching the mesh, exactly as the macOS composer refuses it.
  Future<ChatMessage?> sendChat(String boardId, String message,
      {String? parentId});

  /// Delete a chat message by id. Soft-delete + tombstone gossiped to peers,
  /// like every other delete in the engine — the message converges to deleted
  /// everywhere rather than only vanishing here. Fire-and-forget: callers
  /// re-read the transcript rather than wait for a receipt.
  Future<void> deleteChat(String messageId);

  // ---- unread --------------------------------------------------------------
  //
  // BOARD-level only. One message counts once, on its board — there is no
  // workspace or group rollup, so the dock badge total is the SUM of this map
  // and a caller that adds its own rollup would double-count.

  /// Unread count per board id. A board with nothing unread is absent from the
  /// map rather than present as 0.
  Future<Map<String, int>> unreadCounts();

  /// Mark the board [scopeId] read: its unread items clear and the engine emits
  /// `UnreadChanged`. Opening a chat is a READ, so this is what opening one
  /// fires — it never increments anything. Fire-and-forget: callers re-read
  /// [unreadCounts] rather than wait for a receipt.
  Future<void> markRead(String scopeId);

  // ---- files ---------------------------------------------------------------

  /// The ACTIVE files attached to one board, in the order the engine lists
  /// them (`cyan_get_files` under a board scope). Tombstoned files are absent,
  /// never present-and-flagged.
  ///
  /// A file here may be METADATA ONLY — the row has synced but the bytes have
  /// not. [CyanFile.isDownloaded] is what separates the two, and it is why the
  /// files face has a download affordance at all.
  Future<List<CyanFile>> filesForBoard(String boardId);

  /// Ask the mesh for a remote file's bytes. Returns whether the engine
  /// ACCEPTED the request, not whether the file arrived — the transfer runs
  /// after this answers, and [fileStatus] is how its progress is read.
  Future<bool> requestFileDownload(String fileId);

  /// Where one file's bytes are, and how far along a transfer in flight is.
  /// Null when the engine does not know the id at all.
  Future<FileTransfer?> fileStatus(String fileId);

  /// Delete a file. Soft-delete + tombstone gossiped to peers — the engine
  /// never hard-deletes — so the row converges to deleted everywhere rather
  /// than vanishing here. Fire-and-forget.
  Future<void> deleteFile(String fileId);

  /// Resolve a file by its stable workflow handle
  /// `group_id:workspace_id:board_id:file_name` — how a workflow step names an
  /// input without carrying an id around. Null when no ACTIVE file matches; a
  /// tombstoned one never resolves.
  Future<CyanFile?> resolveFileHandle(
      String groupId, String workspaceId, String boardId, String fileName);

  /// Extract the text of the file at [path] (PDF, TXT, MD, CSV, JSON, code) for
  /// the Lens rails. The ENGINE truncates to its own token budget, so what
  /// comes back may be shorter than the file. Null means the engine could not
  /// read it — an unsupported or unreadable file — never an empty document.
  Future<String?> extractFileText(String path);

  // ---- presence ------------------------------------------------------------

  /// The LIVE peer set behind the shell's status bar: the engine's own total
  /// (`cyan_get_total_peer_count`) with the per-group ids behind it
  /// (`cyan_get_all_peers`).
  ///
  /// A dead engine answers [MeshPresence.none] — zero peers, which is the
  /// honest reading, not an error. The engine has no presence STREAM, so this
  /// is a READ the status bar polls; see `syncLifecycleProvider`.
  Future<MeshPresence> meshPresence();

  // ---- identity ------------------------------------------------------------

  /// The signed-in identity on THIS device (`cyan_get_my_node_id` +
  /// `cyan_get_my_profile`) — what the shell's status bar shows and the
  /// Settings / Identity face states in full. Null when no identity exists on
  /// the device (fresh install, or after a vault wipe), which callers render
  /// as signed-out rather than as a blank profile.
  Future<DeviceProfile?> myProfile();

  // ---- live event pump -----------------------------------------------------

  /// Pop ONE queued event frame off [component]'s buffer, or null when the
  /// buffer is empty (`cyan_poll_events`). Mirrors the SwiftUI seam's
  /// `pollEvents(component:)`, which `ComponentActor` drains in a loop.
  ///
  /// Contract, and it is load-bearing for every consumer:
  ///   - null means EMPTY, not broken. It is the normal answer.
  ///   - the buffer is POP-FRONT, so a frame is delivered to exactly one
  ///     caller — a component may have only one live pump.
  ///   - the frame is raw JSON the engine wrote. It may be a variant this
  ///     build has never heard of; decoding is the caller's problem and must
  ///     never be fatal.
  Future<String?> pollEvents(String component);

  // ---- pipeline (the compile / run / gate spine) ----------------------------
  //
  // These drive a workflow: compile the authored steps, run the DAG, then walk
  // the approval gates. Compile and run are FIRE-AND-FORGET engine-side — they
  // acknowledge immediately and the work lands later, so poll [pipelineStatus]
  // (or the event stream) for progress.

  /// Compile the board's authored steps into an executable DAG. Returns the
  /// engine's immediate acknowledgement, not the finished compile.
  Future<PipelineLaunch> pipelineCompile(String boardId);

  /// Start the compiled DAG. Returns the immediate acknowledgement.
  Future<PipelineLaunch> runPipeline(String boardId);

  /// The persisted single-run snapshot: derived run status, per-step state +
  /// cost, and the step currently holding the gate. Pure read.
  Future<PipelineStatus> pipelineStatus(String boardId);

  /// AUTOPILOT (design §1) — a board's autopilot mode: `off` (every gate is
  /// human), `assist` (earned classes only), `autopilot` (the policy card
  /// clears gates; you get digests and the kill switch).
  ///
  /// Reading it is a READ, and it answers the engine's own default (`off`) for
  /// a board that has never been flipped — an unreachable engine also answers
  /// `off`, because the safe reading of "I do not know" is "every gate is
  /// still yours".
  Future<String> autopilotMode(String boardId);

  /// Set a board's autopilot mode. Flipping TO `autopilot` is the human
  /// ADOPTION act that delegates gate clearance to the policy; flipping back is
  /// the kill switch. Answers the mode the ENGINE now holds, not the one that
  /// was asked for — a refused write must not leave the toolbar claiming a
  /// delegation that never happened.
  Future<String> setAutopilotMode(String boardId, String mode);

  /// Clear a step's approval gate. False when the gate would not move.
  Future<bool> pipelineApprove(String boardId, String stepId);

  /// Clear a step's gate AS [reviewer]. A producer-review hold clears ONLY for
  /// the user it is waiting on — the ack carries WHO when it refuses.
  Future<PipelineAck> pipelineApproveAs(
      String boardId, String stepId, String reviewer);

  /// Reject a step at its gate.
  Future<bool> pipelineReject(String boardId, String stepId);

  /// Reject a step's gate AS [reviewer] — the twin of [pipelineApproveAs].
  Future<PipelineAck> pipelineRejectAs(
      String boardId, String stepId, String reviewer);

  /// Retry a step: back to pending with its compiled metadata preserved.
  Future<bool> pipelineRetry(String boardId, String stepId);

  /// Reset every step on the board back to pending.
  Future<bool> pipelineReset(String boardId);

  /// Reset ONE step back to pending.
  Future<bool> pipelineResetStep(String boardId, String stepId);

  /// Dispatch ONE step against its locally-bound plugin, without walking the
  /// DAG. Reports gated / parked outcomes distinctly from a failure.
  Future<StepRunResult> pipelineRunStepLocal(String boardId, String stepId);

  /// Walk a step cell's edit history one revision in [direction], returning the
  /// restored body and the remaining undo/redo depths.
  Future<StepTravel> stepEditTravel(
      String boardId, String cellId, StepTravelDirection direction);

  /// The board's deploy state (deployed / dashboard / locked). A board with no
  /// deployment reads back as the authoring default.
  Future<BoardWorkflowState> boardWorkflowState(String boardId);

  // ---- device identity + prefs ---------------------------------------------

  /// The commit the loaded engine was built from, so a bug report can name the
  /// exact binary. Null when no engine is loaded.
  Future<String?> buildCommit();

  /// Wipe this device's identity from the vault. After this [myProfile] answers
  /// null — the device is signed OUT, not blank. Destructive and final.
  Future<bool> deleteIdentity();

  /// The device's craft-role preference, or null when unset. Device-LOCAL by
  /// construction — it is never synced.
  Future<String?> getProductionRole();

  /// Save the craft-role preference; the empty string CLEARS it. A role outside
  /// the engine's vocabulary is REFUSED (false) and the pref is left untouched.
  Future<bool> setProductionRole(String role);

  /// Resolve a craft-role selector. A refusal carries the vocabulary the engine
  /// WOULD accept, which is how a caller reads the catalog rather than keeping
  /// its own copy of it.
  Future<SelectorResolution> selectorResolve(String role, String formatType,
      {String tenantId = ''});

  /// The ENGINE's display fallback for a raw node id — "User-A3F2". An id too
  /// short to abbreviate comes back unchanged. Screens ask for it rather than
  /// abbreviating themselves, so one device's fallback name matches another's.
  Future<String?> friendlyNodeId(String nodeId);

  // ---- SSO session grants ----------------------------------------------------

  /// Install a broker-minted session grant, verified against [trustJson]
  /// ({"tenant":"…","org_did":…|null,"legacy_rsa_public_pem":…|null,
  /// "grace_secs":N}). Success seeds the granted groups and flips RBAC active.
  /// A refusal carries the engine's reason and leaves any previously installed
  /// session UNTOUCHED — a bad re-install never signs the device out.
  Future<SsoSession> ssoInstallGrant(String grantToken, String trustJson);

  /// Clear the installed session; RBAC returns to its no-session default. There
  /// is nothing to report — the sign-out cannot fail.
  Future<void> ssoSignOut();

  // ---- anonymous sessions ---------------------------------------------------
  //
  // Anonymity is per SCOPE (a board / workspace id): a device can be masked on
  // one board and visible on another. Revealing is ONE WAY.

  /// Mint an ephemeral session for [scopeId]. The ENGINE mints the handle —
  /// callers never invent one. Null when the engine could not mint.
  Future<AnonymousSession?> createAnonymousSession(String scopeId);

  /// Bind the scope's handle back to this device's real identity. Null when
  /// there is no session, or it was already revealed — it cannot be undone.
  Future<AnonymousSession?> revealAnonymousIdentity(String scopeId);

  /// Whether this device is behind a handle in [scopeId].
  Future<AnonymousStatus> getAnonymousStatus(String scopeId);

  /// Drop the scope's session — this device is visible there again.
  Future<bool> exitAnonymousMode(String scopeId);

  // ---- groups: roster, grants, portable bundles ------------------------------

  /// The group's PERSISTENT roster. Members who are offline stay listed with
  /// their cached names; [GroupMember.online] is a live overlay on a durable
  /// row, never the row's existence condition.
  Future<List<GroupMember>> getGroupMembers(String groupId);

  /// Mint a signed capability grant for {group, role}. [ttlSeconds] of 0 takes
  /// the engine's own default. Only a group Owner/Admin may issue one — anyone
  /// else gets a refusal carrying the engine's reason.
  Future<GrantQrIssue> issueGrantQr(String groupId, String role,
      {int ttlSeconds = 0});

  /// Verify a grant QR and JOIN the group it grants. A forged, expired or
  /// out-of-scope payload is refused BY THE ENGINE — the caller never
  /// adjudicates a grant itself.
  Future<GrantScanResult> scanGrantQr(String qrPayload);

  /// This device's X25519 bundle public key — the recipient key an inviter
  /// seals a `.cyangroup` export to.
  Future<String?> bundlePubkey();

  /// Seal a portable group bundle TO [inviteePubkey]. It re-imports on that
  /// device and nowhere else.
  Future<GroupExportResult> exportGroup(String groupId, String inviteePubkey);

  /// Verify, decrypt and seed a `.cyangroup` bundle. Works fully offline.
  Future<GroupImportResult> importGroup(String bundle);

  // ---- board notes: the review rail's plain CRUD ------------------------------

  /// A board's notes, tenant-scoped to the board's GROUP by the engine. This is
  /// the unscoped read — [noteListScoped] narrows the same store by scope/kind.
  Future<List<CyanNote>> noteList(String boardId);

  /// Write a note on a board. An omitted [noteId] mints a new note; passing one
  /// EDITS that note (the engine resolves the conflict last-write-wins). An
  /// omitted [tenantId] lets the ENGINE derive the tenant from the board's
  /// group, so reads match writes.
  ///
  /// Fire-and-forget engine-side: the write is queued and acknowledged with
  /// nothing, so callers re-read rather than wait for a receipt.
  Future<void> notePut(String boardId, String text,
      {String? noteId, String? tenantId});

  /// Write a note carrying its ANCHOR and its PROVENANCE — the C7 lane the
  /// ledger's anchor label and from-chat glyph are drawn from.
  ///
  /// The plain C verbs (`cyan_note_put` / `cyan_note_put_scoped`) hardcode
  /// `anchor_kind`/`anchor_id`/`origin_ref` to null, so an anchored note cannot
  /// be written through them at all. The engine takes one through the JSON
  /// command door (`cyan_send_command` with a `PutNote` body), which is exactly
  /// what SwiftUI's `BoardNote.toJSON()` feeds it. Fire-and-forget like the
  /// other note writes: callers re-read.
  ///
  /// False when the command could not even be queued.
  Future<bool> notePutAnchored(
    String boardId,
    String text, {
    String? noteId,
    String? tenantId,
    String scope = 'board',
    String kind = 'editor-note',
    String? anchorKind,
    String? anchorId,
    String? originRef,
    String? authorRole,
  });

  /// Delete a note by id. Fire-and-forget for the same reason as [notePut].
  Future<void> noteDelete(String id);

  // ---- timecoded notes: review pinned to a moment in the asset ----------------

  /// A board's timecoded notes, engine-ordered by timecode.
  Future<List<TimecodeNote>> loadTimecodeNotes(String boardId);

  /// Persist [note] — a new one or an edit of an existing id. False means the
  /// ENGINE refused it (unparseable note, or no store to write to); it is never
  /// a partial write.
  Future<bool> saveTimecodeNote(TimecodeNote note);

  /// Send [note] to the engine's AI rail. The engine builds the prompt from the
  /// note's pipeline context and nearby flags, and RE-SAVES the note with the
  /// answer attached — so the caller re-reads the list instead of patching its
  /// own copy.
  Future<TimecodeNoteAction> actOnTimecodeNote(TimecodeNote note);

  /// The board's whole review rail as a markdown timeline: threads grouped by
  /// the pipeline step they were raised against, each root note carrying its AI
  /// result and its replies beneath it. This is the ENGINE's rendering, so an
  /// export from here reads identically to one taken from the shipping app.
  /// Null when the notes store could not be read.
  Future<String?> exportNotesMarkdown(String boardId);

  // ---- scoped notes + the constitution chain they feed ------------------------

  /// List an anchor's notes in ONE scope (`board` | `group` | `tenant` | …).
  /// An omitted [kind] reads every kind. The ENGINE derives the tenant from the
  /// anchor, so a board read finds its own group's notes — reads match writes.
  Future<List<CyanNote>> noteListScoped(String boardId, String scope,
      {String kind = ''});

  /// Write a note at one scope. A group-scope rule is anchored on the GROUP, so
  /// pass the group id as [boardId] for one.
  Future<void> notePutScoped(String boardId, String text,
      {String scope = 'board', String kind = 'editor-note'});

  /// The on-device PREVIEW resolve for a board: the merged constitution
  /// markdown, the soft preferences kept APART from it, the chain hash and the
  /// provenance. The user scope is included — the caller IS the device owner.
  Future<ResolvedConstitution> constitutionResolved(String boardId);

  /// The same chain read the cloud sees, plus the HARD rules the engine
  /// classified off it — constraints a run may not trade away.
  Future<EffectiveConstitution> constitutionEffective(String boardId);

  // ---- templates: the spine cloned onto a board ------------------------------
  //
  // A template is a pre-written English workflow. Cloning one materializes real
  // authorable step cells on a board — the answer to a blank slate. The clone
  // is FIRE-AND-FORGET engine-side, so its result is POLLED, not returned.

  /// The templates visible to [tenantId]: the built-in seeds (always) plus that
  /// tenant's own saves. An empty [tenantId] reads the seeds ALONE — that is
  /// the engine's own reading of "no tenant", not an error.
  Future<List<CyanTemplate>> templateList({String tenantId = ''});

  /// Clone [templateId] onto [boardId] as real step cells. Fire-and-forget: the
  /// engine acknowledges nothing, so callers re-read the board (and poll
  /// [templateCloneOutcome] for the auto-install result). An empty [tenantId]
  /// lets the ENGINE derive the tenant from the board's group.
  Future<void> workflowFromTemplate(String templateId, String boardId,
      {String tenantId = ''});

  /// The board's LAST clone outcome: how many cells landed and what the
  /// template's declared plugin set did. Null when no clone has finished for
  /// this board since launch — that is the engine's answer, so the caller keeps
  /// polling rather than reporting a failure.
  Future<TemplateCloneOutcome?> templateCloneOutcome(String boardId);

  /// Save [steps] as a reusable user template owned by [tenantId].
  ///
  /// This verb carries NO error channel — the engine answers a refusal and an
  /// unreachable engine identically — so the result says exactly that instead
  /// of naming a cause it cannot know.
  Future<TemplateSaveResult> templateSave(
      String tenantId, String name, String description, List<TemplateStep> steps);

  /// The same save FROM [boardId], so the board's STANDING notes (constitution
  /// / preference) travel with the template and a clone lands them too.
  Future<TemplateSaveResult> templateSaveFromBoard(String tenantId, String name,
      String description, List<TemplateStep> steps, String boardId);

  /// Save a ROLETYPE template (format type, stages, note kinds, plugin set).
  ///
  /// The ENGINE validates every vocabulary field and rejects the WHOLE save on
  /// any violation, carrying the value it refused and the vocabulary it would
  /// accept — the caller never keeps its own copy of the catalog.
  Future<TemplateSaveResult> templateSaveV2(
      String tenantId, CyanTemplate template);

  // ---- step composer --------------------------------------------------------

  /// The autocomplete index for [boardId], filtered by the trailing `@` / `#` /
  /// `/` trigger in [partial]. Text with no active trigger returns the FULL
  /// index and the caller decides what to show.
  Future<AutocompleteIndex> workflowAutocomplete(String boardId, String partial);

  // ---- producer review: assignee, media, comments -----------------------------
  //
  // The surface behind the review rail: WHO a gate waits on, WHAT the board
  // plays, and the comment that lands on it. The comment verb reaches an
  // external review service through the plugin host, so it is the one read here
  // that can fail for reasons outside this device.

  /// The REAL user this board's review gates wait on — the engine stamps it
  /// into review-hold steps as `waiting_on`, which is what
  /// [pipelineApproveAs] then clears against. Null when unset: the board's
  /// holds wait on nobody in particular.
  Future<String?> boardReviewAssignee(String boardId);

  /// Set the board's review assignee. False when the ENGINE refused the write;
  /// the previous assignee is left untouched, never half-written.
  Future<bool> boardSetReviewAssignee(String boardId, String user);

  /// The board's playable video, resolved through the same rails the media
  /// tools use — so the player never opens a different file than the workflow
  /// operates on. A board with nothing ingested answers with no media, which is
  /// an answer, not an error.
  Future<BoardVideoMedia> boardVideoMedia(String boardId);

  /// Post a frame-anchored comment at [atSeconds] on the board's CURRENT review
  /// proxy, and echo it locally as a timecoded note (so it appears on the same
  /// rail as sensed comments). The engine anchors it in frames using the
  /// proxy's own fps.
  ///
  /// This one leaves the device: a board with no published review media, or an
  /// unreachable review service, comes back as a refusal carrying the engine's
  /// reason. Blocking engine-side, so callers should not hold a frame on it.
  Future<ReviewCommentResult> reviewAddComment(String boardId, String text,
      {double atSeconds = 0, String author = 'reviewer'});

  /// Drive the review-loop state machine. [command] is the engine's own op
  /// envelope — `{"op": …, "actor": "auto|agent|human", …}` — passed through
  /// verbatim, because the op vocabulary and the three-actor authority model
  /// are the ENGINE's and it enforces them itself. An AGENT may only propose;
  /// every gated / external-send transition requires `actor: human`, and a
  /// caller that fires one without it gets a refusal rather than a state move.
  Future<ReviewCommandResult> reviewCommand(Map<String, dynamic> command);

  /// Drive the ingest surface: the watched sources on a board and the per-asset
  /// workflow runs a scan materializes. [command] is the engine's own op
  /// envelope — `{"op": …, "tenant_id": …, …}` — passed through verbatim, for
  /// the same reason [reviewCommand] is: the op vocabulary is the ENGINE's.
  /// Ops: source_add, source_list, source_remove, scan_now, scan_due,
  /// runs_for_board, produce_master_plan.
  ///
  /// `scan_now` and `scan_due` walk the watched location, so they are slow and
  /// leave the device for the bucket kinds. A source that cannot be read comes
  /// back as a carried error on its own sweep row rather than sinking the tick.
  Future<IngestCommandResult> ingestCommand(Map<String, dynamic> command);

  /// Drive the content-addressed ChangeList store — the review-&-conform
  /// ledger behind the review player. [command] is the engine's own op
  /// envelope, passed through verbatim for the same reason [reviewCommand] and
  /// [ingestCommand] are: the op vocabulary and the authority model are the
  /// ENGINE's and it enforces them itself.
  ///
  /// Ops: append, set_state, set_active, supersede, snapshot, branch, diff,
  /// conform_plan, get, get_version, set_outcome, plus the BOARD-keyed `list`
  /// the review player reads its envelope from.
  ///
  /// The read ops take a BOUNDED acquire engine-side: under contention they
  /// answer "store busy — try again" rather than parking the caller, so a
  /// refusal here is routinely transient and the caller keeps what it has.
  Future<ChangelistCommandResult> changelistCommand(
      Map<String, dynamic> command);

  // ---- lens command bar -------------------------------------------------------

  /// Complete a partial `g\Group\Workspace\Board` path, ten rows at a time.
  /// The engine reads this under a BOUNDED acquire because it fires per
  /// keystroke: a busy store answers with NO suggestions rather than parking
  /// the caller, and the next keystroke retries. So an empty list here means
  /// "nothing to offer for this keystroke", never "no such path".
  Future<List<PathSuggestion>> autocompletePath(String partial);

  /// Parse one `/verb` line. The ENGINE owns the command vocabulary and the
  /// path grammar, and it already runs the read-only verbs while parsing — a
  /// `/pipeline status` comes back carrying its status payload, a
  /// `/summarize file` with the file's text already extracted. Callers dispatch
  /// on [LensCommandParse.type] rather than re-parsing the line themselves.
  Future<LensCommandParse> parseLensCommand(String input);

  // ---- demo seeding -----------------------------------------------------------

  /// Seed the coherent demo set under this device's OWN identity. Idempotent —
  /// it truncates then re-seeds its managed group ids, so calling it twice
  /// converges on exactly one copy. Fire-and-forget engine-side: the seed is
  /// queued and the tree refreshes on the engine's own snapshot, so callers
  /// re-read rather than wait for a receipt.
  Future<void> seedDemo();

  /// Seed the six-role persona cast and get the routing manifest back — one row
  /// per persona naming the `seedtok_<persona>` token and the surface its
  /// sign-in lands on. GATED engine-side: a build without `CYAN_SEED_DEMO=1`
  /// refuses with `seed_disabled` and seeds nothing. An empty [tenantId] takes
  /// the engine's own `seedtok` default; an empty [ownerNodeId] seeds without
  /// stamping an owner.
  Future<SeedPersonasResult> seedPersonas(
      {String tenantId = '', String ownerNodeId = ''});

}
