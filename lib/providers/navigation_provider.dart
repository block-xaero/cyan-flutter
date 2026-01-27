// providers/navigation_provider.dart
// Simplified navigation state - Explorer, AllBoards, Chat (fullscreen)

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Main view modes
enum ViewMode {
  allBoards,  // Default: Pinterest grid of ALL boards
  explorer,   // File tree + board grid (workspace filtered)
  chat,       // Full-screen chat (takes over everything)
  events,     // Network events view
}

/// Navigation mode provider
final viewModeProvider = StateNotifierProvider<ViewModeNotifier, ViewMode>((ref) {
  return ViewModeNotifier();
});

class ViewModeNotifier extends StateNotifier<ViewMode> {
  ViewModeNotifier() : super(ViewMode.allBoards);
  
  void setMode(ViewMode mode) => state = mode;
  void showAllBoards() => state = ViewMode.allBoards;
  void showExplorer() => state = ViewMode.explorer;
  void showChat() => state = ViewMode.chat;
  void showEvents() => state = ViewMode.events;
  
  void toggleExplorer() {
    if (state == ViewMode.explorer) {
      state = ViewMode.allBoards;
    } else {
      state = ViewMode.explorer;
    }
  }
}

/// DMs panel visibility (separate from main chat)
final showDMsPanelProvider = StateProvider<bool>((ref) => false);

/// Console visibility
final showConsoleProvider = StateProvider<bool>((ref) => false);

// Legacy providers for backward compatibility
enum NavSection { home, search, starred, profile, debug }

final navigationProvider = StateNotifierProvider<NavigationNotifier, NavSection>((ref) {
  return NavigationNotifier();
});

class NavigationNotifier extends StateNotifier<NavSection> {
  NavigationNotifier() : super(NavSection.home);
  void setSection(NavSection section) => state = section;
}
