import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';

/// Everything the assistant remembers — view, edit, delete. ARCHITECTURE.md §13.
class MemoriesScreen extends ConsumerWidget {
  const MemoriesScreen({super.key});

  static const _types = {
    MemoryType.profile: ('About you', LucideIcons.user, LifeColors.iris),
    MemoryType.preference: ('Preferences', LucideIcons.slidersHorizontal, LifeColors.sky),
    MemoryType.episodic: ('Moments', LucideIcons.history, LifeColors.mint),
    MemoryType.summary: ('Latest summary', LucideIcons.fileText, LifeColors.amber),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memories = ref.watch(memoriesProvider);
    final enabled = ref.watch(prefsProvider.select((p) => p.aiMemory));
    final proposed = memories.where((m) => m.proposed).toList();

    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.assistant)),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.screen, Space.lg, Space.screen, 60),
              children: [
                Row(
                  children: [
                    IconGlassButton(icon: Icons.arrow_back_rounded, semanticLabel: 'Back', onPressed: () => context.pop()),
                    const Spacer(),
                    IconGlassButton(icon: LucideIcons.plus, semanticLabel: 'Add memory', onPressed: () => _edit(context, ref)),
                  ],
                ),
                const SizedBox(height: Space.lg),
                Text('What your assistant knows', style: LifeText.eyebrow),
                Text('Memory', style: LifeText.display),
                const SizedBox(height: Space.md),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Remember things about me', style: LifeText.bodyStrong),
                            Text('Off = nothing new is stored', style: LifeText.caption),
                          ],
                        ),
                      ),
                      Switch(
                        value: enabled,
                        onChanged: (v) => ref.read(prefsProvider.notifier).update((p) => p.copyWith(aiMemory: v)),
                      ),
                    ],
                  ),
                ),
                if (proposed.isNotEmpty) ...[
                  const SizedBox(height: Space.section),
                  const SectionHeader(title: 'Suggested by your assistant'),
                  for (final m in proposed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.cardGap),
                      child: GlassCard(
                        ai: true,
                        padding: const EdgeInsets.all(Space.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(m.content, style: LifeText.body),
                            const SizedBox(height: Space.md),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                GradientButton(
                                  label: 'Discard',
                                  compact: true,
                                  variant: ButtonVariant.ghost,
                                  onPressed: () => ref.read(memoriesProvider.notifier).remove(m.id),
                                ),
                                const SizedBox(width: Space.sm),
                                GradientButton(
                                  label: 'Keep',
                                  compact: true,
                                  onPressed: () => ref.read(memoriesProvider.notifier).keep(m.id),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                for (final type in _types.keys) ...[
                  if (memories.any((m) => m.type == type && !m.proposed)) ...[
                    const SizedBox(height: Space.section),
                    Row(
                      children: [
                        IconChip(icon: _types[type]!.$2, color: _types[type]!.$3, size: 26),
                        const SizedBox(width: Space.sm),
                        Text(_types[type]!.$1, style: LifeText.title),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
                      child: Column(
                        children: [
                          for (final (i, m) in memories.where((m) => m.type == type && !m.proposed).indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: Space.md),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: Text(m.content, style: LifeText.body)),
                                  GestureDetector(
                                    onTap: () => _edit(context, ref, m),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(LucideIcons.pencil, size: 16, color: LifeColors.text3),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => ref.read(memoriesProvider.notifier).remove(m.id),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(LucideIcons.trash2, size: 16, color: LifeColors.text3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _edit(BuildContext context, WidgetRef ref, [Memory? m]) {
    final c = TextEditingController(text: m?.content);
    showGlassSheet<void>(
      context,
      title: m == null ? 'Tell your assistant something' : 'Edit memory',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: c,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'e.g. I study best before noon'),
          ),
          const SizedBox(height: Space.lg),
          GradientButton(
            label: 'Save',
            expand: true,
            onPressed: () {
              final text = c.text.trim();
              if (text.isEmpty) return;
              if (m == null) {
                ref.read(memoriesProvider.notifier).add(Memory(id: newId(), type: MemoryType.preference, content: text));
              } else {
                ref.read(memoriesProvider.notifier).edit(m.id, text);
              }
              Navigator.of(sheet).pop();
            },
          ),
        ],
      ),
    );
  }
}
