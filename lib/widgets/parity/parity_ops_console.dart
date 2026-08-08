// widgets/parity/parity_ops_console.dart
//
// The OPS CONSOLE — the host that turns three separate faces into one console.
//
// `OpsScaffold` draws the header and the Runs / Cost / Efficiency segmented
// control, and its own comment says the selection is "UI-only here; the host
// wires navigation between the three console faces". There was no host: the
// three faces each had their own green tests and nothing composed them, so the
// segmented control could not actually change anything and the console was
// unreachable besides.
//
// This is that host, and it is deliberately tiny — it owns exactly one piece of
// state, which face is showing.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Views/OperationsConsoleView.swift
//   cyan-iOS/Cyan/Cyan/Views/Components/IconRail.swift  (the rail's Ops entry)
//
// All three faces read the SAME `/runs` fetch through the `LensApi` seam — Cost
// and Efficiency are §4/§5 rollups over it — so flipping the control costs
// nothing and the three can never disagree with each other.

import 'package:flutter/material.dart';

import 'parity_ops_cost.dart';
import 'parity_ops_efficiency.dart';
import 'parity_ops_runs.dart';
import 'parity_ops_scaffold.dart';

class ParityOpsConsole extends StatefulWidget {
  /// The face the console opens on. Swift opens on Runs — what is happening
  /// now, before what it cost.
  final OpsFace initialFace;

  const ParityOpsConsole({super.key, this.initialFace = OpsFace.runs});

  @override
  State<ParityOpsConsole> createState() => _ParityOpsConsoleState();
}

class _ParityOpsConsoleState extends State<ParityOpsConsole> {
  late OpsFace _face = widget.initialFace;

  @override
  Widget build(BuildContext context) {
    // Each face draws its OWN `OpsScaffold` — that is how the shared header
    // stays identical across the three — so this composer must NOT wrap them
    // again. It supplies the callback the header was always missing.
    void select(OpsFace face) => setState(() => _face = face);

    return switch (_face) {
      OpsFace.runs => ParityOpsRuns(onSelectFace: select),
      OpsFace.cost => ParityOpsCost(onSelectFace: select),
      OpsFace.efficiency => ParityOpsEfficiency(onSelectFace: select),
    };
  }
}
