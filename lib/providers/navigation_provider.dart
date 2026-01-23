// providers/navigation_provider.dart
// Navigation state with modes matching Swift IconRail

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/icon_rail.dart';

/// Provider for navigation mode
final navigationModeProvider = StateNotifierProvider<NavigationModeNotifier, NavigationMode>((ref) {
  return NavigationModeNotifier();
});

class NavigationModeNotifier extends StateNotifier<NavigationMode> {
  NavigationModeNotifier() : super(NavigationMode.explorer);
  
  void setMode(NavigationMode mode) {
    state = mode;
  }
  
  void showExplorer() => state = NavigationMode.explorer;
  void showBoards() => state = NavigationMode.boards;
  void showChat() => state = NavigationMode.chat;
  void showEvents() => state = NavigationMode.events;
}

/// Legacy provider for backward compatibility
enum NavSection { home, search, starred, profile, debug }

final navigationProvider = StateNotifierProvider<NavigationNotifier, NavSection>((ref) {
  return NavigationNotifier();
});

class NavigationNotifier extends StateNotifier<NavSection> {
  NavigationNotifier() : super(NavSection.home);
  
  void setSection(NavSection section) {
    state = section;
  }
}
