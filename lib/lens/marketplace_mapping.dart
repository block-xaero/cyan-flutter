// lens/marketplace_mapping.dart
//
// Row 20 — the lens's plugin card → the storefront card the face draws. The
// port of Swift's `LensPluginCard.toCard()` + `contextualize()` +
// `MarketplaceCuration.keep()`.
//
// WHY THIS IS ITS OWN FILE. The lens's browse shape is the FORGE/plugin shape
// (`plugin_id` / `description` / `tool_summary` / `trust` / `source`), not the
// commercial card. The macOS app once decoded `data` as a bare list of
// commercial cards; the mismatch threw, and the storefront reported "Lens is
// offline" over a perfectly live lens while showing sample data. Keeping the
// wire shape and the display shape apart — with the mapping between them a
// pure, testable function — is what stops that happening again.
//
// Three rules the Swift file states and this one keeps:
//
//   1. A CURATED card carries REAL semantics. Its manifest name, its
//      model-written description and its true stage are surfaced VERBATIM. The
//      keyword contextualizer used to run on every card and stamped
//      "Use in a workflow to transcode/render video" over Frame.io — because
//      "frameio" contains "frame" — along with a hardcoded Delivery stage.
//
//   2. CONTEXTUALIZE only a PUBLIC entry with no description. Those are raw
//      repo ids (`io.github.CSOAI-ORG/voice-audio-mcp`), which mean nothing to
//      a creative professional.
//
//   3. CURATE. Ours (curated/forged) always pass. A public card must look like
//      media or named collaboration work — the storefront is not a registry
//      dump.

import '../ffi/parity_models.dart';
import 'lens_api.dart';

/// The lens's controlled stage vocabulary → the card's category band. A stage
/// this client has never heard of falls to [PluginCategory.delivery], which is
/// what the reference does — the card still SHOWS rather than being dropped.
PluginCategory categoryFromStage(String? stage) => switch (stage) {
      'editorial' => PluginCategory.editorial,
      'color' => PluginCategory.color,
      'sound' => PluginCategory.sound,
      'review' => PluginCategory.review,
      _ => PluginCategory.delivery,
    };

/// Map one lens card onto the storefront card.
PluginCard storefrontCardFrom(LensPluginCardWire wire) {
  final raw = (wire.name != null && wire.name!.isNotEmpty)
      ? wire.name!
      : wire.pluginId;
  final desc = (wire.description ?? '').trim();
  final isPublic = wire.isPublicRegistry;
  final category = categoryFromStage(wire.stage);

  final String displayName;
  final String summary;
  if (!isPublic && desc.isNotEmpty) {
    // Real card semantics from the manifest — no hint, no rewrite.
    displayName = raw;
    summary = desc;
  } else {
    final (friendly, hint) = contextualize(name: raw, description: desc);
    displayName = friendly;
    summary = desc.isEmpty
        ? (hint.isEmpty ? 'Workflow plugin' : hint)
        : (hint.isEmpty ? desc : '$hint — $desc');
  }

  return PluginCard(
    id: wire.pluginId,
    name: displayName,
    publisher: isPublic ? 'Community' : 'Curated',
    summary: summary,
    category: category,
    stage: wire.stage ?? category.label.toLowerCase(),
    // The browse shape carries no placement. Device-local connect is the
    // Member+ path and the only one a card can claim without the server's
    // RBAC answer; the team placement is chosen on the detail page's gate.
    placement: 'device',
    // …and it carries no side-effect data either. The ENGINE's catalog does
    // (`InstalledPluginTool.sideEffects`, which is what actually gates a run),
    // so a listing NEVER claims read-only-ness it cannot know: it claims the
    // safe default and the gate is re-checked at the door.
    sideEffect: PluginSideEffect.readOnly,
    isTrusted: wire.isTrusted,
    rating: 0,
    isFeatured: wire.featured ?? false,
  );
}

