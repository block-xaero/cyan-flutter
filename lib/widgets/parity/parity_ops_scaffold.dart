// widgets/parity/parity_ops_scaffold.dart
//
// Shared chrome for the three Operations Console faces (Runs · Cost ·
// Efficiency), matching the SwiftUI `OperationsConsoleView` header: a console
// title and a segmented control to flip between the faces. Each face widget
// (ParityOpsRuns / ParityOpsCost / ParityOpsEfficiency) wraps its body in this
// scaffold so they share one consistent header.
//
// Pure presentation — no backend access here.

import 'package:flutter/material.dart';

import '../../theme/monokai_theme.dart';

enum OpsFace { runs, cost, efficiency }

extension OpsFaceX on OpsFace {
  String get label => switch (this) {
        OpsFace.runs => 'Runs',
        OpsFace.cost => 'Cost',
        OpsFace.efficiency => 'Efficiency',
      };
}

class OpsScaffold extends StatelessWidget {
  final OpsFace face;
  final Widget child;

  /// Selecting a different face in the segmented control — UI-only here; the
  /// host wires navigation between the three console faces.
  final void Function(OpsFace)? onSelectFace;

  const OpsScaffold({
    super.key,
    required this.face,
    required this.child,
    this.onSelectFace,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.grid_view, size: 18, color: MonokaiTheme.cyan),
                const SizedBox(width: 10),
                Text('Ops console', style: MonokaiTheme.titleSmall),
                const Spacer(),
                _Segmented(selected: face, onSelect: onSelectFace),
              ],
            ),
          ),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final OpsFace selected;
  final void Function(OpsFace)? onSelect;

  const _Segmented({required this.selected, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MonokaiTheme.border.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in OpsFace.values)
            GestureDetector(
              // Keyed because the face labels legitimately recur inside the
              // console's own content — "Cost" is both a segment and a column —
              // exactly as the Swift console disambiguates by
              // accessibilityIdentifier rather than by visible text.
              key: ValueKey('ops.face.${f.name}'),
              onTap: () => onSelect?.call(f),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: f == selected
                      ? MonokaiTheme.cyan.withValues(alpha: 0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  f.label,
                  style: MonokaiTheme.labelMedium.copyWith(
                    color: f == selected
                        ? MonokaiTheme.cyan
                        : MonokaiTheme.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
