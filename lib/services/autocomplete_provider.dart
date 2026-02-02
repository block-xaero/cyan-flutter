// services/autocomplete_provider.dart
// VSCode-style autocomplete suggestions for notebook cells
// Language-aware: Python, SQL, Mermaid keywords + table/column names

import 'package:flutter/material.dart';

class AutocompleteSuggestion {
  final String label;
  final String insertText;
  final String detail;
  final AutocompleteKind kind;
  final IconData icon;
  final Color color;

  const AutocompleteSuggestion({
    required this.label,
    required this.insertText,
    this.detail = '',
    required this.kind,
    required this.icon,
    required this.color,
  });
}

enum AutocompleteKind {
  keyword,
  function,
  module,
  snippet,
  table,
  column,
  variable,
  method,
}

class AutocompleteProvider {
  // Active DB tables/columns (populated from SQL schema)
  static List<String> _tableNames = [];
  static Map<String, List<String>> _tableColumns = {};

  static void setSchema(List<String> tables, Map<String, List<String>> columns) {
    _tableNames = tables;
    _tableColumns = columns;
  }

  /// Get suggestions for the given language and prefix
  static List<AutocompleteSuggestion> getSuggestions(
    String language,
    String prefix, {
    String? fullText,
    int? cursorPosition,
  }) {
    if (prefix.length < 1) return [];

    final lower = prefix.toLowerCase();

    switch (language) {
      case 'python':
        return _pythonSuggestions(lower);
      case 'sql':
        return _sqlSuggestions(lower, fullText: fullText);
      case 'mermaid':
        return _mermaidSuggestions(lower);
      default:
        return [];
    }
  }

  static List<AutocompleteSuggestion> _pythonSuggestions(String prefix) {
    final all = <AutocompleteSuggestion>[];

    // Keywords
    for (final kw in _pythonKeywords) {
      if (kw.startsWith(prefix)) {
        all.add(AutocompleteSuggestion(
          label: kw,
          insertText: kw,
          detail: 'keyword',
          kind: AutocompleteKind.keyword,
          icon: Icons.vpn_key,
          color: const Color(0xFFC586C0),
        ));
      }
    }

    // Built-in functions
    for (final fn in _pythonBuiltins) {
      if (fn.startsWith(prefix)) {
        all.add(AutocompleteSuggestion(
          label: fn,
          insertText: '$fn()',
          detail: 'builtin',
          kind: AutocompleteKind.function,
          icon: Icons.functions,
          color: const Color(0xFFDCDCAA),
        ));
      }
    }

    // Common imports
    for (final entry in _pythonImports.entries) {
      if (entry.key.startsWith(prefix)) {
        all.add(AutocompleteSuggestion(
          label: entry.key,
          insertText: entry.value,
          detail: 'import',
          kind: AutocompleteKind.module,
          icon: Icons.inventory_2,
          color: const Color(0xFF4EC9B0),
        ));
      }
    }

    // Snippets
    for (final snip in _pythonSnippets.entries) {
      if (snip.key.startsWith(prefix)) {
        all.add(AutocompleteSuggestion(
          label: snip.key,
          insertText: snip.value,
          detail: 'snippet',
          kind: AutocompleteKind.snippet,
          icon: Icons.code,
          color: const Color(0xFF66D9EF),
        ));
      }
    }

    return all.take(10).toList();
  }

