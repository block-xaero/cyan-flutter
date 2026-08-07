// lens_marketplace_test.dart — row 20's contract: the lens's plugin card →
// the storefront card, and the curation filter in front of it.
//
// Every rule here was a BUG on the Swift side before it was a rule, which is
// why each has its own test rather than living as a comment.

import 'package:cyan_flutter/ffi/parity_models.dart';
import 'package:cyan_flutter/lens/lens_api.dart';
import 'package:cyan_flutter/lens/marketplace_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

LensPluginCardWire wire({
  String id = 'p1',
  String? name,
  String? description,
  String? trust,
  String? source,
  bool? featured,
  String? stage,
}) =>
    LensPluginCardWire(
      pluginId: id,
      name: name,
      description: description,
      trust: trust,
      source: source,
      featured: featured,
      stage: stage,
    );

void main() {
  group('a CURATED card keeps its own words', () {
    test('name, description and stage are surfaced VERBATIM', () {
      final card = storefrontCardFrom(wire(
        id: 'pl-frameio',
        name: 'Frame.io Review',
        description: 'Push a cut to Frame.io for client review.',
        source: 'curated',
        stage: 'review',
      ));
      // "frameio" contains "frame", which is a video keyword. Running the
      // contextualizer over a curated card stamped this listing
      // "Use in a workflow to transcode/render video" AND forced its stage to
      // Delivery. Both are wrong; the manifest is the authority.
      expect(card.name, 'Frame.io Review');
      expect(card.summary, 'Push a cut to Frame.io for client review.');
      expect(card.category, PluginCategory.review);
      expect(card.publisher, 'Curated');
    });

    test('a stage this client has never heard of still SHOWS, in Delivery', () {
      final card = storefrontCardFrom(
          wire(name: 'X', description: 'y', source: 'curated', stage: 'mastering'));
      expect(card.category, PluginCategory.delivery);
      // …and the lens's own word for the stage is kept, not overwritten with
      // the fallback band's.
      expect(card.stage, 'mastering');
    });

    test('a curated card with NO description falls back to the hint rather '
        'than showing a blank summary', () {
      final card =
          storefrontCardFrom(wire(id: 'x.audio-tool', source: 'curated'));
      expect(card.summary, isNotEmpty);
    });
  });

  group('a PUBLIC registry entry is contextualized', () {
    test('a raw repo id becomes a name a creative professional can read', () {
      final card = storefrontCardFrom(
          wire(id: 'io.github.CSOAI-ORG/voice-audio-mcp', source: 'public'));
      expect(card.name, 'Voice Audio');
      expect(card.summary, 'Use in a workflow to analyze or process audio');
      expect(card.publisher, 'Community');
    });

    test('the -server and -mcp suffixes are dropped, separators become spaces',
        () {
      expect(contextualize(name: 'acme/render-farm-server', description: '').$1,
          'Render Farm');
      expect(contextualize(name: 'some_caption_mcp', description: '').$1,
          'Some Caption');
    });

    test('the hint is chosen by keyword, in the reference\'s priority order',
        () {
      String hint(String n) => contextualize(name: n, description: '').$2;
      expect(hint('whisper-tool'),
          'Use in a workflow to transcribe/caption an asset');
      expect(hint('loudness-meter'),
          'Use in a workflow to analyze or process audio');
      expect(hint('ffmpeg-proxy'), 'Use in a workflow to transcode/render video');
      expect(hint('lut-loader'), 'Use in a workflow for color & grade');
      expect(hint('slack-notify'), 'Use in a workflow to notify your team');
      expect(hint('jira-sync'), 'Use in a workflow to sync tasks & docs');
      expect(hint('outlook-send'), 'Use in a workflow to send delivery notices');
      expect(hint('quantum-widget'), 'Use as a workflow tool');
    });

    test('a public card WITH a description keeps it, prefixed by the hint', () {
      final card = storefrontCardFrom(wire(
          id: 'acme/transcode-mcp',
          description: 'Fast H.264 proxies.',
          source: 'public'));
      expect(card.summary,
          'Use in a workflow to transcode/render video — Fast H.264 proxies.');
    });
  });

  group('trust is the SERVER\'s answer, never widened here', () {
    test('only the literal "trusted" is trusted', () {
      expect(storefrontCardFrom(wire(trust: 'trusted')).isTrusted, isTrue);
      for (final t in const [null, '', 'Trusted', 'signed', 'untrusted']) {
        expect(storefrontCardFrom(wire(trust: t)).isTrusted, isFalse,
            reason: 'trust="$t" must not read as trusted');
      }
    });

    test('trust and SOURCE are independent — a curated card can be untrusted',
        () {
      final card = storefrontCardFrom(wire(
          name: 'Frame.io Review',
          description: 'Push a cut.',
          trust: 'untrusted',
          source: 'curated'));
      expect(card.isTrusted, isFalse);
      expect(card.publisher, 'Curated',
          reason: 'signing a wrapper gives provenance, not trust');
    });

    test('a listing NEVER claims a side effect the lens cannot tell it', () {
      // The browse shape has no side-effect field. The engine's catalog does,
      // and that is the thing that actually gates a run, so the listing claims
      // the safe default and the gate is re-checked at the door.
      expect(storefrontCardFrom(wire(trust: 'untrusted', source: 'public'))
          .sideEffect,
          PluginSideEffect.readOnly);
    });

    test('the featured flag is the SERVER\'s curation, not a guess', () {
      expect(storefrontCardFrom(wire(featured: true)).isFeatured, isTrue);
      expect(storefrontCardFrom(wire()).isFeatured, isFalse);
    });

    test('the listing id IS the bundle id on this lane', () {
      // The download leg is `/marketplace/bundle/{plugin_id}`.
      final card = storefrontCardFrom(wire(id: 'ffmpeg'));
      expect(card.id, 'ffmpeg');
      expect(card.bundleId, 'ffmpeg');
    });
  });

  group('curation — the storefront is not a registry dump', () {
    test('OURS always pass, whatever they are about', () {
      final kept = storefrontCardsFrom([
        wire(
            id: 'cyan.ledger',
            name: 'Ledger Export',
            description: 'Export the board ledger.',
            source: 'curated'),
      ]);
      expect(kept, hasLength(1));
    });

    test('a public entry must look like media or named collaboration work', () {
      final kept = storefrontCardsFrom([
        wire(id: 'acme/transcode-mcp', source: 'public'), // media
        wire(id: 'acme/slack-notify', source: 'public'), // collaboration
        wire(id: 'acme/kubernetes-operator', source: 'public'), // neither
      ]);
      expect([for (final c in kept) c.id],
          ['acme/transcode-mcp', 'acme/slack-notify']);
    });

    test('curation reads the WIRE\'s source, not the mapped publisher string',
        () {
      // A curated card about nothing media-ish must survive even though its
      // words match no keyword — the check must not be re-derived from a
      // display field that could change.
      final kept = storefrontCardsFrom([
        wire(
            id: 'cyan.zzz',
            name: 'Quantum Widget',
            description: 'Nothing to do with pictures.',
            source: 'curated'),
      ]);
      expect(kept, hasLength(1));
    });

    test('an empty browse maps to an empty storefront, not to an error', () {
      expect(storefrontCardsFrom(const []), isEmpty);
    });
  });
}
