import 'package:flutter/material.dart';

/// LifeOS palette (v2 — liquid glass). See docs/UI_UX.md §4.1.
///
/// Neutral, cool near-black base; color comes from the mesh background and
/// a set of accents that each have a job. Glass is white-tinted, not purple.
abstract final class LifeColors {
  // Base
  static const bg = Color(0xFF07070B);
  static const bgElevated = Color(0xFF101016);

  /// Opaque card for dense lists (no blur).
  static const solid = Color(0xFF14141B);
  static const surfaceHigh = Color(0xFF1D1D26);

  // Text (Apple-style opacity steps on white)
  static const text = Color(0xFFF5F5F7);
  static const text2 = Color(0x9EEBEBF5); // 62%
  static const text3 = Color(0x61EBEBF5); // 38%
  static const onLight = Color(0xFF0B0B10); // text on white buttons

  // Glass
  static const glass = Color(0x0FFFFFFF); // 6%
  static const glassHigh = Color(0x1AFFFFFF); // 10%
  static const glassActive = Color(0x29FFFFFF); // 16%
  static const glassBorder = Color(0x1FFFFFFF); // 12%
  static const hairline = Color(0x14FFFFFF); // 8%
  static const track = Color(0x14FFFFFF);
  static const grid = Color(0x0FFFFFFF);

  // Accents
  static const iris = Color(0xFF8E7CFF); // primary / tasks / AI
  static const lilac = Color(0xFFC3B5FF);
  static const sky = Color(0xFF5DB7FF); // goals
  static const mint = Color(0xFF4FE0B0); // learning / study / success
  static const coral = Color(0xFFFF8E6E); // habits
  static const rose = Color(0xFFFF6FAE); // journal / mood
  static const amber = Color(0xFFFFC46B); // warnings / streaks

  // Semantic
  static const success = mint;
  static const warning = amber;
  static const danger = Color(0xFFFF6B7A);

  // Domains
  static const tasks = iris;
  static const habits = coral;
  static const learning = mint;
  static const goals = sky;
  static const journal = rose;

  // Priority
  static const priorityHigh = coral;
  static const priorityMedium = iris;
  static const priorityLow = sky;

  /// Mood 1..5 — low moods are cool and calm, never red.
  static const mood = <Color>[
    Color(0xFF7C8AA5),
    Color(0xFF8E7CFF),
    Color(0xFF5DB7FF),
    Color(0xFF4FE0B0),
    Color(0xFFFFC46B),
  ];
}
