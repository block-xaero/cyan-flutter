// services/demo_data_seeder.dart
// Creates rich demo data: groups, workspaces, boards with content
// Preserves existing data - only adds new items

import 'dart:math';
import '../ffi/ffi_helpers.dart';
import '../ffi/component_bridge.dart';

class DemoDataSeeder {
  static final _random = Random();
  
  /// Department/Group definitions
  static const _departments = [
    ('Engineering', 'hammer.fill', '#00AEEF'),
    ('Product', 'lightbulb.fill', '#A6E22E'),
    ('Design', 'paintbrush.fill', '#F92672'),
    ('Marketing', 'megaphone.fill', '#FD971F'),
    ('Sales', 'chart.line.uptrend.xyaxis', '#AE81FF'),
    ('Operations', 'gearshape.2.fill', '#E6DB74'),
  ];
  
  /// Workspace templates per department
  static const _workspaceTemplates = {
    'Engineering': ['Backend Services', 'Frontend Apps', 'Infrastructure'],
    'Product': ['Roadmap', 'User Research', 'Analytics'],
    'Design': ['UI Components', 'Brand Assets', 'Prototypes'],
    'Marketing': ['Campaigns', 'Content', 'Social Media'],
    'Sales': ['Pipeline', 'Client Relations', 'Proposals'],
    'Operations': ['HR & People', 'Finance', 'Legal'],
  };
  
  /// Board templates with face types and labels
  static final _boardTemplates = <String, List<(String, String, List<String>, bool, int)>>{
    'Backend Services': [
      ('API Architecture', 'canvas', ['design', 'in-progress'], true, 4),
      ('Database Schema', 'notebook', ['approved', 'development'], false, 5),
      ('Deployment Notes', 'notes', ['draft'], false, 2),
    ],
    'Frontend Apps': [
      ('Component Library', 'canvas', ['design', 'approved'], true, 5),
      ('State Management', 'notebook', ['research'], false, 3),
      ('Performance Metrics', 'notes', ['review'], false, 4),
    ],
    'Infrastructure': [
      ('Cloud Architecture', 'canvas', ['approved'], true, 5),
      ('CI/CD Pipeline', 'notebook', ['in-progress', 'development'], false, 4),
      ('Security Checklist', 'notes', ['urgent', 'review'], true, 5),
    ],
    'Roadmap': [
      ('Q1 2026 Goals', 'canvas', ['approved'], true, 5),
      ('Feature Prioritization', 'notebook', ['in-progress'], false, 4),
      ('Release Schedule', 'notes', ['draft'], false, 3),
    ],
    'User Research': [
      ('Interview Notes', 'notes', ['research'], false, 4),
      ('Persona Mapping', 'canvas', ['approved'], true, 5),
      ('Survey Results', 'notebook', ['review'], false, 3),
    ],
    'Analytics': [
      ('KPI Dashboard', 'canvas', ['approved'], true, 5),
      ('Funnel Analysis', 'notebook', ['in-progress'], false, 4),
      ('Weekly Reports', 'notes', ['draft'], false, 2),
    ],
    'UI Components': [
      ('Design System', 'canvas', ['approved', 'design'], true, 5),
      ('Component Specs', 'notebook', ['development'], false, 4),
      ('Accessibility Notes', 'notes', ['review'], false, 4),
    ],
    'Brand Assets': [
      ('Logo Guidelines', 'canvas', ['approved'], true, 5),
      ('Color Palette', 'notebook', ['design'], false, 4),
      ('Typography', 'notes', ['approved'], false, 4),
    ],
    'Prototypes': [
      ('Mobile App v2', 'canvas', ['in-progress', 'design'], true, 4),
      ('Dashboard Redesign', 'canvas', ['review'], false, 3),
      ('Onboarding Flow', 'notebook', ['draft'], false, 3),
    ],
    'Campaigns': [
      ('Product Launch', 'canvas', ['urgent', 'in-progress'], true, 5),
      ('Email Sequences', 'notebook', ['approved'], false, 4),
      ('Campaign Calendar', 'notes', ['draft'], false, 3),
    ],
    'Content': [
      ('Blog Editorial', 'notes', ['in-progress'], false, 3),
      ('Video Scripts', 'notebook', ['review'], false, 4),
      ('SEO Strategy', 'canvas', ['research'], false, 3),
    ],
    'Social Media': [
      ('Content Calendar', 'canvas', ['approved'], true, 4),
      ('Analytics Report', 'notebook', ['review'], false, 3),
      ('Brand Voice Guide', 'notes', ['approved'], false, 5),
    ],
    'Pipeline': [
      ('Q1 Deals', 'canvas', ['urgent'], true, 5),
      ('Lead Scoring', 'notebook', ['in-progress'], false, 4),
      ('Win/Loss Analysis', 'notes', ['review'], false, 3),
    ],
    'Client Relations': [
      ('Account Map', 'canvas', ['approved'], true, 4),
      ('Meeting Notes', 'notes', ['draft'], false, 2),
      ('Renewal Tracker', 'notebook', ['in-progress'], false, 4),
    ],
    'Proposals': [
      ('Template Library', 'canvas', ['approved'], true, 5),
      ('Pricing Matrix', 'notebook', ['review'], false, 4),
      ('Case Studies', 'notes', ['approved'], false, 5),
    ],
    'HR & People': [
      ('Org Chart', 'canvas', ['approved'], true, 5),
      ('Onboarding Checklist', 'notebook', ['approved'], false, 5),
      ('Policy Updates', 'notes', ['review'], false, 3),
    ],
    'Finance': [
      ('Budget Overview', 'canvas', ['approved'], true, 5),
      ('Expense Tracking', 'notebook', ['in-progress'], false, 4),
      ('Quarterly Report', 'notes', ['draft'], false, 3),
    ],
    'Legal': [
      ('Contract Templates', 'notes', ['approved'], true, 5),
      ('Compliance Checklist', 'notebook', ['review'], false, 4),
      ('NDA Tracker', 'canvas', ['in-progress'], false, 3),
    ],
    // For existing "My Workspace" group
    'Projects': [
      ('Project Ideas', 'canvas', ['draft'], false, 3),
      ('Learning Notes', 'notebook', ['in-progress'], false, 4),
      ('Quick Reference', 'notes', ['approved'], true, 5),
    ],
  };
  
