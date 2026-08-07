#!/bin/bash
# One-command sync: Mac feat/flutter-parity → cyan-win worktree (bundle over SSH).
set -e
cd "$(dirname "$0")"
git bundle create /tmp/cf-sync.bundle feat/flutter-parity 2>/dev/null
scp -q /tmp/cf-sync.bundle ricky@192.168.1.24:C:/cyan/cf-sync.bundle
ssh ricky@192.168.1.24 "cd C:\cyan\cyan_flutter && git fetch C:\cyan\cf-sync.bundle feat/flutter-parity:refs/heads/sync-tmp -f && git checkout -f sync-tmp && git branch -f feat/flutter-parity sync-tmp && git checkout feat/flutter-parity && git branch -D sync-tmp" 2>&1 | tail -1
echo "synced: $(git log --oneline -1)"
