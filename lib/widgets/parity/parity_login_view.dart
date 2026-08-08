// widgets/parity/parity_login_view.dart
//
// PARITY port of the SwiftUI `LoginView` (Cyan/Cyan/Views/Auth/LoginView.swift):
// the two-mode front door.
//
//   • Personal / sovereign — create a XaeroID on this device (no account, no
//     network, fully offline), or restore an existing one from a QR / backup key.
//   • Organization (SSO)   — an optional tenant, then sign in through the org's
//     IdP; the broker returns a signed, expiring, XaeroID-bound grant.
//
// This screen is PRE-SESSION: login happens before there is a backend session,
// so it deliberately takes plain callbacks rather than going through the
// `CyanBackend` seam. Everything else follows the parity house style (Monokai
// colours, no hard-coded palette).

import 'package:flutter/material.dart';

import '../../theme/monokai_theme.dart';

/// The two clear sign-in modes of the front door.
enum LoginMode {
  personal('Personal'),
  organization('Organization');

  const LoginMode(this.title);
  final String title;
}

class ParityLoginView extends StatefulWidget {
  /// Rendered in a red notice box when non-null.
  final String? errorMessage;

  /// Covers the screen with a progress overlay while a login is in flight.
  final bool isLoading;

  /// Sovereign default — generate a XaeroID on this device.
  final VoidCallback? onCreateIdentity;

  /// Restore an existing XaeroID (scan QR / backup key).
  final VoidCallback? onRestore;

  /// Organization SSO; carries the (possibly empty) tenant that was typed.
  final void Function(String tenant)? onSsoSignIn;

  const ParityLoginView({
    super.key,
    this.errorMessage,
    this.isLoading = false,
    this.onCreateIdentity,
    this.onRestore,
    this.onSsoSignIn,
  });

  @override
  State<ParityLoginView> createState() => _ParityLoginViewState();
}

class _ParityLoginViewState extends State<ParityLoginView> {
  LoginMode _mode = LoginMode.personal;
  final TextEditingController _org = TextEditingController();

  @override
  void dispose() {
    _org.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MonokaiTheme.background,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _BrandBlock(),
                    const SizedBox(height: 28),
                    _ModePicker(
                      mode: _mode,
                      onChanged: (m) => setState(() => _mode = m),
                    ),
                    const SizedBox(height: 20),
                    if (widget.errorMessage != null) ...[
                      _NoticeBox(
                        key: const ValueKey('login-error'),
                        text: widget.errorMessage!,
                        tint: MonokaiTheme.red,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_mode == LoginMode.personal)
                      _PersonalSection(
                        onCreateIdentity: widget.onCreateIdentity,
                        onRestore: widget.onRestore,
                      )
                    else
                      _OrganizationSection(
                        controller: _org,
                        onSsoSignIn: widget.onSsoSignIn,
                      ),
                    const SizedBox(height: 24),
                    const _Footer(),
                  ],
                ),
              ),
            ),
          ),
          if (widget.isLoading) const _LoadingOverlay(),
        ],
      ),
    );
  }
}

// MARK: - Brand block

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  /// Swift's `CyanBrandLogo` defaults to 72pt; the corner radius is derived
  /// from it, so the two must stay together.
  static const double _brandMarkSize = 76;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // THE BRAND MARK — the real the-cyan.com icon, not a stand-in.
        //
        // This used to draw `Icons.hexagon_outlined` inside a cyan ring, with a
        // comment admitting it was "a hex-ish cyan glyph standing in for
        // CyanBrandLogo". The actual asset was in the repo the whole time and
        // simply never bundled: `assets/icons/app_icon.png` is BYTE-IDENTICAL
        // to cyan-iOS's `CyanBrandMark.imageset/cyan-wordmark.png` (same
        // sha256, 1024x1024), and pubspec had no `assets:` key at all, so
        // nothing could load it.
        //
        // Swift's `CyanBrandLogo` clips the asset to `size * 0.22` because the
        // artwork bakes its own dark rounded tile and the square corners would
        // otherwise show against the login ground. Same radius here, for the
        // same reason — and it is the same file the Windows app icon is built
        // from, so the login screen and the taskbar show one mark.
        ClipRRect(
          borderRadius: BorderRadius.circular(_brandMarkSize * 0.22),
          child: Image.asset(
            'assets/icons/app_icon.png',
            width: _brandMarkSize,
            height: _brandMarkSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: 'Cyan',
            // A missing asset must not take the front door down with it: the
            // wordmark below still names the app.
            errorBuilder: (_, __, ___) => const SizedBox(
              width: _brandMarkSize,
              height: _brandMarkSize,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Cyan',
            style: MonokaiTheme.displayLarge
                .copyWith(color: MonokaiTheme.foreground)),
        const SizedBox(height: 8),
        Text('Decentralized Collaboration',
            style:
                MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.comment)),
      ],
    );
  }
}

// MARK: - Mode picker (the two clear modes)

