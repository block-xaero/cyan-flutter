// test/roster_panel_test.dart
//
// PARITY face `settings_identity` — the Peers roster. Tier-1: drives
// `ParityRosterPanel` through the `CyanBackend` seam (FakeCyanBackend) and
// asserts the persistent roster (offline members kept with cached names), the
// presence lines, the craft roles the mesh stamped, and the "just you" copy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/widgets/parity/parity_roster_panel.dart';

import 'support/parity_test_harness.dart';

const Size _panel = Size(380, 460);

void main() {
  testWidgets('the roster panel lists group members and their roles',
      (tester) async {
    final backend = FakeCyanBackend();
    await pumpParity(
      tester,
      const ParityRosterPanel(groupId: 'g-eng', boardId: 'b-eng-1'),
      backend: backend,
      size: _panel,
    );

    expect(find.text('Peers'), findsOneWidget);
    expect(find.text('4 of 5 online'), findsOneWidget);

    // Every member — the live neighbours AND the offline half, which keeps its
    // cached name rather than dropping off the roster.
    expect(find.text('Ada Byron'), findsOneWidget);
    expect(find.text('Mara'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Ravi Shah'), findsOneWidget);
    // No cached profile name yet ⇒ the short id, never a raw node id.
    expect(find.text('node-jun'), findsOneWidget);

    expect(find.text('Active now'), findsNWidgets(4));
    expect(find.textContaining('Last seen'), findsOneWidget);

    // The roles are the craft roles the ENGINE stamped as note provenance —
    // never invented. Nobody has stamped one for Mara, Priya or node-jun.
    expect(find.text('producer'), findsOneWidget); // Ada Byron authored as one
    expect(find.text('editor'), findsOneWidget); // Ravi Shah
    expect(find.text('unassigned'), findsNWidgets(3));
  });

  testWidgets('the roster reflects the craft role this device saved',
      (tester) async {
    final backend = FakeCyanBackend();
    // The pref Settings writes is what this device authors as from now on.
    expect(await backend.setProductionRole('colorist'), isTrue);

    await pumpParity(
      tester,
      const ParityRosterPanel(groupId: 'g-eng', boardId: 'b-eng-1'),
      backend: backend,
      size: _panel,
    );

    expect(find.text('you'), findsOneWidget);
    expect(find.text('colorist'), findsOneWidget);
    // The stale provenance no longer wins over the device's own pref.
    expect(find.text('producer'), findsNothing);
  });

  testWidgets('a group with no other members reads just you', (tester) async {
    await pumpParity(
      tester,
      const ParityRosterPanel(groupId: 'g-nobody'),
      backend: FakeCyanBackend(),
      size: _panel,
    );

    expect(find.text('Just you — invite someone to collaborate.'),
        findsOneWidget);
  });
}
