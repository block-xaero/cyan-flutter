# ============================================================
# v54: Real Auth System - Google OAuth + XaeroID
# ============================================================

# 1. Add dependencies to pubspec.yaml
cd ~/Projects/cyan_flutter  # or your project root

# Add these to pubspec.yaml under dependencies:
# url_launcher: ^6.2.0
# flutter_secure_storage: ^9.0.0
flutter pub add url_launcher flutter_secure_storage

# 2. Extract tarball (overwrites lib/)
tar -xzvf ~/Downloads/cyan_v54_auth.tar.gz -C .

# 3. macOS entitlements for Google OAuth localhost callback
# In macos/Runner/DebugProfile.entitlements AND macos/Runner/Release.entitlements,
# ensure these exist:
cat macos/Runner/DebugProfile.entitlements
# Should contain:
#   <key>com.apple.security.network.client</key>
#   <true/>
#   <key>com.apple.security.network.server</key>
#   <true/>

# If missing, add them:
/usr/libexec/PlistBuddy -c "Add :com.apple.security.network.server bool true" macos/Runner/DebugProfile.entitlements 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :com.apple.security.network.server bool true" macos/Runner/Release.entitlements 2>/dev/null

# 4. macOS Keychain entitlement for flutter_secure_storage
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" macos/Runner/DebugProfile.entitlements 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string '$(AppIdentifierPrefix)io.blockxaero.cyan'" macos/Runner/DebugProfile.entitlements 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" macos/Runner/Release.entitlements 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string '$(AppIdentifierPrefix)io.blockxaero.cyan'" macos/Runner/Release.entitlements 2>/dev/null

# 5. Build
flutter clean
flutter pub get
flutter run -d macos
