// models/default_plugins.dart
//
// cyan-media is a DEFAULT plugin: the core media engine auto-provisions into
// EVERY group, never a manual Market install.
//
// SwiftUI reference (read-only):
//   cyan-iOS/Cyan/Cyan/Models/DefaultPlugins.swift
//   cyan-iOS/Cyan/Cyan/ViewModels/FileTreeViewModel.swift (the ensure hooks)
//
// WHY THIS EXISTS AT ALL, and why the storefront cannot substitute for it: a
// brand-new group's Plugins workspace is created EMPTY. Every `@cyan-media`
// step a cloned template lands then binds to a bundle that is not in the group,
// and the engine's bind refuses it — so the clone is runnable on macOS and
// unrunnable here. The engine's own clone-path auto-install needs a running
// lens, and cyan-media is the lens's colocated media host rather than a browse
// card, so it is not something an operator could go and install even if they
// knew to.
//
// The signed bundle ships as an app ASSET and lands through the SAME engine
// verb the Market uses (`installPluginBundle` → the group's Plugins workspace +
// content-addressed unpack), so `@cyan-media.` authoring resolves OFFLINE in a
// brand-new group with zero clicks.
//
// The bundle at `assets/plugins/cyan-media.cyanplugin` is owned by the Mac
// session, exactly like the engine DLL: never hand-edit it, request a restage
// on COORD.md.

import 'dart:convert';

import 'package:flutter/services.dart' show ByteData, rootBundle;

import '../ffi/cyan_backend.dart';

/// Reads an app-shipped `.cyanplugin`'s bytes. Injectable so a widget test can
/// drive the whole flow without an asset bundle.
typedef PluginAssetLoader = Future<List<int>?> Function(String pluginId);

abstract final class DefaultPlugins {
  /// The plugins every group carries by default.
  static const List<String> ids = ['cyan-media'];

  /// Groups already ensured in THIS process. The engine's install is
  /// idempotent, so this only avoids re-writing bundle bytes on every tree
  /// reload — it is a bandwidth guard, not a correctness one.
  static final Set<String> _ensured = <String>{};

  /// Land the default plugins in [groupId] if not already ensured.
  ///
  /// A group that does not fully land is NOT marked ensured, so the next tree
  /// event retries it — a group row that has not synced yet is a timing
  /// problem, not a permanent one. Safe to call often.
  ///
  /// Never throws: provisioning is a convenience, and an operator who cannot
  /// reach their boards because a plugin install failed is strictly worse off
  /// than one whose `@cyan-media` step pends.
  static Future<void> ensure(
    String groupId,
    CyanBackend backend, {
    PluginAssetLoader loadAsset = _assetBytes,
  }) async {
    // `temp_` ids are the tree's optimistic local rows, which have no engine
    // group behind them yet; installing into one would foreign-key-reject.
    if (groupId.isEmpty ||
        groupId.startsWith('temp_') ||
        _ensured.contains(groupId)) {
      return;
    }

    var allLanded = true;
    for (final pluginId in ids) {
      try {
        final bytes = await loadAsset(pluginId);
        // No bundled asset (a dev build without it): there is nothing to land,
        // and retrying forever would not change that.
        if (bytes == null) continue;

        final result = await backend.installPluginBundle(
            groupId, pluginId, base64Encode(bytes));
        if (!result.success) allLanded = false;
      } catch (_) {
        allLanded = false;
      }
    }
    if (allLanded) _ensured.add(groupId);
  }

  /// The app-shipped bytes for [pluginId], or null when the asset is absent.
  static Future<List<int>?> _assetBytes(String pluginId) async {
    try {
      final ByteData data =
          await rootBundle.load('assets/plugins/$pluginId.cyanplugin');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Test hook: forget the ensured set, so each fake backend starts clean.
  static void resetForTests() => _ensured.clear();
}
