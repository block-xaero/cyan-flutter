// widgets/parity/parity_sources_sheet.dart
//
// PARITY port of the SwiftUI `SourcesSheet` (Views/SourcesSheet.swift) and the
// `IngestRunsStrip` beside it: the board's INGEST SOURCES — the watched sensors
// this board is pointed at, add / remove / scan-now, the per-source scan report,
// and the per-asset runs a scan materialized.
//
// Driven ENTIRELY through the `CyanBackend` seam (via `ingestSourcesProvider`,
// which speaks the one `ingestCommand` gateway). This widget never touches
// `CyanFFI` directly — the parity rule.
//
// The face exists to make one sentence true: POINT THIS BOARD AT A SOURCE AND
// NEW MEDIA MATERIALIZES ITS OWN PIPELINE RUN. So the three things the operator
// cannot otherwise know are all on the surface:
//
//   • WHEN was this sensor last read — every row says, including "never".
//   • WHAT did the last scan do — discovered / ingested / deduped, in a
//     sentence, including the two ways a scan legitimately does nothing.
//   • WHAT came out of it — the runs strip, one chip per ingested asset.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ffi/parity_models.dart';
import '../../providers/ingest_sources_controller.dart';
import '../../theme/monokai_theme.dart';

/// The engine's CLOSED kind vocabulary (`INGEST_KIND_VOCAB`), with the label
/// each one carries in the picker. A kind outside it is refused on add and on
/// scan, so the form never offers one.
const List<(String, String, IconData)> ingestKinds = [
  ('folder', 'Watch a folder', Icons.folder),
  ('s3', 'S3 bucket (s3://bucket/prefix)', Icons.cloud_outlined),
  ('frameio_c2c', 'Frame.io C2C project (frameio://project-id)', Icons.videocam),
];

/// The cadences a new sensor can be put on. Null is manual-only — the sensor
/// waits to be asked.
const List<(int?, String)> ingestScheduleOptions = [
  (null, 'Manual only — “Scan now”'),
  (60, 'Every minute'),
  (300, 'Every 5 minutes'),
  (900, 'Every 15 minutes'),
  (3600, 'Every hour'),
];

class ParitySourcesSheet extends ConsumerStatefulWidget {
  /// The board these sensors feed. Every asset they ingest materializes a run
  /// of THIS board's workflow template.
  final String boardId;

  /// The tenant (group) boundary every ingest verb carries.
  final String tenantId;

  /// Dismissing the sheet. Null renders no Done affordance — the panel is
  /// embedded rather than presented.
  final VoidCallback? onClose;

  const ParitySourcesSheet({
    super.key,
    this.boardId = 'b-eng-1',
    this.tenantId = 'g-eng',
    this.onClose,
  });

  @override
  ConsumerState<ParitySourcesSheet> createState() => _ParitySourcesSheetState();
}

class _ParitySourcesSheetState extends ConsumerState<ParitySourcesSheet> {
  final TextEditingController _uri = TextEditingController();
  String _kind = 'folder';
  int? _scheduleSecs;

  IngestScope get _scope =>
      (boardId: widget.boardId, tenantId: widget.tenantId);

  @override
  void dispose() {
    _uri.dispose();
    super.dispose();
  }

  String get _uriHint => switch (_kind) {
        's3' => 's3://bucket/prefix',
        'frameio_c2c' => 'frameio://project-id',
        _ => '/path/to/watch — new media auto-ingests',
      };

