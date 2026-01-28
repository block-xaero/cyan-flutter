# Cyan Flutter

Offline-first P2P collaborative workspace. Notion + Miro + Slack without servers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Flutter (UI)                                                   │
│  ├─ Riverpod providers → ViewModels                             │
│  └─ ComponentBridge → FFI → Rust backend                        │
└────────────────────────────────────────────────────────────────┬┘
                                                                 │
                                                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  Rust Backend (cyan-backend)                                    │
│  ├─ lib.rs         — FFI layer (~90 C-compatible functions)     │
│  ├─ commands.rs    — Command enum (CreateGroup, SendMessage...) │
│  ├─ network_actor  — Iroh (QUIC + gossipsub)                    │
│  ├─ storage/       — SQLite + local files                       │
│  └─ actors/        — Per-component actors (Chat, FileTree...)   │
└─────────────────────────────────────────────────────────────────┘
```

## Data Hierarchy

```
Group
  └─ Workspace
       └─ Board
            └─ Faces: Notes | Canvas | Chat | Files
```

## FFI Bridge

Flutter talks to Rust via `ComponentBridge`:

```dart
// Send command to Rust
ComponentBridge.sendCommand('FileTree', '{"type":"LoadTree"}');

// Poll events from Rust  
String events = ComponentBridge.pollEvents('FileTree');
```

Key FFI functions exposed from Rust:

| Function | Purpose |
|----------|---------|
| `cyan_init()` | Initialize backend |
| `cyan_send_command(component, json)` | Send command to actor |
| `cyan_poll_events(component)` | Get events from actor |
| `cyan_free_string(ptr)` | Free Rust-allocated string |
| `cyan_create_group/workspace/board` | CRUD operations |
| `cyan_rename_group/workspace/board` | Rename entities |
| `cyan_delete_group/workspace/board` | Delete entities |
| `cyan_seed_demo_if_empty()` | Seed demo data |

## Project Structure

```
lib/
├── main.dart
├── ffi/
│   ├── cyan_bindings.dart      # Raw FFI bindings (dart:ffi)
│   └── component_bridge.dart   # High-level wrapper
├── providers/
│   ├── navigation_provider.dart
│   ├── file_tree_provider.dart
│   ├── board_grid_provider.dart
│   └── chat_provider.dart
├── models/
│   └── tree_item.dart          # Group, Workspace, Board models
├── screens/
│   ├── login_screen.dart
│   └── workspace_screen.dart
└── widgets/
    ├── icon_rail.dart          # Left navigation rail
    ├── file_tree_widget.dart   # Explorer tree view
    ├── board_grid_widget.dart  # Masonry grid of boards
    └── chat_panel.dart         # Chat with code blocks
```

## Building

### Prerequisites

- Flutter 3.27+
- Rust toolchain
- For macOS: Xcode

### Build Rust Backend

```bash
cd cyan-backend

# macOS arm64
cargo build --release --target aarch64-apple-darwin

# Copy to Flutter project
cp target/aarch64-apple-darwin/release/libcyan_backend.a ../cyan_flutter/macos/Libraries/
```

### Run Flutter

```bash
cd cyan_flutter
flutter pub get
flutter run -d macos
```

## P2P Sync

Sync via Iroh (QUIC + gossipsub):

- **Discovery**: `cyan/discovery/{discovery_key}` topic
- **Group sync**: `cyan/group/{group_id}` topic
- **Direct**: QUIC connection via Iroh node ID

Sync flow:
1. New peer joins discovery topic → announces presence
2. Existing peer sends snapshot (full state dump)
3. Ongoing changes sync via delta events on group topics

## Commands & Events

Commands flow: Flutter → FFI → Rust actor
Events flow: Rust actor → FFI → Flutter provider

### FileTree Commands

```json
{"type": "LoadTree"}
{"type": "CreateGroup", "name": "...", "icon": "...", "color": "..."}
{"type": "CreateWorkspace", "group_id": "...", "name": "..."}
{"type": "CreateBoard", "workspace_id": "...", "name": "...", "board_type": "..."}
```

### FileTree Events

```json
{"type": "TreeLoaded", "groups": [...], "workspaces": [...], "boards": [...]}
{"type": "GroupCreated", "id": "...", "name": "..."}
{"type": "Error", "message": "..."}
```

### Chat Commands

```json
{"type": "LoadChatHistory", "board_id": "..."}
{"type": "SendMessage", "board_id": "...", "text": "..."}
```

### Chat Events

```json
{"type": "ChatHistory", "messages": [...]}
{"type": "Message", "id": "...", "text": "...", "sender_id": "...", "timestamp": "..."}
```

## Storage

SQLite with tables:

| Table | Purpose |
|-------|---------|
| `groups` | Group metadata |
| `workspaces` | Workspace metadata |
| `objects` | Boards, notes, files |
| `messages` | Chat messages |
| `peers` | Known peers |

Content-addressed files via Blake3 hashing.

## Theme

Monokai-inspired dark theme:

```dart
background: 0xFF1E1E1E
surface:    0xFF252525
hover:      0xFF2A2A2A
comment:    0xFF808080
cyan:       0xFF66D9EF
green:      0xFFA6E22E
orange:     0xFFFD971F
pink:       0xFFF92672
```

## Known Issues

- Chat context doesn't scope correctly (shows workspace chat when in board)
- Element count badges in BoardGridView showing 0
- Large .dylib/.a files need Git LFS or exclusion from repo

## Next Steps

1. FAISS integration for search
2. Whiteboard canvas polish
3. File drag-drop
4. iPhone layout (masonry + bottom bar)
