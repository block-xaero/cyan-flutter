// screens/home_screen.dart
// Main app shell with navigation rail and content area

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/navigation_provider.dart';
import '../widgets/icon_rail.dart';
import '../widgets/status_bar.dart';
import '../widgets/dms_panel.dart';
import 'workspace_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(navigationModeProvider);
    
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
                
                // Content area
                Expanded(
                  child: _buildContent(currentMode),
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
  
  Widget _buildContent(AppNavMode mode) {
    switch (mode) {
      case AppNavMode.explorer:
        return const WorkspaceScreen();
      case AppNavMode.dms:
        return const DMsPanel();
      case AppNavMode.events:
        return const _PlaceholderScreen(
          icon: Icons.hub,
          title: 'Events',
          subtitle: 'Network events will appear here',
        );
    }
  }
}

class _PlaceholderScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  
  const _PlaceholderScreen({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: const Color(0xFF75715E)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF8F8F2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF75715E),
            ),
          ),
        ],
      ),
    );
  }
}
