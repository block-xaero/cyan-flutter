// services/google_oauth.dart
// Google OAuth with localhost callback server
// Matches Swift GoogleAuthManager + OAuthCallbackServer pattern
// Production: Opens system browser, listens on localhost for redirect

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================================
// GOOGLE OAUTH CONFIG
// ============================================================================

class GoogleOAuthConfig {
  // Your Google Cloud OAuth Client ID (Desktop/Web type)
  // For macOS desktop: use "Desktop" application type in Google Cloud Console
  // Redirect to localhost - Google allows this for native apps
  static const clientId = '***REMOVED***';
  static const scopes = 'openid email profile';
  static const tokenUrl = 'https://oauth2.googleapis.com/token';

  /// Build authorization URL with PKCE and localhost redirect
  static String authorizationUrl({
    required int port,
    required String codeVerifier,
    required String state,
  }) {
    // PKCE: code_challenge = base64url(sha256(code_verifier))
    // For desktop apps, we use plain method since we control the redirect
    final redirectUri = 'http://127.0.0.1:$port/callback';

    final params = {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes,
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
      'code_challenge': codeVerifier,
      'code_challenge_method': 'plain',
    };

    final queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'https://accounts.google.com/o/oauth2/v2/auth?$queryString';
  }
}

// ============================================================================
// OAUTH RESULT
// ============================================================================

class GoogleOAuthResult {
  final String email;
  final String? name;
  final String? picture;
  final String accessToken;
  final String? refreshToken;
  final String idToken;

  GoogleOAuthResult({
    required this.email,
    this.name,
    this.picture,
    required this.accessToken,
    this.refreshToken,
    required this.idToken,
  });
}

// ============================================================================
// GOOGLE AUTH MANAGER
// ============================================================================

class GoogleAuthManager {
  HttpServer? _server;
  bool _isAuthenticating = false;

  bool get isAuthenticating => _isAuthenticating;

