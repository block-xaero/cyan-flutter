// config/secrets.template.dart
// Copy this file to secrets.dart and fill in your actual credentials
// secrets.dart is gitignored and should never be committed

class Secrets {
  // Google OAuth credentials from Google Cloud Console
  // Create at: https://console.cloud.google.com/apis/credentials
  // Use "Desktop" application type for macOS
  static const googleClientId = 'YOUR_CLIENT_ID.apps.googleusercontent.com';
  static const googleClientSecret = 'YOUR_CLIENT_SECRET';
}
