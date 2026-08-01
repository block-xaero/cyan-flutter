// test/ops_metering_test.dart
//
// PARITY face `ops_metering` — the operations console's metering spine:
// the run list (with each run's terminal state), the run audit drill-down
// (per-step provenance), the run-scoped cost & usage panel, and the W11 trial
// banner / locked-surface states.
//
// Tier-1: every test drives the real widgets through the `CyanBackend` seam
// (FakeCyanBackend) — no dylib, no engine. The license clock is INJECTED
// (`nowSecs`) exactly as the SwiftUI `LicenseViewModel` injects `now`, so the
// countdown and the expiry are deterministic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/widgets/parity/parity_ops_metering.dart';
import 'package:cyan_flutter/widgets/parity/parity_run_audit.dart';

import 'support/parity_test_harness.dart';

/// The seeded grant's hard-stop (fixture epoch 2026-06-01 + 7 days).
final int _trialExpiry = DateTime.utc(2026, 6, 8).millisecondsSinceEpoch ~/ 1000;

/// Five whole days before the hard-stop.
final int _midTrial = DateTime.utc(2026, 6, 3).millisecondsSinceEpoch ~/ 1000;

/// A day past it.
final int _afterTrial = DateTime.utc(2026, 6, 9).millisecondsSinceEpoch ~/ 1000;

const Size _console = Size(1100, 800);

/// A tenant that has already PAID: no trial clock, so no banner and no lock.
class _PaidPlanBackend extends FakeCyanBackend {
  @override
  Future<String?> cachedEntitlementJson() async => '{"tenant":"acme",'
      '"plan":"pro","seats":25,'
      '"features":{"lens":true,"codegen":true,"marketplace_publish":true},'
      '"meter":{"included_minutes":5000,"rate_cents_per_minute":3}}';
}

/// A plan that never included the Lens surface at all — locked on its own
/// terms, with the trial clock still running.
class _NoLensBackend extends FakeCyanBackend {
  @override
  Future<String?> cachedEntitlementJson() async => '{"tenant":"acme",'
      '"plan":"trial","seats":2,'
      '"features":{"lens":false,"codegen":true,"marketplace_publish":false},'
      '"trial_expiry":1780876800}';
}

