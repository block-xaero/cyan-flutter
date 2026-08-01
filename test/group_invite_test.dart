// test/group_invite_test.dart
//
// PARITY face `settings_identity` — the capability-grant invite. Tier-1: drives
// `ParityGroupInvite` through the `CyanBackend` seam (FakeCyanBackend) and
// rides the whole round trip: mint a signed grant QR for a {group, role}, then
// scan that very payload back and join. The refusal paths (forged payload,
// unknown group) come from the ENGINE, not from the screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/widgets/parity/parity_group_invite.dart';

import 'support/parity_test_harness.dart';

const Size _panel = Size(620, 1400);

void main() {
  testWidgets('a group invite can be issued and scanned', (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityGroupInvite(groupId: 'g-eng'),
        backend: backend, size: _panel);

    // Mint a grant for a role…
    await tester.tap(find.byKey(const ValueKey('invite-role-member')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('invite-issue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('invite-qr')), findsOneWidget);
    final payload = tester
        .widget<SelectableText>(find.byKey(const ValueKey('invite-payload')))
        .data!;
    expect(payload, contains('"group_id":"g-eng"'));
    expect(payload, contains('"role":"member"'));

    // …then scan that very payload: signature, group and expiry check out, so
    // the engine joins the group.
    await tester.enterText(
        find.byKey(const ValueKey('invite-scan-field')), payload);
    await tester.tap(find.byKey(const ValueKey('invite-scan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('invite-scan-joined')), findsOneWidget);
    expect(find.text('Joined Engineering'), findsOneWidget);
  });

  testWidgets('a forged invite is refused by the engine', (tester) async {
    await pumpParity(tester, const ParityGroupInvite(groupId: 'g-eng'),
        backend: FakeCyanBackend(), size: _panel);

    await tester.enterText(
        find.byKey(const ValueKey('invite-scan-field')), 'not-a-grant');
    await tester.tap(find.byKey(const ValueKey('invite-scan')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('invite-scan-error')), findsOneWidget);
    expect(find.textContaining('Grant rejected'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-scan-joined')), findsNothing);
  });

  testWidgets('an invite for a group this device is not in is refused',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(tester, const ParityGroupInvite(groupId: 'g-not-mine'),
        backend: backend, size: _panel);

    await tester.tap(find.byKey(const ValueKey('invite-issue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('invite-issue-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-qr')), findsNothing);
  });
}