  Future<void> _add() async {
    final controller = ref.read(ingestSourcesProvider(_scope).notifier);
    final added = await controller.addSource(
      kind: _kind,
      uri: _uri.text,
      scheduleSecs: _scheduleSecs,
    );
    if (!mounted || !added) return;
    setState(() {
      _uri.clear();
      _scheduleSecs = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ingestSourcesProvider(_scope));
    final controller = ref.read(ingestSourcesProvider(_scope).notifier);

    return Material(
      color: MonokaiTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onClose: widget.onClose),
          if (state.error != null)
            _ErrorBanner(text: state.error!, onDismiss: controller.clearError),
          const Divider(height: 1, color: MonokaiTheme.divider),
          Expanded(
            child: state.loading
                ? const Center(
                    child: CircularProgressIndicator(color: MonokaiTheme.cyan))
                : state.isEmpty
                    ? const _Empty()
                    : ListView(
                        padding: const EdgeInsets.all(10),
                        children: [
                          for (final source in state.sources)
                            _SourceRow(
                              source: source,
                              report: state.reports[source.id],
                              busy: state.isScanning,
                              onScan: () => controller.scanNow(source.id),
                              onRemove: () =>
                                  controller.removeSource(source.id),
                            ),
                        ],
                      ),
          ),
          if (state.runs.isNotEmpty) _RunsStrip(runs: state.runs),
          const Divider(height: 1, color: MonokaiTheme.divider),
          _AddForm(
            kind: _kind,
            uri: _uri,
            hint: _uriHint,
            scheduleSecs: _scheduleSecs,
            onKind: (k) => setState(() => _kind = k),
            onSchedule: (s) => setState(() => _scheduleSecs = s),
            onAdd: _add,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback? onClose;
  const _Header({this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      color: MonokaiTheme.surface,
      child: Row(
        children: [
          const Icon(Icons.settings_input_antenna,
              size: 15, color: MonokaiTheme.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ingest Sources', style: MonokaiTheme.titleSmall),
                const SizedBox(height: 1),
                Text(
                  'Point this board at a source — new media materialises its '
                  'own pipeline run.',
                  style: MonokaiTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onClose != null)
            TextButton(
              key: const Key('sources.done'),
              onPressed: onClose,
              style: TextButton.styleFrom(
                  foregroundColor: MonokaiTheme.cyan,
                  visualDensity: VisualDensity.compact),
              child: const Text('Done'),
            ),
        ],
      ),
    );
  }
}

/// The engine's refusal, verbatim. It stays until dismissed — an ingest error
/// that scrolls away is an ingest error nobody read.
class _ErrorBanner extends StatelessWidget {
  final String text;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.text, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('sources.error.banner'),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      color: MonokaiTheme.red.withValues(alpha: 0.10),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 13, color: MonokaiTheme.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: MonokaiTheme.labelSmall.copyWith(
                  color: MonokaiTheme.red, fontWeight: FontWeight.w500),
              maxLines: 3,
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 12),
            color: MonokaiTheme.comment,
            splashRadius: 14,
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.settings_input_antenna,
                size: 32, color: MonokaiTheme.border),
            const SizedBox(height: 10),
            Text('No sources yet',
                style: MonokaiTheme.bodyMedium
                    .copyWith(color: MonokaiTheme.foreground)),
            const SizedBox(height: 4),
            Text(
              'Watch a folder to auto-ingest new dailies — each new file gets '
              'its own run of this board’s workflow.',
              textAlign: TextAlign.center,
              style: MonokaiTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final IngestSource source;

  /// The last scan this session did. Null = not scanned here yet, which is NOT
  /// the same as scanned-and-found-nothing; only one of those prints counts.
  final ScanReport? report;

  /// A scan is in flight somewhere on the sheet — the engine takes one at a
  /// time, so every row's button rests.
  final bool busy;

  final VoidCallback onScan;
  final VoidCallback onRemove;

  const _SourceRow({
    required this.source,
    required this.report,
    required this.busy,
    required this.onScan,
    required this.onRemove,
  });

  IconData get _icon => switch (source.kind) {
        'folder' => Icons.folder,
        's3' => Icons.cloud_outlined,
        'frameio_c2c' => Icons.videocam,
        _ => Icons.help_outline,
      };

  @override
  Widget build(BuildContext context) {
    final subtitle = '${source.kind} · '
        '${ingestScheduleLabel(source.scheduleSecs)} · '
        '${ingestLastScanLabel(source.lastScanAt)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MonokaiTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_icon, size: 14, color: MonokaiTheme.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(source.uri,
                        style: MonokaiTheme.codeSmall
                            .copyWith(color: MonokaiTheme.foreground),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(subtitle, style: MonokaiTheme.labelSmall),
                  ],
                ),
              ),
              TextButton.icon(
                key: Key('sources.scan.${source.id}'),
                onPressed: busy ? null : onScan,
                icon: const Icon(Icons.refresh, size: 13),
                label: const Text('Scan now'),
                style: TextButton.styleFrom(
                  foregroundColor: MonokaiTheme.green,
                  disabledForegroundColor: MonokaiTheme.comment,
                  backgroundColor:
                      MonokaiTheme.green.withValues(alpha: busy ? 0.04 : 0.12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                  textStyle: MonokaiTheme.labelSmall
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: Key('sources.remove.${source.id}'),
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 14),
                color: MonokaiTheme.comment,
                splashRadius: 15,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove this source (already-ingested assets stay)',
              ),
            ],
          ),
          if (report != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Chip(
                      icon: Icons.search,
                      text: '${report!.discovered} discovered',
                      tint: MonokaiTheme.cyan),
                  _Chip(
                      icon: Icons.download_done,
                      text: '${report!.ingested} ingested',
                      tint: MonokaiTheme.green),
                  _Chip(
                      icon: Icons.copy_all_outlined,
                      text: '${report!.deduped} deduped',
                      tint: MonokaiTheme.comment),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              // The sentence is the point: a scan that ingested nothing SAYS so
              // here, rather than leaving three zeroes to be read as a failure.
              child: Text(
                ingestScanSummary(report!),
                key: Key('sources.report.${source.id}'),
                style: MonokaiTheme.labelSmall.copyWith(
                  color: report!.ingested > 0
                      ? MonokaiTheme.green
                      : MonokaiTheme.comment,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color tint;
  const _Chip({required this.icon, required this.text, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: tint),
          const SizedBox(width: 4),
          Text(text,
              style: MonokaiTheme.labelSmall
                  .copyWith(color: tint, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// WORKFLOW = ASSET CLASS, made visible: one chip per ingested asset's OWN
/// materialized run (short content-hash · status), refreshed after any scan.
/// Renders nothing when the board has no runs.
class _RunsStrip extends StatelessWidget {
  final List<MaterializedRun> runs;
  const _RunsStrip({required this.runs});

  static Color _tint(String status) => switch (status) {
        'done' => MonokaiTheme.green,
        'running' => MonokaiTheme.yellow,
        'failed' => MonokaiTheme.red,
        _ => MonokaiTheme.cyan, // materialized
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('workflow.runs.strip'),
      color: MonokaiTheme.surface.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text('Runs · ${runs.length}',
              style: MonokaiTheme.labelSmall
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 22,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: runs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) => _RunChip(run: runs[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunChip extends StatelessWidget {
  final MaterializedRun run;
  const _RunChip({required this.run});

  /// The asset's short content-hash — the human handle on a run whose subject
  /// is a hash, not a filename.
  String get _shortHash => run.assetHash.length <= 8
      ? run.assetHash
      : run.assetHash.substring(0, 8);

  @override
  Widget build(BuildContext context) {
    final tint = _RunsStrip._tint(run.status);
    return Container(
      key: Key('workflow.run.${run.runId}'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.widgets_outlined, size: 9, color: tint),
          const SizedBox(width: 5),
          Text(_shortHash,
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.foreground)),
          const SizedBox(width: 5),
          Text(run.status,
              style: MonokaiTheme.labelSmall
                  .copyWith(color: tint, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AddForm extends StatelessWidget {
  final String kind;
  final TextEditingController uri;
  final String hint;
  final int? scheduleSecs;
  final ValueChanged<String> onKind;
  final ValueChanged<int?> onSchedule;
  final Future<void> Function() onAdd;

  const _AddForm({
    required this.kind,
    required this.uri,
    required this.hint,
    required this.scheduleSecs,
    required this.onKind,
    required this.onSchedule,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a source',
              style: MonokaiTheme.bodySmall.copyWith(
                  color: MonokaiTheme.foreground,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              DropdownButton<String>(
                key: const Key('sources.add.kind'),
                value: kind,
                dropdownColor: MonokaiTheme.surface,
                underline: const SizedBox.shrink(),
                isDense: true,
                style: MonokaiTheme.bodySmall
                    .copyWith(color: MonokaiTheme.foreground),
                items: [
                  for (final (key, label, icon) in ingestKinds)
                    DropdownMenuItem(
                      value: key,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 12, color: MonokaiTheme.cyan),
                          const SizedBox(width: 6),
                          Text(label),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onKind(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: TextField(
              key: const Key('sources.add.uri'),
              controller: uri,
              style: MonokaiTheme.codeSmall
                  .copyWith(color: MonokaiTheme.foreground),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: MonokaiTheme.labelSmall,
                filled: true,
                fillColor: MonokaiTheme.background,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: MonokaiTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: const BorderSide(color: MonokaiTheme.border),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Cadence — the checkmark-row pattern the schedule picker uses.
          for (final (secs, label) in ingestScheduleOptions)
            _ScheduleRow(
              label: label,
              selected: scheduleSecs == secs,
              onTap: () => onSchedule(secs),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Scheduled sources are swept while this board is open '
                  '(engine-side scheduling is v2).',
                  style: MonokaiTheme.labelSmall,
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: uri,
                builder: (context, value, _) {
                  final ready = value.text.trim().isNotEmpty;
                  return ElevatedButton(
                    key: const Key('sources.add.confirm'),
                    onPressed: ready ? onAdd : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MonokaiTheme.cyan,
                      foregroundColor: MonokaiTheme.background,
                      disabledBackgroundColor: MonokaiTheme.selection,
                      disabledForegroundColor: MonokaiTheme.comment,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      textStyle: MonokaiTheme.bodySmall
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Add source'),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ScheduleRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? MonokaiTheme.green.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 13,
              color: selected ? MonokaiTheme.green : MonokaiTheme.comment,
            ),
            const SizedBox(width: 8),
            Text(label,
                style: MonokaiTheme.labelSmall
                    .copyWith(color: MonokaiTheme.foreground)),
          ],
        ),
      ),
    );
  }
}