void main() {
  // -------------------------------------------------------------------------
  // Behaviour 1 — the run list
  // -------------------------------------------------------------------------

  testWidgets('the operations console lists runs with their terminal state',
      (tester) async {
    await pumpParity(tester, ParityOpsMetering(nowSecs: _midTrial),
        size: _console);

    expect(find.text('Ops console'), findsOneWidget);
    expect(find.text('Metering'), findsOneWidget);

    // Every seeded run is listed.
    for (final id in const [
      'run-7f3a',
      'run-9c21',
      'run-4b88',
      'run-1de0',
      'run-2a55',
      'run-6e9b',
    ]) {
      expect(find.byKey(ValueKey('ops-run-$id')), findsOneWidget,
          reason: '$id should be listed');
    }

    // A SETTLED run names the state it ended in — two Done, one Failed.
    expect(find.text('terminal · Done'), findsNWidgets(2));
    expect(find.text('terminal · Failed'), findsOneWidget);
    expect(find.byKey(const ValueKey('ops-run-terminal-run-2a55')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('ops-run-terminal-run-6e9b')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('ops-run-terminal-run-4b88')),
        findsOneWidget);

    // A live run is explicitly still in flight — queued / running / approval
    // never read as a final outcome.
    expect(find.text('in flight'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('ops-run-live-run-9c21')), findsOneWidget);
    expect(find.byKey(const ValueKey('ops-run-live-run-1de0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ops-run-live-run-7f3a')), findsOneWidget);
    expect(find.byKey(const ValueKey('ops-run-terminal-run-9c21')),
        findsNothing);

    // The count the operator reads off the header agrees with the rows.
    expect(find.text('3 terminal'), findsOneWidget);

    // Selecting a run swaps the drill-down to it — the list is the way into
    // the audit, one run at a time.
    for (final id in const ['run-4b88', 'run-2a55', 'run-7f3a']) {
      await tester.tap(find.byKey(ValueKey('ops-run-$id')));
      await tester.pumpAndSettle();
      expect(find.text(id), findsOneWidget, reason: '$id should be audited');
    }

    // The failed run's audit carries the error class that stopped it.
    await tester.tap(find.byKey(const ValueKey('ops-run-run-4b88')));
    await tester.pumpAndSettle();
    expect(find.text('TranscodeError'), findsOneWidget);
    expect(find.text('Failed'), findsWidgets);
  });

  // -------------------------------------------------------------------------
  // Behaviour 2 — the run audit
  // -------------------------------------------------------------------------

  testWidgets('a run audit view shows per step provenance', (tester) async {
    await pumpParity(tester, const ParityRunAudit(runId: 'run-2a55'),
        size: const Size(780, 640));

    expect(find.text('Run audit'), findsOneWidget);
    expect(find.text('run-2a55'), findsOneWidget);

    // One rail per step, each naming what it did and who did it.
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('audit-step-$i')), findsOneWidget);
    }
    expect(find.text('Ingest assets'), findsOneWidget);
    expect(find.text('Transcode proxies'), findsOneWidget);
    expect(find.text('Producer approval'), findsOneWidget);
    expect(find.text('Publish to review'), findsOneWidget);
    expect(find.text('human'), findsOneWidget);

    // The per-step audit columns: the bill first, then internal COGS.
    expect(find.text('asset-min'), findsNWidgets(4));
    expect(find.text('billed'), findsNWidgets(4));
    expect(find.text('exec'), findsNWidgets(4));
    expect(find.text('gpu·int'), findsNWidgets(4));
    expect(find.text('tokens·int'), findsNWidgets(4));

    // The operational flags that explain the bill.
    expect(find.text('cache'), findsOneWidget); // reused → billed 0
    expect(find.text('retry'), findsOneWidget); // re-processed → flagged
    expect(find.text('bottleneck'), findsOneWidget); // the gate stall

    // The reconciled totals, summed from the rows underneath them.
    expect(find.text('Billed-min'), findsOneWidget);
    expect(find.text('5.4'), findsWidgets);
    expect(find.text('\$0.22'), findsWidgets); // total == step 0's bill
    expect(find.text('147.4s'), findsOneWidget); // Σ per-step wall
    expect(find.text('1660'), findsOneWidget); // Σ tokens (internal COGS)
    expect(find.textContaining('never billed'), findsOneWidget);

    // A step the lens never metered reads "—" rather than a fabricated zero.
    expect(find.text('—'), findsWidgets);

    // A FAILED run's provenance: the step that broke, its error class, and the
    // steps that never ran because of it.
    await pumpParity(tester, const ParityRunAudit(runId: 'run-4b88'),
        size: const Size(780, 640));
    expect(find.text('run-4b88'), findsOneWidget);
    expect(find.text('TranscodeError'), findsOneWidget);
    expect(find.text('Failed'), findsWidgets);
    expect(find.text('Pending'), findsNWidgets(3)); // never reached
    expect(find.text('Color pass'), findsOneWidget);
    expect(find.text('\$0.04'), findsWidgets); // Σ of the rows above

    // An IN-FLIGHT run audits too — the gate it is sitting on is Running.
    await pumpParity(tester, const ParityRunAudit(runId: 'run-7f3a'),
        size: const Size(780, 640));
    expect(find.text('run-7f3a'), findsOneWidget);
    expect(find.text('Running'), findsWidgets);
    expect(find.text('\$0.18'), findsWidgets);

    // A run the lens has not traced says so, rather than rendering a shell.
    await pumpParity(tester, const ParityRunAudit(runId: 'run-nope'),
        size: const Size(780, 640));
    expect(find.text("Couldn't load run audit"), findsOneWidget);
    expect(find.textContaining('no trace for this run'), findsOneWidget);
    expect(find.text('Step audit'), findsNothing);
  });

  test('the audit totals reconcile with the per-step rows', () async {
    final trace = await FakeCyanBackend().loadRunTrace('run-2a55');
    expect(trace, isNotNull);

    final stepMinutes = trace!.steps
        .map((s) => s.billedMinutesValue)
        .whereType<double>()
        .fold<double>(0, (a, b) => a + b);
    final stepCents = trace.steps
        .map((s) => s.billedCents)
        .whereType<double>()
        .fold<double>(0, (a, b) => a + b);

    expect(trace.billedMinutesRollup, closeTo(stepMinutes, 1e-9));
    expect(trace.billedCentsRollup, closeTo(stepCents, 1e-9));
    // …and with the run card the console lists (cost $0.22 / 5.4 billed-min).
    expect(trace.billedCentsRollup, closeTo(22.0, 1e-9));
    expect(trace.billedMinutesRollup, closeTo(5.4, 1e-9));
    // A cache hit bills nothing but still reports the minutes it saved.
    expect(trace.savedMinutesRollup, closeTo(5.4, 1e-9));
    // Tokens are internal COGS and are never folded into the bill.
    expect(trace.tokensRollup, 1660);
  });

  // -------------------------------------------------------------------------
  // Behaviour 3 — cost & usage
  // -------------------------------------------------------------------------

  testWidgets('the usage and cost panel reports tokens and spend for a run',
      (tester) async {
    await pumpParity(tester, const ParityUsageCostPanel(runId: 'run-2a55'),
        size: const Size(720, 380));

    expect(find.text('Cost & usage'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget); // the scope chip

    // Spend — the asset-minute bill, and only the bill.
    expect(find.text('Spend this run'), findsOneWidget);
    expect(find.text('\$0.22'), findsOneWidget);
    expect(find.text('Billed min'), findsOneWidget);

    // Tokens — internal COGS, labelled as such.
    expect(find.text('Tokens in'), findsOneWidget);
    expect(find.text('480'), findsOneWidget);
    expect(find.text('Tokens out'), findsOneWidget);
    expect(find.text('1180'), findsOneWidget);
    expect(find.text('Tokens total'), findsOneWidget);
    expect(find.text('1660'), findsOneWidget);

    // The money-back line only appears because a step really was reused.
    expect(find.text('Saved via cache'), findsOneWidget);
    expect(find.text('5.4 min'), findsOneWidget);

    // Spend attributed per step.
    expect(find.text('Spend by step'), findsOneWidget);

    // Each run reports ITS OWN tokens and spend.
    await pumpParity(tester, const ParityUsageCostPanel(runId: 'run-4b88'),
        size: const Size(720, 380));
    expect(find.text('\$0.04'), findsOneWidget);
    expect(find.text('60'), findsOneWidget); // tokens in
    expect(find.text('140'), findsOneWidget); // tokens out
    expect(find.text('200'), findsOneWidget); // tokens total
    // Nothing was reused on that run, so no saving is claimed.
    expect(find.text('Saved via cache'), findsNothing);

    await pumpParity(tester, const ParityUsageCostPanel(runId: 'run-7f3a'),
        size: const Size(720, 380));
    expect(find.text('\$0.18'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(find.text('420'), findsOneWidget);
    expect(find.text('570'), findsOneWidget);

    // An untraced run reports no usage rather than a fabricated zero.
    await pumpParity(tester, const ParityUsageCostPanel(runId: 'run-nope'),
        size: const Size(720, 380));
    expect(find.text('Cost & usage'), findsOneWidget);
    expect(find.text('No usage recorded for this run yet.'), findsOneWidget);
    expect(find.text('\$0.00'), findsNothing);
    expect(find.text('Spend by step'), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Behaviour 4 — trial + license state
  // -------------------------------------------------------------------------

  testWidgets(
      'a trial banner reports remaining days and an expired state locks paid surfaces',
      (tester) async {
    // Mid-trial: the banner counts down and the metered panes are open.
    await pumpParity(
        tester, ParityOpsMetering(nowSecs: _midTrial, isAdmin: true),
        size: _console);

    expect(find.byKey(const ValueKey('trial-banner')), findsOneWidget);
    expect(find.text('5 days left in your trial'), findsOneWidget);
    expect(find.text('Trial · 5 seats'), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-cost-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('locked-surface')), findsNothing);

    // The last partial day still reads as a whole day, never "0 days".
    await pumpParity(
        tester, ParityOpsMetering(nowSecs: _trialExpiry - 3600, isAdmin: true),
        size: _console);
    expect(find.text('1 day left in your trial'), findsOneWidget);
    expect(find.byKey(const ValueKey('locked-surface')), findsNothing);

    // Past the hard-stop: the banner flips and the paid surfaces lock.
    await pumpParity(
        tester, ParityOpsMetering(nowSecs: _afterTrial, isAdmin: true),
        size: _console);

    expect(find.text('Your trial has ended — paid features are locked.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('locked-surface')), findsOneWidget);
    expect(find.text('Upgrade to unlock'), findsOneWidget);
    expect(find.text('Upgrade your plan to unlock Lens runs.'), findsOneWidget);

    // The metered panes are gone…
    expect(find.byKey(const ValueKey('usage-cost-panel')), findsNothing);
    expect(find.text('Run audit'), findsNothing);
    // …but the local read is NEVER gated: the run list still lists runs with
    // their terminal state.
    expect(find.byKey(const ValueKey('ops-run-run-2a55')), findsOneWidget);
    expect(find.text('terminal · Done'), findsNWidgets(2));

    // A locked NON-admin is pointed at their admin instead of an upgrade.
    await pumpParity(tester, ParityOpsMetering(nowSecs: _afterTrial),
        size: _console);
    expect(find.text('Ask your admin'), findsOneWidget);
    expect(
        find.text(
            'Lens runs is locked on your plan. Ask your admin to upgrade.'),
        findsOneWidget);
    expect(find.text('Upgrade to unlock'), findsNothing);
    expect(find.textContaining('Local & LAN work keeps working'),
        findsOneWidget);

    // A PAID plan has no trial clock: no banner, and nothing locked.
    await pumpParity(
        tester, ParityOpsMetering(nowSecs: _afterTrial, isAdmin: true),
        backend: _PaidPlanBackend(), size: _console);
    expect(find.byKey(const ValueKey('trial-banner')), findsNothing);
    expect(find.byKey(const ValueKey('locked-surface')), findsNothing);
    expect(find.byKey(const ValueKey('usage-cost-panel')), findsOneWidget);

    // A plan that never included Lens is locked while the trial still runs —
    // the lock is the plan's, not only the clock's.
    await pumpParity(
        tester, ParityOpsMetering(nowSecs: _midTrial, isAdmin: true),
        backend: _NoLensBackend(), size: _console);
    expect(find.byKey(const ValueKey('trial-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('locked-surface')), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-cost-panel')), findsNothing);
  });

  test('the cached grant decodes, counts down, and gates by tenant', () async {
    final json = await FakeCyanBackend().cachedEntitlementJson();
    final entitlement = Entitlement.decode(json!);
    expect(entitlement, isNotNull);
    expect(entitlement!.tenant, 'acme');
    expect(entitlement.plan, Plan.trial);
    expect(entitlement.seats, 5);
    expect(entitlement.trialExpiry, _trialExpiry);
    expect(entitlement.meter.includedMinutes, 500);

    // The countdown rounds UP, so the last partial day still reads "1 day".
    expect(entitlement.trialDaysLeft(_midTrial), 5);
    expect(entitlement.trialDaysLeft(_trialExpiry - 1), 1);
    expect(entitlement.trialDaysLeft(_afterTrial), 0);
    expect(entitlement.isExpired(_midTrial), isFalse);
    expect(entitlement.isExpired(_afterTrial), isTrue);

    final live = LicenseModel(
        entitlement: entitlement, tenant: 'acme', nowSecs: _midTrial);
    expect(live.trialBannerText, '5 days left in your trial');
    expect(live.isLocked(PaidSurface.lensRun), isFalse);
    expect(live.isLocked(PaidSurface.localCollab), isFalse);

    final expired = LicenseModel(
        entitlement: entitlement, tenant: 'acme', nowSecs: _afterTrial);
    expect(expired.isLocked(PaidSurface.lensRun), isTrue);
    expect(expired.isLocked(PaidSurface.codegen), isTrue);
    // Graceful expiry: local + LAN collaboration is never gated.
    expect(expired.isLocked(PaidSurface.localCollab), isFalse);
    expect(expired.gate(PaidSurface.lensRun).showsAskAdmin, isTrue);
    expect(
        LicenseModel(
                entitlement: entitlement,
                tenant: 'acme',
                isAdmin: true,
                nowSecs: _afterTrial)
            .gate(PaidSurface.lensRun)
            .showsUpgrade,
        isTrue);

    // Tenant isolation: a grant never authorizes another tenant.
    final otherTenant = LicenseModel(
        entitlement: entitlement, tenant: 'globex', nowSecs: _midTrial);
    expect(otherTenant.isLocked(PaidSurface.lensRun), isTrue);
    expect(otherTenant.isLocked(PaidSurface.localCollab), isTrue);
  });

  test('an uncached device falls back to a full offline trial', () {
    const now = 1780000000;
    final fallback = Entitlement.offlineDefault('local', now);
    expect(fallback.plan.isTrial, isTrue);
    expect(fallback.trialDaysLeft(now), 7);
    expect(
        LicenseModel(entitlement: fallback, tenant: 'local', nowSecs: now)
            .isLocked(PaidSurface.lensRun),
        isFalse);
    // A malformed grant decodes to nothing rather than a half-built one.
    expect(Entitlement.decode('{"plan":"trial"}'), isNull);
    expect(Entitlement.decode('not json'), isNull);
  });

  // -------------------------------------------------------------------------
  // Golden
  // -------------------------------------------------------------------------

  testWidgets('golden: ops metering console', (tester) async {
    await pumpParity(tester, ParityOpsMetering(nowSecs: _midTrial),
        size: _console);
    await expectLater(
      find.byType(ParityOpsMetering),
      matchesGoldenFile('golden/ops_metering.png'),
    );
  }, tags: 'golden');
}