  /// Canvas element templates
  static List<Map<String, dynamic>> _generateCanvasElements(String boardId, String boardName) {
    final elements = <Map<String, dynamic>>[];
    final baseX = 100.0;
    final baseY = 100.0;
    
    // Title sticky
    elements.add({
      'id': _generateId(),
      'board_id': boardId,
      'type': 'sticky',
      'x': baseX,
      'y': baseY,
      'width': 300.0,
      'height': 100.0,
      'content': boardName,
      'color': '#E6DB74',
    });
    
    // Add some rectangles
    for (int i = 0; i < 3; i++) {
      elements.add({
        'id': _generateId(),
        'board_id': boardId,
        'type': 'rect',
        'x': baseX + 50 + (i * 150),
        'y': baseY + 150,
        'width': 120.0,
        'height': 80.0,
        'color': ['#00AEEF', '#A6E22E', '#F92672'][i],
      });
    }
    
    // Add connecting lines (as paths)
    elements.add({
      'id': _generateId(),
      'board_id': boardId,
      'type': 'path',
      'points': [
        {'x': baseX + 110, 'y': baseY + 190},
        {'x': baseX + 200, 'y': baseY + 190},
      ],
      'color': '#75715E',
    });
    
    // Add text annotation
    elements.add({
      'id': _generateId(),
      'board_id': boardId,
      'type': 'text',
      'x': baseX,
      'y': baseY + 280,
      'content': 'Created with Cyan',
      'color': '#F8F8F2',
    });
    
    // Add an ellipse
    elements.add({
      'id': _generateId(),
      'board_id': boardId,
      'type': 'ellipse',
      'x': baseX + 400,
      'y': baseY + 100,
      'width': 100.0,
      'height': 100.0,
      'color': '#AE81FF',
    });
    
    return elements;
  }
  
