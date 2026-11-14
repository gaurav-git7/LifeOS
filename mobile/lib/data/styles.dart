// Icons and colors derived from data. The server stores categories and names,
// not visuals, so the app decides how things look.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';

const goalCategories = ['learning', 'career', 'health', 'personal', 'finance', 'other'];

String categoryLabel(String c) => c.isEmpty ? 'Other' : c[0].toUpperCase() + c.substring(1);

(IconData, Color) goalStyle(String category) => switch (category.toLowerCase()) {
      'learning' => (LucideIcons.layers, LifeColors.sky),
      'career' => (LucideIcons.brain, LifeColors.iris),
      'health' => (LucideIcons.activity, LifeColors.mint),
      'finance' => (LucideIcons.wallet, LifeColors.amber),
      'personal' => (LucideIcons.rocket, LifeColors.coral),
      _ => (LucideIcons.target, LifeColors.lilac),
    };

const skillCategories = ['language', 'framework', 'tool', 'concept', 'soft_skill'];

(IconData, Color) skillStyle(String name) {
  final n = name.toLowerCase();
  if (n.contains('java') && !n.contains('script')) return (LucideIcons.coffee, LifeColors.coral);
  if (n.contains('dsa') || n.contains('algorithm')) return (LucideIcons.brain, LifeColors.iris);
  if (n.contains('sql') || n.contains('data')) return (LucideIcons.database, LifeColors.sky);
  if (n.contains('flutter') || n.contains('android') || n.contains('mobile')) return (LucideIcons.smartphone, LifeColors.sky);
  if (n.contains('docker')) return (LucideIcons.container, LifeColors.mint);
  if (n.contains('kube') || n.contains('k8s')) return (LucideIcons.ship, LifeColors.mint);
  if (n.contains('python')) return (LucideIcons.code, LifeColors.amber);
  if (n.contains('cloud') || n.contains('aws') || n.contains('gcp') || n.contains('azure')) {
    return (LucideIcons.cloud, LifeColors.lilac);
  }
  const palette = [LifeColors.iris, LifeColors.sky, LifeColors.mint, LifeColors.coral, LifeColors.amber, LifeColors.rose];
  return (LucideIcons.sparkle, palette[n.hashCode.abs() % palette.length]);
}

Color projectColor(String name) {
  const palette = [LifeColors.iris, LifeColors.mint, LifeColors.amber, LifeColors.sky, LifeColors.coral, LifeColors.rose];
  return palette[name.toLowerCase().hashCode.abs() % palette.length];
}

IconData habitIcon(String title) {
  final t = title.toLowerCase();
  if (t.contains('read') || t.contains('book')) return LucideIcons.bookOpen;
  if (t.contains('gym') || t.contains('run') || t.contains('walk') || t.contains('workout')) return LucideIcons.activity;
  if (t.contains('dsa') || t.contains('code') || t.contains('leet')) return LucideIcons.brain;
  if (t.contains('sleep')) return LucideIcons.moon;
  if (t.contains('water') || t.contains('drink')) return LucideIcons.droplet;
  if (t.contains('meditat') || t.contains('breath')) return LucideIcons.flower2;
  if (t.contains('journal') || t.contains('write')) return LucideIcons.penLine;
  return LucideIcons.sparkle;
}
