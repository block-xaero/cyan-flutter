// storage_migration.rs
// Add this to your run_migrations() function in storage.rs

/*
Add to run_migrations() in storage.rs to fix the owner_node_id column issue:

```rust
pub fn run_migrations(conn: &Connection) -> Result<()> {
    // ... existing migrations ...
    
    // Migration: Add owner_node_id column to groups if missing
    if conn.prepare("SELECT owner_node_id FROM groups LIMIT 1").is_err() {
        tracing::info!("Migration: adding owner_node_id column to groups");
        conn.execute("ALTER TABLE groups ADD COLUMN owner_node_id TEXT", [])?;
    }
    
    // Migration: Add owner_node_id column to workspaces if missing
    if conn.prepare("SELECT owner_node_id FROM workspaces LIMIT 1").is_err() {
        tracing::info!("Migration: adding owner_node_id column to workspaces");
        conn.execute("ALTER TABLE workspaces ADD COLUMN owner_node_id TEXT", [])?;
    }
    
    // Migration: Add owner_node_id column to objects if missing
    if conn.prepare("SELECT owner_node_id FROM objects LIMIT 1").is_err() {
        tracing::info!("Migration: adding owner_node_id column to objects");
        conn.execute("ALTER TABLE objects ADD COLUMN owner_node_id TEXT", [])?;
    }
    
    Ok(())
}
```

OR update ensure_schema() to include owner_node_id in the initial CREATE TABLE:

```rust
pub fn ensure_schema(conn: &Connection) -> Result<()> {
    conn.execute_batch(r#"
        CREATE TABLE IF NOT EXISTS groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            icon TEXT NOT NULL,
            color TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            owner_node_id TEXT
        );
        
        CREATE TABLE IF NOT EXISTS workspaces (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            owner_node_id TEXT,
            FOREIGN KEY (group_id) REFERENCES groups(id)
        );
        
        CREATE TABLE IF NOT EXISTS objects (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            board_type TEXT DEFAULT 'canvas',
            owner_node_id TEXT,
            FOREIGN KEY (workspace_id) REFERENCES workspaces(id)
        );
        
        -- ... rest of schema ...
    "#)?;
    
    Ok(())
}
```

MANUAL FIX (already applied):
```bash
sqlite3 ~/Library/Containers/com.example.cyanFlutter/Data/Documents/cyan.db \
  "ALTER TABLE groups ADD COLUMN owner_node_id TEXT;"
sqlite3 ~/Library/Containers/com.example.cyanFlutter/Data/Documents/cyan.db \
  "ALTER TABLE workspaces ADD COLUMN owner_node_id TEXT;"
sqlite3 ~/Library/Containers/com.example.cyanFlutter/Data/Documents/cyan.db \
  "ALTER TABLE objects ADD COLUMN owner_node_id TEXT;"
```
*/