class _ModePicker extends StatelessWidget {
  final LoginMode mode;
  final ValueChanged<LoginMode> onChanged;

  const _ModePicker({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              const ValueKey('login-mode-personal'),
              LoginMode.personal,
              Icons.person_outline,
            ),
          ),
          Expanded(
            child: _segment(
              const ValueKey('login-mode-organization'),
              LoginMode.organization,
              Icons.apartment,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(Key key, LoginMode m, IconData icon) {
    final selected = m == mode;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(m),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? MonokaiTheme.cyan.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? MonokaiTheme.cyan : MonokaiTheme.comment),
            const SizedBox(width: 6),
            Text(
              m.title,
              style: MonokaiTheme.labelLarge.copyWith(
                color: selected ? MonokaiTheme.cyan : MonokaiTheme.comment,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Personal / sovereign

class _PersonalSection extends StatelessWidget {
  final VoidCallback? onCreateIdentity;
  final VoidCallback? onRestore;

  const _PersonalSection({this.onCreateIdentity, this.onRestore});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PRIMARY: the sovereign default — zero account, zero network.
        _PrimaryButton(
          key: const ValueKey('login-create-identity'),
          icon: Icons.vpn_key,
          label: 'Create your identity (no account)',
          onTap: onCreateIdentity,
        ),
        const SizedBox(height: 12),
        Text(
          'Generates a XaeroID on this device — works fully offline.',
          textAlign: TextAlign.center,
          style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment),
        ),
        const SizedBox(height: 16),
        // RESTORE — scan a QR or paste a backup key.
        _SecondaryButton(
          key: const ValueKey('login-restore'),
          icon: Icons.qr_code_scanner,
          label: 'Restore (Scan QR · Backup key)',
          onTap: onRestore,
        ),
        const SizedBox(height: 16),
        Text(
          'Your XaeroID never leaves this device — no account is created and no '
          'network is used.',
          textAlign: TextAlign.center,
          style: MonokaiTheme.labelSmall.copyWith(
            color: MonokaiTheme.comment.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

// MARK: - Organization (SSO)

class _OrganizationSection extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String tenant)? onSsoSignIn;

  const _OrganizationSection({required this.controller, this.onSsoSignIn});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: MonokaiTheme.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: MonokaiTheme.comment.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            key: const ValueKey('login-org-field'),
            controller: controller,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            style: MonokaiTheme.bodyMedium
                .copyWith(color: MonokaiTheme.foreground),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              hintText: 'Organization (optional)',
              hintStyle:
                  MonokaiTheme.bodyMedium.copyWith(color: MonokaiTheme.comment),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          key: const ValueKey('login-sso-signin'),
          icon: Icons.business,
          label: 'Sign in with your organization',
          onTap:
              onSsoSignIn == null ? null : () => onSsoSignIn!(controller.text),
        ),
        const SizedBox(height: 16),
        Text(
          'Single sign-on via your IdP (Google · Okta · Entra). We bind a '
          'signed, expiring grant to your XaeroID, then sign you in offline '
          'until it expires.',
          textAlign: TextAlign.center,
          style: MonokaiTheme.labelSmall.copyWith(
            color: MonokaiTheme.comment.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

// MARK: - Reusable label / row builders

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MonokaiTheme.cyan,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: MonokaiTheme.background),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: MonokaiTheme.titleMedium.copyWith(
                  color: MonokaiTheme.background,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SecondaryButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MonokaiTheme.cyan.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MonokaiTheme.cyan.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: MonokaiTheme.cyan),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style:
                    MonokaiTheme.labelLarge.copyWith(color: MonokaiTheme.cyan),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  final String text;
  final Color tint;

  const _NoticeBox({super.key, required this.text, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tint.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.foreground),
      ),
    );
  }
}

// MARK: - Footer (durable-XaeroID legibility)

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Your XaeroID is durable: it is created once on this device and is '
          'yours to keep — an organization grant only layers on top of it.',
          textAlign: TextAlign.center,
          style: MonokaiTheme.bodySmall.copyWith(color: MonokaiTheme.comment),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline,
                size: 12, color: MonokaiTheme.green.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'End-to-end encrypted · stays on your device',
                style: MonokaiTheme.labelSmall.copyWith(
                  color: MonokaiTheme.green.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// MARK: - Loading overlay

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: MonokaiTheme.background.withValues(alpha: 0.8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A DETERMINATE arc, deliberately: an indeterminate indicator
            // spins forever, which means the frame loop never quiesces and
            // any `pumpAndSettle` over this screen would hang. The cyan ring
            // plus the caption below carry the "busy" state.
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                value: 0.25,
                color: MonokaiTheme.cyan,
                backgroundColor: MonokaiTheme.surface,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text('Setting up…',
                style: MonokaiTheme.bodyMedium
                    .copyWith(color: MonokaiTheme.comment)),
          ],
        ),
      ),
    );
  }
}