  /// Notebook cell templates
  static List<Map<String, dynamic>> _generateNotebookCells(String boardId, String boardName) {
    final cells = <Map<String, dynamic>>[];
    
    // Markdown header cell
    cells.add({
      'id': _generateId(),
      'board_id': boardId,
      'cell_type': 'markdown',
      'content': '# $boardName\n\nThis notebook contains documentation and notes.',
      'order': 0,
    });
    
    // Code/diagram cell
    cells.add({
      'id': _generateId(),
      'board_id': boardId,
      'cell_type': 'mermaid',
      'content': '''graph TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Action 1]
    B -->|No| D[Action 2]
    C --> E[End]
    D --> E''',
      'order': 1,
    });
    
    // Another markdown cell
    cells.add({
      'id': _generateId(),
      'board_id': boardId,
      'cell_type': 'markdown',
      'content': '''## Key Points

- First important item
- Second consideration
- Third takeaway

### Next Steps

1. Review this document
2. Add comments
3. Share with team''',
      'order': 2,
    });
    
    // Canvas cell (mini drawing)
    cells.add({
      'id': _generateId(),
      'board_id': boardId,
      'cell_type': 'canvas',
      'content': '{"elements":[]}',
      'order': 3,
    });
    
    return cells;
  }
  
  /// Notes content templates
  static String _generateNotesContent(String boardName) {
    return '''# $boardName

## Overview

This document contains important notes and reference material.

## Details

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

### Section 1

Key information goes here. Remember to update this section as needed.

### Section 2

Additional context and supporting details.

## Action Items

- [ ] Review and update
- [ ] Share with stakeholders
- [ ] Schedule follow-up

---

*Last updated: ${DateTime.now().toString().split(' ')[0]}*
''';
  }
  
  static String _generateId() {
    const chars = 'abcdef0123456789';
    return List.generate(32, (_) => chars[_random.nextInt(chars.length)]).join();
  }
  
  /// Get board template for a workspace
  static List<(String, String, List<String>, bool, int)>? getBoardTemplates(String workspaceName) {
    return _boardTemplates[workspaceName];
  }
  
  /// Get workspace templates for a group
  static List<String>? getWorkspaceTemplates(String groupName) {
    return _workspaceTemplates[groupName];
  }
  
  /// Get all department definitions
  static List<(String, String, String)> get departments => _departments;
  
  /// Add content to a board based on its face type
  static Future<void> seedBoardContent(
    String boardId,
    String boardName,
    String face,
    List<String> labels,
    {bool pinned = false, int rating = 0}
  ) async {
    print('🌱 Adding content to board: $boardName (face: $face)');
    
    // Set board mode/face
    CyanFFI.setBoardMode(boardId, face);
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Set labels
    if (labels.isNotEmpty) {
      CyanFFI.setBoardLabels(boardId, labels);
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    // Set rating
    if (rating > 0) {
      CyanFFI.rateBoard(boardId, rating);
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    // Pin if specified
    if (pinned) {
      CyanFFI.pinBoard(boardId);
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    // Add content based on face type
    switch (face) {
      case 'canvas':
        final elements = _generateCanvasElements(boardId, boardName);
        for (final element in elements) {
          CyanFFI.saveWhiteboardElement(boardId, element);
          await Future.delayed(const Duration(milliseconds: 30));
        }
        break;
        
      case 'notebook':
        final cells = _generateNotebookCells(boardId, boardName);
        for (final cell in cells) {
          CyanFFI.saveNotebookCell(boardId, cell);
          await Future.delayed(const Duration(milliseconds: 30));
        }
        break;
        
      case 'notes':
        // Notes use the first markdown cell
        final notesCell = {
          'id': _generateId(),
          'board_id': boardId,
          'cell_type': 'markdown',
          'content': _generateNotesContent(boardName),
          'order': 0,
        };
        CyanFFI.saveNotebookCell(boardId, notesCell);
        break;
    }
    
    print('🌱 Content added to $boardName');
  }
}
