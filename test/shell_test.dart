// test/shell_test.dart
//
// PARITY face_shell — the icon rail + home shell + status gutter. Tier-1,
// fakes only: no native library, no network, no engine.
//
// Acceptance oracle for scripts/parity_faces/shell.txt, authored from the
// SwiftUI reference (read only):
//   cyan-iOS/Cyan/Cyan/Views/ContentView.swift        (authenticated -> shell)
//   cyan-iOS/Cyan/Cyan/Views/WorkspaceViewNew.swift   (rail | surface | bar)
//   cyan-iOS/Cyan/Cyan/Views/StatusBar.swift          (peers · state · profile)
//
// The shell under test is `ParityHomeShell`: five rail doors that each mount a
// REAL parity face, over the status gutter (`ParityStatusBar` + the identity
// chip). Everything drives through the `CyanBackend` seam, so `FakeCyanBackend`
// scripts the mesh and the identity with no dylib.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyan_flutter/ffi/fake_cyan_backend.dart';
import 'package:cyan_flutter/widgets/parity/parity_chat_view.dart';
import 'package:cyan_flutter/widgets/parity/parity_explorer_tree.dart';
import 'package:cyan_flutter/widgets/parity/parity_home_shell.dart';
import 'package:cyan_flutter/widgets/parity/parity_icon_rail.dart';
import 'package:cyan_flutter/widgets/parity/parity_marketplace.dart';
import 'package:cyan_flutter/widgets/parity/parity_status_bar.dart';

import 'support/parity_test_harness.dart';

void main() {
  Finder inRail(String label) => find.descendant(
        of: find.byType(ParityIconRail),
        matching: find.text(label),
      );

  Finder inBar(String text) => find.descendant(
        of: find.byType(ParityStatusBar),
        matching: find.text(text),
      );

  testWidgets(
      'the icon rail shows the Explorer, Boards, Chat, Lens and Market doors',
      (tester) async {
    await pumpParity(tester, const ParityHomeShell());

    for (final door in const ['Explorer', 'Boards', 'Chat', 'Lens', 'Market']) {
      expect(inRail(door), findsOneWidget,
          reason: 'the rail must advertise the $door door');
    }
  });

  testWidgets('selecting a rail door swaps the home surface', (tester) async {
    await pumpParity(tester, const ParityHomeShell());

    // The shell opens on the Explorer face.
    expect(find.byType(ParityExplorerTree), findsOneWidget);
    expect(find.byType(ParityMarketplace), findsNothing);

    // Open the Market door: the surface is REPLACED, not stacked.
    await tester.tap(inRail('Market'));
    await tester.pumpAndSettle();
    expect(find.byType(ParityMarketplace), findsOneWidget);
    expect(find.byType(ParityExplorerTree), findsNothing);

    // And again to Chat, off the marketplace.
    await tester.tap(inRail('Chat'));
    await tester.pumpAndSettle();
    expect(find.byType(ParityChatView), findsOneWidget);
    expect(find.byType(ParityMarketplace), findsNothing);
  });

  testWidgets('the status bar reports the peer count and mesh reachability',
      (tester) async {
    // A scripted mesh: 4 live neighbours -> reachable, honestly "Synced".
    final busy = FakeCyanBackend()
      ..setLivePeers({
        'g-eng': ['p1', 'p2', 'p3'],
        'g-post': ['p4'],
      });
    await pumpParity(tester, const ParityHomeShell(), backend: busy);
    final count =
        tester.widget<Text>(find.byKey(const ValueKey('statusbar-peer-count')));
    expect(count.data, '4',
        reason: 'the gutter must report the live peer count');
    expect(inBar('Synced'), findsOneWidget,
        reason: '≥1 peer and nothing pending is the one honest "Synced"');

    // An empty mesh: 0 peers may NEVER read "Synced" — that is the lie the
    // SyncStatusMachine was written to kill.
    final alone = FakeCyanBackend()..setLivePeers({});
    await pumpParity(tester, const ParityHomeShell(), backend: alone);
    expect(inBar('0'), findsOneWidget);
    expect(inBar('Local-only · no peers'), findsOneWidget,
        reason: 'an unreachable mesh must say so');
    expect(inBar('Synced'), findsNothing);
  });

  testWidgets('the status bar shows the signed-in identity', (tester) async {
    // The seeded device is signed in as Ada Byron — the same identity the
    // roster carries this device's node id under.
    await pumpParity(tester, const ParityHomeShell());
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('shell-identity')),
        matching: find.text('Ada Byron'),
      ),
      findsOneWidget,
      reason: 'the gutter must name the signed-in identity',
    );

    // A wiped device is SIGNED OUT — stated, never a blank chip.
    final wiped = FakeCyanBackend()..profile = null;
    await pumpParity(tester, const ParityHomeShell(), backend: wiped);
    expect(find.text('Ada Byron'), findsNothing);
    expect(find.byKey(const ValueKey('shell-identity-signed-out')),
        findsOneWidget);
    expect(find.text('Signed out'), findsOneWidget);
  });
}
