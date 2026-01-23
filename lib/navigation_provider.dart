// providers/navigation_provider.dart
// Navigation state
// - explorer: File tree (groups → workspaces → boards)
// - dms: Direct messages panel
// - events: Network events

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/icon_rail.dart';

/// Provider for navigation mode
final navigationModeProvider = StateNotifierProvider<NavigationModeNotifier, AppNavMode>((ref) {
  return NavigationModeNotifier();
});

class NavigationModeNotifier extends StateNotifier<AppNavMode> {
  NavigationModeNotifier() : super(AppNavMode.explorer);
  
  void setMode(AppNavMode mode) {
    state = mode;
  }
  
  void showExplorer() => state = AppNavMode.explorer;
  void showDMs() => state = AppNavMode.dms;
  void showEvents() => state = AppNavMode.events;
}
