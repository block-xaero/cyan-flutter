# Push instructions (agent could not push — no GitHub creds in the sandbox)

The Phase-0 parity work is committed locally on branch **`feat/flutter-parity`**
(2 commits ahead of `main`, which is untouched). The agent's isolated workspace
has **no GitHub credentials** (no token, no SSH key, no `gh`), so it could not
`git push`. Run this on your Mac to trigger CI:

```bash
cd ~/cyan_flutter

# 1) Clear any stale git locks the gitstatusd daemon left behind (safe — repo
#    is not mid-operation; the interrupted rebase was already aborted):
rm -f .git/index.lock .git/HEAD.lock

# 2) Confirm you're on the right branch with the right commits:
git checkout feat/flutter-parity
git log --oneline main..feat/flutter-parity   # expect 2 parity commits

# 3) Push and set upstream so CI runs:
git push -u origin feat/flutter-parity
```

CI (`.github/workflows/flutter-parity.yml`) then runs `flutter pub get`,
`flutter analyze`, and `flutter test --exclude-tags golden` on a stable Flutter
runner. **CI is the first real signal** — the agent cannot run Flutter, so it has
not verified the Dart compiles.

You can delete this file after pushing.
