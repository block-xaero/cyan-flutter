# Manual Patches Required

These fixes are needed in your existing files that weren't in the batch.

## 1. lib/services/identity_service.dart (line ~103)

**Error:** `Property 'isNotEmpty' cannot be accessed on 'String?' because it is potentially null`

**Find this:**
```dart
nodeId: nodeId.isNotEmpty ? nodeId : null,
```

**Replace with:**
```dart
nodeId: (nodeId?.isNotEmpty ?? false) ? nodeId : null,
```

---

## 2. lib/providers/chat_provider.dart (line ~87-90)

**Error:** `The argument type 'Map<String, dynamic>?' can't be assigned to 'String'`

`CyanFFI.getMyProfile()` now returns a `Map<String, dynamic>?` directly, not a JSON string.

**Find this:**
```dart
final myProfile = CyanFFI.getMyProfile();
final profile = jsonDecode(myProfile) as Map<String, dynamic>;
```

**Replace with:**
```dart
final profile = CyanFFI.getMyProfile();
if (profile == null) return;
```

Then use `profile['node_id']` and `profile['display_name']` directly.

---

## Quick sed commands (run from ~/cyan_flutter):

```bash
# Fix 1: identity_service.dart
sed -i '' 's/nodeId\.isNotEmpty/(nodeId?.isNotEmpty ?? false)/g' lib/services/identity_service.dart

# Fix 2: chat_provider.dart - this one needs manual edit since it's multi-line
```

For chat_provider.dart, open it and change the getMyProfile usage - it no longer needs jsonDecode.