  static List<AutocompleteSuggestion> _sqlSuggestions(
    String prefix, {
    String? fullText,
  }) {
    final all = <AutocompleteSuggestion>[];

    // SQL Keywords
    for (final kw in _sqlKeywords) {
      if (kw.toLowerCase().startsWith(prefix)) {
        all.add(AutocompleteSuggestion(
          label: kw,
          insertText: kw,
          detail: 'keyword',
          kind: AutocompleteKind.keyword,
          icon: Icons.vpn_key,
          color: const Color(0xFF569CD6),
        ));
      }
    }

    // SQL Functions
    for (final fn in _sqlFunctions) {
      if (fn.toLowerCase().startsWith(prefix)) {
        all.add(AutocompleteSuggestion(
          label: fn,
          insertText: '$fn()',
          detail: 'function',
          kind: AutocompleteKind.function,
          icon: Icons.functions,
          color: const Color(0xFFDCDCAA),
        ));
      }
    }

    // Table names
    for (final table in _tableNames) {
      if (table.toLowerCase().startsWith(prefix)) {
        all.add(AutocompleteSuggestion(
          label: table,
          insertText: table,
          detail: 'table',
          kind: AutocompleteKind.table,
          icon: Icons.table_chart,
          color: const Color(0xFFA6E22E),
        ));
      }
    }

    // Column names (from all tables)
    for (final entry in _tableColumns.entries) {
      for (final col in entry.value) {
        if (col.toLowerCase().startsWith(prefix)) {
          all.add(AutocompleteSuggestion(
            label: col,
            insertText: col,
            detail: entry.key,
            kind: AutocompleteKind.column,
            icon: Icons.view_column,
            color: const Color(0xFF9CDCFE),
          ));
        }
      }
    }

    // SQL Snippets
    for (final snip in _sqlSnippets.entries) {
      if (snip.key.toLowerCase().startsWith(prefix)) {
        all.add(AutocompleteSuggestion(
          label: snip.key,
          insertText: snip.value,
          detail: 'snippet',
          kind: AutocompleteKind.snippet,
          icon: Icons.code,
          color: const Color(0xFF66D9EF),
        ));
      }
    }

    return all.take(10).toList();
  }

  static List<AutocompleteSuggestion> _mermaidSuggestions(String prefix) {
    final all = <AutocompleteSuggestion>[];

    for (final snip in _mermaidSnippets.entries) {
      if (snip.key.toLowerCase().startsWith(prefix)) {
        all.add(AutocompleteSuggestion(
          label: snip.key,
          insertText: snip.value,
          detail: 'diagram',
          kind: AutocompleteKind.snippet,
          icon: Icons.account_tree,
          color: const Color(0xFFA6E22E),
        ));
      }
    }

    return all.take(8).toList();
  }

  // ====== DATA ======

  static const _pythonKeywords = [
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue',
    'def', 'del', 'elif', 'else', 'except', 'finally', 'for', 'from',
    'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal', 'not',
    'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
    'True', 'False', 'None',
  ];

  static const _pythonBuiltins = [
    'print', 'len', 'range', 'type', 'int', 'float', 'str', 'list',
    'dict', 'set', 'tuple', 'bool', 'input', 'open', 'enumerate',
    'zip', 'map', 'filter', 'sorted', 'reversed', 'sum', 'min', 'max',
    'abs', 'round', 'isinstance', 'issubclass', 'hasattr', 'getattr',
  ];

  static const _pythonImports = {
    'pandas': 'import pandas as pd',
    'numpy': 'import numpy as np',
    'matplotlib': 'import matplotlib.pyplot as plt',
    'plotly': 'import plotly.express as px',
    'seaborn': 'import seaborn as sns',
    'sklearn': 'from sklearn import',
    'requests': 'import requests',
    'json': 'import json',
    'os': 'import os',
    'sys': 'import sys',
    'datetime': 'from datetime import datetime',
    'pathlib': 'from pathlib import Path',
    'csv': 'import csv',
    'sqlite3': 'import sqlite3',
    're': 'import re',
  };

  static const _pythonSnippets = {
    'df': 'df = pd.DataFrame()',
    'defn': 'def function_name():\n    pass',
    'forin': 'for item in items:\n    ',
    'ifmain': "if __name__ == '__main__':\n    ",
    'tryexcept': 'try:\n    \nexcept Exception as e:\n    print(e)',
    'with_open': "with open('file.txt', 'r') as f:\n    data = f.read()",
    'listcomp': '[x for x in items if condition]',
    'dictcomp': '{k: v for k, v in items.items()}',
    'plt_basic': "plt.figure(figsize=(10, 6))\nplt.plot(x, y)\nplt.title('Title')\nplt.show()",
    'pd_read': "df = pd.read_csv('data.csv')",
  };