  /// Start the full Google OAuth flow
  /// 1. Start localhost callback server
  /// 2. Open system browser to Google auth
  /// 3. Wait for redirect with auth code
  /// 4. Exchange code for tokens
  /// 5. Decode JWT for user info
  Future<GoogleOAuthResult> authenticate() async {
    if (_isAuthenticating) {
      throw GoogleAuthError('Authentication already in progress');
    }

    _isAuthenticating = true;

    try {
      // Generate PKCE verifier and state
      final codeVerifier = _generateRandomString(64);
      final state = _generateRandomString(32);

      // Find available port and start callback server
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      final port = server.port;
      debugPrint('🔐 OAuth callback server listening on port $port');

      // Build auth URL
      final authUrl = GoogleOAuthConfig.authorizationUrl(
        port: port,
        codeVerifier: codeVerifier,
        state: state,
      );

      // Open browser
      final uri = Uri.parse(authUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw GoogleAuthError('Could not open browser for authentication');
      }

      // Wait for callback with timeout
      final completer = Completer<String>();

      server.listen((request) {
        if (request.uri.path == '/callback') {
          final code = request.uri.queryParameters['code'];
          final returnedState = request.uri.queryParameters['state'];
          final error = request.uri.queryParameters['error'];

          if (error != null) {
            // Send error page
            _sendHtmlResponse(request, _errorHtml(error));
            if (!completer.isCompleted) {
              completer.completeError(GoogleAuthError('Google auth error: $error'));
            }
          } else if (code != null && returnedState == state) {
            // Send success page
            _sendHtmlResponse(request, _successHtml);
            if (!completer.isCompleted) {
              completer.complete(code);
            }
          } else {
            _sendHtmlResponse(request, _errorHtml('Invalid callback'));
            if (!completer.isCompleted) {
              completer.completeError(GoogleAuthError('Invalid state parameter'));
            }
          }
        } else {
          request.response
            ..statusCode = 404
            ..write('Not found')
            ..close();
        }
      });

      // Wait for auth code with 5 minute timeout
      final code = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw GoogleAuthError('Authentication timed out'),
      );

      // Shut down callback server
      await _cleanup();

      // Exchange code for tokens
      final redirectUri = 'http://127.0.0.1:$port/callback';
      final tokenResult = await _exchangeCodeForTokens(code, redirectUri, codeVerifier);

      // Decode ID token for user info
      final userInfo = _decodeIdToken(tokenResult['id_token'] as String);

      return GoogleOAuthResult(
        email: userInfo['email'] as String,
        name: userInfo['name'] as String?,
        picture: userInfo['picture'] as String?,
        accessToken: tokenResult['access_token'] as String,
        refreshToken: tokenResult['refresh_token'] as String?,
        idToken: tokenResult['id_token'] as String,
      );
    } catch (e) {
      await _cleanup();
      rethrow;
    } finally {
      _isAuthenticating = false;
    }
  }

  /// Cancel authentication
  Future<void> cancel() async {
    await _cleanup();
    _isAuthenticating = false;
  }

  Future<void> _cleanup() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }

  // ---- TOKEN EXCHANGE ----

  Future<Map<String, dynamic>> _exchangeCodeForTokens(
    String code,
    String redirectUri,
    String codeVerifier,
  ) async {
    final client = HttpClient();

    try {
      final request = await client.postUrl(Uri.parse(GoogleOAuthConfig.tokenUrl));
      request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');

      final body = {
        'client_id': GoogleOAuthConfig.clientId,
        'code': code,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'client_secret': '***REMOVED***',
        'code_verifier': codeVerifier,
      };

      final encodedBody = body.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      request.write(encodedBody);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('🔐 Token exchange failed: $responseBody');
        throw GoogleAuthError('Token exchange failed (${response.statusCode})');
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;

      if (!json.containsKey('access_token') || !json.containsKey('id_token')) {
        throw GoogleAuthError('Missing tokens in response');
      }

      return json;
    } finally {
      client.close();
    }
  }

  // ---- JWT DECODE ----

  Map<String, dynamic> _decodeIdToken(String idToken) {
    // JWT: header.payload.signature
    final parts = idToken.split('.');
    if (parts.length < 2) {
      throw GoogleAuthError('Invalid ID token format');
    }

    // Decode payload (middle part)
    var base64Payload = parts[1];
    // Pad to multiple of 4
    while (base64Payload.length % 4 != 0) {
      base64Payload += '=';
    }
    // Replace URL-safe chars
    base64Payload = base64Payload
        .replaceAll('-', '+')
        .replaceAll('_', '/');

    final payloadBytes = base64Decode(base64Payload);
    final payload = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;

    final email = payload['email'] as String?;
    if (email == null) {
      throw GoogleAuthError('No email in ID token');
    }

    debugPrint('📷 Google profile: ${payload['name']}, picture: ${payload['picture']}');

    return {
      'email': email,
      'name': payload['name'] as String?,
      'picture': payload['picture'] as String?,
    };
  }

  // ---- HTML RESPONSES ----

  void _sendHtmlResponse(HttpRequest request, String html) {
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(html)
      ..close();
  }

  static const _successHtml = '''
<!DOCTYPE html>
<html>
<head>
<style>
  body {
    background: #1e1e1e; color: #f8f8f2; font-family: -apple-system, system-ui, sans-serif;
    display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0;
  }
  .container { text-align: center; }
  .icon { font-size: 64px; margin-bottom: 16px; }
  h1 { color: #66d9ef; font-size: 24px; margin-bottom: 8px; }
  p { color: #75715e; font-size: 14px; }
</style>
</head>
<body>
<div class="container">
  <div class="icon">✅</div>
  <h1>Signed in to Cyan</h1>
  <p>You can close this tab and return to the app.</p>
</div>
</body>
</html>
''';

  String _errorHtml(String error) => '''
<!DOCTYPE html>
<html>
<head>
<style>
  body {
    background: #1e1e1e; color: #f8f8f2; font-family: -apple-system, system-ui, sans-serif;
    display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0;
  }
  .container { text-align: center; }
  .icon { font-size: 64px; margin-bottom: 16px; }
  h1 { color: #f92672; font-size: 24px; margin-bottom: 8px; }
  p { color: #75715e; font-size: 14px; }
</style>
</head>
<body>
<div class="container">
  <div class="icon">❌</div>
  <h1>Authentication Failed</h1>
  <p>$error</p>
  <p>Please close this tab and try again.</p>
</div>
</body>
</html>
''';

  // ---- HELPERS ----

  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

// ============================================================================
// ERROR
// ============================================================================

class GoogleAuthError implements Exception {
  final String message;
  GoogleAuthError(this.message);

  @override
  String toString() => message;
}
