// widgets/parity/parity_onboarding_gate.dart
//
// PARITY port of the front-door SPINE: the thing that decides whether the app
// shows its login surface or its contents, and the signed-in identity panel
// that can put it back.
//
//   • Signed out → `ParityLoginView`, wired to the real session controller.
//       - Organization  → broker mints a grant, the ENGINE installs it, and
//                         the session captures the tenant it resolved.
//       - Personal      → anonymous entry: the ENGINE mints the handle. This is
//                         the SwiftUI "Create your identity (no account)" path —
//                         no account, no org, no tenant.
//   • Signed in  → the caller's [child], or (when there is none) the identity
//                  panel below, which is where Sign Out lives.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/Auth/LoginView.swift  — the two-mode front door
//   cyan-iOS/Cyan/Cyan/Views/ProfileView.swift     — `ssoSection` + Sign Out
//
// NOT ported here: Restore (Scan QR / backup key). That is the QR-scanner face
// (`Views/Auth/QRScannerView.swift`) and there is no identity-restore verb on
// the `CyanBackend` seam yet, so `ParityLoginView.onRestore` is left unwired
// rather than pointed at a stub that would pretend to restore something.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/onboarding_session_provider.dart';
import '../../theme/monokai_theme.dart';
import 'parity_login_view.dart';

class ParityOnboardingGate extends ConsumerWidget {
  /// What the app is, once there is a session. Null renders the identity panel,
  /// which is the smallest signed-in surface that can sign back out.
  final Widget? child;

  const ParityOnboardingGate({super.key, this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(onboardingSessionProvider);
    final controller = ref.read(onboardingSessionProvider.notifier);

    if (session.isSignedIn) {
      return child ?? const ParitySessionProfile();
    }

    return ParityLoginView(
      key: const ValueKey('onboarding-login'),
      errorMessage: session.error,
      isLoading: session.isBusy,
      // The sovereign default IS the anonymous entry — no account, no network,
      // no organization. The engine mints the handle it is seen behind.
      onCreateIdentity: controller.enterAnonymously,
      onSsoSignIn: controller.signInWithOrganization,
    );
  }
}

/// The signed-in identity panel — the SwiftUI `ProfileView`'s identity + SSO
/// session rows and its Sign Out button.
///
/// Every value here is what the ENGINE answered: the profile from `myProfile`,
/// the tenant and role from the grant it verified, the handle from the session
/// it minted. Nothing is a client-side copy.
class ParitySessionProfile extends ConsumerWidget {
  const ParitySessionProfile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(onboardingSessionProvider);
    final controller = ref.read(onboardingSessionProvider.notifier);

    return Material(
      color: MonokaiTheme.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              key: const ValueKey('session-profile'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Monogram(session: session),
                const SizedBox(height: 16),
                Text(
                  session.displayLabel,
                  textAlign: TextAlign.center,
                  style: MonokaiTheme.titleLarge
                      .copyWith(color: MonokaiTheme.foreground),
                ),
                const SizedBox(height: 6),
                Text(
                  session.isAnonymous
                      ? 'Entered anonymously — peers see this handle, not your '
                          'identity.'
                      : 'Signed in',
                  textAlign: TextAlign.center,
                  style: MonokaiTheme.bodySmall
                      .copyWith(color: MonokaiTheme.comment),
                ),
                const SizedBox(height: 24),

                // The ORGANIZATION half. Present only when a grant is installed
                // — an anonymous entry genuinely has no tenant, so the panel
                // shows none rather than an empty row.
                if (session.tenant.isNotEmpty) ...[
                  _SessionCard(
                    rows: [
                      _Row(
                        key: const ValueKey('session-tenant'),
                        label: 'Tenant',
                        value: session.tenant,
                      ),
                      if (session.role.isNotEmpty)
                        _Row(
                          key: const ValueKey('session-role'),
                          label: 'Role',
                          value: session.role,
                        ),
                      if (session.profile != null)
                        _Row(
                          key: const ValueKey('session-node'),
                          label: 'Device',
                          value: session.profile!.nodeId,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                if (session.isAnonymous) ...[
                  _SessionCard(
                    rows: [
                      _Row(
                        key: const ValueKey('session-anonymous-handle'),
                        label: 'Handle',
                        value: session.anonymous!.handle,
                      ),
                      _Row(
                        key: const ValueKey('session-anonymous-scope'),
                        label: 'Scope',
                        value: session.anonymous!.scopeId,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                _SignOutButton(onTap: controller.signOut),
                const SizedBox(height: 12),
                Text(
                  'Signing out drops this session. Your XaeroID stays on this '
                  'device.',
                  textAlign: TextAlign.center,
                  style: MonokaiTheme.labelSmall.copyWith(
                    color: MonokaiTheme.comment.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// MARK: - Pieces

class _Monogram extends StatelessWidget {
  final OnboardingSession session;

  const _Monogram({required this.session});

  /// The masked session shows a mask, not initials — a monogram taken from the
  /// handle would read like a real person's.
  @override
  Widget build(BuildContext context) {
    final anonymous = session.isAnonymous;
    final tint = anonymous ? MonokaiTheme.purple : MonokaiTheme.cyan;
    return Center(
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: tint.withValues(alpha: 0.5), width: 1.5),
        ),
        alignment: Alignment.center,
        child: anonymous
            ? Icon(Icons.masks_outlined, size: 30, color: tint)
            : Text(
                session.profile?.initials ?? '',
                style: MonokaiTheme.titleLarge.copyWith(color: tint),
              ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final List<Widget> rows;

  const _SessionCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: MonokaiTheme.comment.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                MonokaiTheme.labelMedium.copyWith(color: MonokaiTheme.comment)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: MonokaiTheme.bodySmall
                .copyWith(color: MonokaiTheme.foreground),
          ),
        ),
      ],
    );
  }
}

class _SignOutButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SignOutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('session-sign-out'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MonokaiTheme.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MonokaiTheme.red.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout, size: 15, color: MonokaiTheme.red),
            const SizedBox(width: 8),
            Text('Sign Out',
                style: MonokaiTheme.labelLarge
                    .copyWith(color: MonokaiTheme.red)),
          ],
        ),
      ),
    );
  }
}