  static const _sqlKeywords = [
    'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET',
    'DELETE', 'CREATE', 'TABLE', 'DROP', 'ALTER', 'ADD', 'COLUMN',
    'INDEX', 'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'ON',
    'GROUP', 'BY', 'ORDER', 'ASC', 'DESC', 'HAVING', 'LIMIT', 'OFFSET',
    'UNION', 'ALL', 'DISTINCT', 'AS', 'AND', 'OR', 'NOT', 'IN',
    'BETWEEN', 'LIKE', 'IS', 'NULL', 'EXISTS', 'CASE', 'WHEN', 'THEN',
    'ELSE', 'END', 'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES',
    'INTEGER', 'TEXT', 'REAL', 'BLOB', 'VARCHAR', 'BOOLEAN', 'DATE',
    'TIMESTAMP', 'DEFAULT', 'CONSTRAINT', 'UNIQUE', 'CHECK',
  ];

  static const _sqlFunctions = [
    'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COALESCE', 'IFNULL',
    'CAST', 'SUBSTR', 'LENGTH', 'UPPER', 'LOWER', 'TRIM',
    'REPLACE', 'ROUND', 'ABS', 'DATE', 'TIME', 'DATETIME',
    'STRFTIME', 'GROUP_CONCAT', 'RANDOM', 'TYPEOF',
  ];

  static const _sqlSnippets = {
    'sel': 'SELECT * FROM ',
    'selw': 'SELECT * FROM table_name\nWHERE ',
    'ins': "INSERT INTO table_name (col1, col2)\nVALUES ('val1', 'val2');",
    'cre': 'CREATE TABLE table_name (\n    id INTEGER PRIMARY KEY,\n    name TEXT NOT NULL\n);',
    'join': 'SELECT *\nFROM t1\nJOIN t2 ON t1.id = t2.t1_id',
    'group': 'SELECT col, COUNT(*)\nFROM table_name\nGROUP BY col\nORDER BY COUNT(*) DESC',
  };

  static const _mermaidSnippets = {
    'graph': 'graph TD\n    A[Start] --> B{Decision}\n    B -->|Yes| C[Process]\n    B -->|No| D[End]\n    C --> D',
    'sequence': 'sequenceDiagram\n    participant A\n    participant B\n    A->>B: Request\n    B-->>A: Response',
    'class': 'classDiagram\n    class Animal {\n        +String name\n        +makeSound()\n    }\n    class Dog {\n        +fetch()\n    }\n    Animal <|-- Dog',
    'state': 'stateDiagram-v2\n    [*] --> Idle\n    Idle --> Processing\n    Processing --> Done\n    Done --> [*]',
    'er': 'erDiagram\n    USER ||--o{ ORDER : places\n    ORDER ||--|{ LINE_ITEM : contains\n    PRODUCT ||--o{ LINE_ITEM : "ordered in"',
    'gantt': 'gantt\n    title Project Schedule\n    dateFormat YYYY-MM-DD\n    section Phase 1\n    Task 1: 2024-01-01, 30d\n    Task 2: 2024-02-01, 20d',
    'pie': 'pie title Distribution\n    "Category A" : 40\n    "Category B" : 30\n    "Category C" : 20\n    "Other" : 10',
    'flowchart': 'flowchart LR\n    A[Input] --> B(Process)\n    B --> C{Check}\n    C -->|Pass| D[Output]\n    C -->|Fail| E[Error]',
    'mindmap': 'mindmap\n  root((Topic))\n    Branch A\n      Leaf 1\n      Leaf 2\n    Branch B\n      Leaf 3',
    'gitgraph': 'gitgraph\n    commit\n    branch feature\n    checkout feature\n    commit\n    commit\n    checkout main\n    merge feature',
    'subgraph': 'graph TD\n    subgraph Group1\n        A --> B\n    end\n    subgraph Group2\n        C --> D\n    end\n    B --> C',
  };
}
