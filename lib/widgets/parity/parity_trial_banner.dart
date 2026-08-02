// widgets/parity/parity_trial_banner.dart
//
// PARITY port of the SwiftUI `TrialBanner` + `LockedSurface` components (the
// W11 license state, app side): the thin strip that counts a trial down to its
// hard-stop, and the locked/upgrade states the PAID surfaces (Lens runs,
// codegen, marketplace publish) show once it runs out.
//
// OFFLINE-SAFE and receive-only. The verdict is the engine's contract restated
// through `LicenseModel` / `EntitlementPolicy`, never a second authorization
// scheme — and local + LAN work is NEVER gated, so it never reaches the locked
// card. The banner reads the CACHED signed grant through the `CyanBackend` seam
// (via `entitlementProvider`); it never touches `CyanFFI` directly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/cyan_backend_provider.dart';
import '../../theme/monokai_theme.dart';

/// Build the license read-model over a cached grant. [tenant] defaults to the
/// grant's own tenant (the session this device signed the grant into);
/// [nowSecs] defaults to the wall clock and is injected by tests so the
/// countdown is deterministic.
LicenseModel buildLicense(
  Entitlement entitlement, {
  String? tenant,
  bool isAdmin = false,
  int? nowSecs,
}) {
  return LicenseModel(
    entitlement: entitlement,
    tenant: tenant ?? entitlement.tenant,
    isAdmin: isAdmin,
    nowSecs: nowSecs ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}

/// The trial strip: "N days left in your trial" while the clock runs, an ended
/// note once it stops. Renders NOTHING on a paid plan.
class ParityTrialBanner extends ConsumerWidget {
  /// The session tenant the grant must match; null ⇒ the grant's own.
  final String? tenant;

  /// Admin/Owner see the upgrade path; everyone else is pointed at their admin.
  final bool isAdmin;

  /// Injected unix-seconds clock (tests); null ⇒ the wall clock.
  final int? nowSecs;

  /// Upgrade tap — UI-only here; the host wires the purchase path.
  final VoidCallback? onUpgrade;

  const ParityTrialBanner({
    super.key,
    this.tenant,
    this.isAdmin = false,
    this.nowSecs,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlementAsync = ref.watch(entitlementProvider);
    return entitlementAsync.maybeWhen(
      data: (entitlement) {
        final license = buildLicense(entitlement,
            tenant: tenant, isAdmin: isAdmin, nowSecs: nowSecs);
        if (!license.showsTrialBanner) return const SizedBox.shrink();
        return TrialBannerStrip(license: license, onUpgrade: onUpgrade);
      },
      // A banner is chrome: while the grant loads (or if it cannot be read at
      // all) the surface below it stays usable rather than showing a shell.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// The banner itself — pure presentation over a resolved [LicenseModel].
class TrialBannerStrip extends StatelessWidget {
  final LicenseModel license;
  final VoidCallback? onUpgrade;

  const TrialBannerStrip({super.key, required this.license, this.onUpgrade});

  Color get _accent =>
      license.trialExpired ? MonokaiTheme.red : MonokaiTheme.yellow;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('trial-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(license.trialExpired ? Icons.lock : Icons.schedule,
              size: 16, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(license.trialBannerText,
                    style: MonokaiTheme.labelLarge
                        .copyWith(color: MonokaiTheme.foreground)),
                const SizedBox(height: 1),
                Text(
                  license.isAdmin
                      ? 'Upgrade anytime to keep Lens runs, codegen, and publishing.'
                      : 'Local & LAN work keeps working — paid cloud features pause.',
                  style: MonokaiTheme.labelSmall,
                ),
              ],
            ),
          ),
          Text('${license.planName} · ${license.seatCap} seats',
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.comment)),
          if (license.isAdmin) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onUpgrade,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Upgrade',
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.background)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The small inline lock chip that sits next to a gated action's label.
class ParityLockedBadge extends StatelessWidget {
  final SurfaceGate gate;
  const ParityLockedBadge({super.key, required this.gate});

  @override
  Widget build(BuildContext context) {
    if (!gate.locked) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MonokaiTheme.yellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock, size: 10, color: MonokaiTheme.yellow),
          const SizedBox(width: 4),
          Text(gate.isAdmin ? 'Upgrade' : 'Locked',
              style: MonokaiTheme.labelSmall
                  .copyWith(color: MonokaiTheme.yellow)),
        ],
      ),
    );
  }
}

/// The explanatory card a gated paid surface shows IN PLACE OF its content.
/// An admin/owner gets the upgrade (+ seats) path; a gated non-admin is told to
/// ask their admin.
class ParityLockedSurfaceCard extends StatelessWidget {
  final SurfaceGate gate;

  /// Optional seat summary an admin sees alongside the upgrade path.
  final String? seatSummary;

  /// Upgrade tap (admin only); null hides the button.
  final VoidCallback? onUpgrade;

  const ParityLockedSurfaceCard({
    super.key,
    required this.gate,
    this.seatSummary,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('locked-surface'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MonokaiTheme.yellow.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MonokaiTheme.yellow.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock, size: 18, color: MonokaiTheme.yellow),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gate.isAdmin ? 'Upgrade to unlock' : 'Ask your admin',
                    style: MonokaiTheme.titleSmall),
                const SizedBox(height: 4),
                Text(gate.message, style: MonokaiTheme.labelMedium),
                if (gate.isAdmin && seatSummary != null) ...[
                  const SizedBox(height: 4),
                  Text(seatSummary!,
                      style: MonokaiTheme.codeSmall
                          .copyWith(color: MonokaiTheme.comment)),
                ],
              ],
            ),
          ),
          if (gate.showsUpgrade && onUpgrade != null)
            GestureDetector(
              onTap: onUpgrade,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MonokaiTheme.yellow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Upgrade',
                    style: MonokaiTheme.labelMedium
                        .copyWith(color: MonokaiTheme.background)),
              ),
            ),
        ],
      ),
    );
  }
}
