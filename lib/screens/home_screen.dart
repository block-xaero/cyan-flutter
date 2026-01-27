// screens/home_screen.dart
// Main app shell - simplified to just IconRail + WorkspaceScreen + StatusBar
// WorkspaceScreen handles all view mode switching internally

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/icon_rail.dart';
import '../widgets/status_bar.dart';
import 'workspace_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF272822),
      body: Column(
        children: [
          // Main content area
          Expanded(
            child: Row(
              children: [
                // Left navigation rail
                const IconRail(),
                
                // Vertical divider
                Container(
                  width: 1,
                  color: const Color(0xFF3E3D32),
                ),
                
                // Content area - WorkspaceScreen handles all view modes
                const Expanded(
                  child: WorkspaceScreen(),
                ),
              ],
            ),
          ),
          
          // Bottom status bar
          const StatusBar(),
        ],
      ),
    );
  }
}