/// Map a raw registry name + description to (creative-pro name, "use in a
/// workflow to…"). Public entries only — see rule 1 above.
(String, String) contextualize(
    {required String name, required String description}) {
  // Friendly name: last path/namespace segment, drop the -mcp suffix, spaced
  // and title-cased.
  final parts = [
    for (final p in name.split(RegExp(r'[/.]')))
      if (p.isNotEmpty) p
  ];
  var seg = parts.isEmpty ? name : parts.last;
  for (final suffix in const ['-mcp', '_mcp', '-server', ' mcp']) {
    if (seg.toLowerCase().endsWith(suffix)) {
      seg = seg.substring(0, seg.length - suffix.length);
    }
  }
  final friendly = seg
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  final hay = '$name $description'.toLowerCase();
  bool has(List<String> keys) => keys.any(hay.contains);

  final String hint;
  if (has(const ['transcrib', 'caption', 'subtitle', 'speech', 'whisper'])) {
    hint = 'Use in a workflow to transcribe/caption an asset';
  } else if (has(const ['loudness', 'lufs', 'mix', 'master', 'audio', 'sound'])) {
    hint = 'Use in a workflow to analyze or process audio';
  } else if (has(const [
    'transcode',
    'render',
    'encode',
    'proxy',
    'ffmpeg',
    'video',
    'frame',
    'codec'
  ])) {
    hint = 'Use in a workflow to transcode/render video';
  } else if (has(const ['color', 'grade', 'lut'])) {
    hint = 'Use in a workflow for color & grade';
  } else if (has(const ['slack', 'discord', 'teams'])) {
    hint = 'Use in a workflow to notify your team';
  } else if (has(const ['jira', 'confluence', 'notion'])) {
    hint = 'Use in a workflow to sync tasks & docs';
  } else if (has(const ['email', 'gmail', 'outlook', 'mail'])) {
    hint = 'Use in a workflow to send delivery notices';
  } else {
    hint = 'Use as a workflow tool';
  }
  return (friendly.isEmpty ? name : friendly, hint);
}

/// The curation filter: ours always pass; a public card must look like media
/// or named collaboration work. The storefront is not a registry dump.
class MarketplaceCuration {
  static const List<String> mediaKeywords = [
    'video', 'audio', 'media', 'ffmpeg', 'transcode', 'encode', 'decode',
    'edit', 'editorial', 'frame', 'render', 'color', 'grade', 'subtitle',
    'caption', 'transcribe', 'transcription', 'image', 'photo', 'vfx',
    'broadcast', 'stream', 'mux', 'codec', 'resolve', 'premiere', 'avid',
    'pro tools', 'final cut', 'final draft', 'music', 'sound', 'mix',
    'master', 'loudness', 'lut', 'footage', 'clip', 'timeline', 'otio',
    'whisper', 'speech', 'camera', 'film', 'cinema', 'dolby',
  ];

  static const List<String> collabKeywords = [
    'slack', 'confluence', 'jira', 'discord', 'email', 'gmail', 'outlook',
    'mail', 'notion',
  ];

  /// [isPublic] is the WIRE's `source`, not something re-derived from the
  /// mapped card — a curated card whose publisher string changed must not
  /// silently become filterable.
  static bool keep(PluginCard card, {required bool isPublic}) {
    if (!isPublic) return true;
    final hay = '${card.name} ${card.summary}'.toLowerCase();
    return mediaKeywords.any(hay.contains) || collabKeywords.any(hay.contains);
  }
}

/// The whole browse → storefront step: map, then curate.
List<PluginCard> storefrontCardsFrom(List<LensPluginCardWire> wire) {
  final kept = <PluginCard>[];
  for (final w in wire) {
    final card = storefrontCardFrom(w);
    if (MarketplaceCuration.keep(card, isPublic: w.isPublicRegistry)) {
      kept.add(card);
    }
  }
  return kept;
}
