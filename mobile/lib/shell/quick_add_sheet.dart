import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/routing/routes.dart';
import '../core/widgets/widgets.dart';
import '../data/models.dart';
import '../data/stores.dart';
import '../shared/task_editor_sheet.dart';
import 'quick_capture_parser.dart';

/// Solid white "+" button above the nav bar. See docs/UI_UX.md §8.3.
class QuickAddFab extends StatelessWidget {
  const QuickAddFab({super.key});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      haptic: true,
      scale: 0.9,
      semanticLabel: 'Quick add',
      onTap: () => showGlassSheet<void>(context, builder: (_) => const QuickAddSheet()),
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: LifeShadows.float),
        child: const Icon(LucideIcons.plus, color: LifeColors.onLight, size: 24),
      ),
    );
  }
}

/// Type a line ("study graphs tomorrow 7pm") → preview → Add. Rules only, no AI.
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key});

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _controller = TextEditingController();
  QuickCapture? _preview;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _preview = v.trim().isEmpty ? null : QuickCaptureParser.parse(v));
  }

  void _submit() {
    final p = _preview;
    if (p == null) return;
    ref.read(tasksProvider.notifier).add(Task(id: newId(), title: p.title, due: p.due, hasTime: p.hasTime));
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text('Added “${p.title}”${p.dueLabel != null ? ' · ${p.dueLabel}' : ''}'),
    ));
  }

  void _then(void Function(BuildContext root) action) {
    final router = GoRouter.of(context);
    final root = router.routerDelegate.navigatorKey.currentContext!;
    Navigator.of(context).pop();
    action(root);
  }

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, Color, void Function(BuildContext))>[
      (LucideIcons.squareCheck, 'Task', LifeColors.iris, (c) => showTaskEditor(c)),
      (LucideIcons.alarmClock, 'Reminder', LifeColors.amber, (c) => showTaskEditor(c, defaultDue: DateTime.now())),
      (LucideIcons.penLine, 'Journal', LifeColors.rose, (c) => c.push(Routes.journalNew())),
      (LucideIcons.smile, 'Mood', LifeColors.coral, (c) => c.go(Routes.journal)),
      (LucideIcons.timer, 'Study session', LifeColors.mint, (c) => c.push(Routes.focus)),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          onSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          style: LifeText.body,
          decoration: const InputDecoration(
            hintText: 'Type anything… “study graphs tomorrow 7pm”',
            prefixIcon: Icon(LucideIcons.sparkles, size: 18, color: LifeColors.lilac),
          ),
        ),
        AnimatedSize(
          duration: Motion.size(context, Motion.card),
          curve: Motion.inOut,
          child: _preview == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Space.md),
                  child: GlassCard(
                    ai: true,
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
                    child: Row(
                      children: [
                        const IconChip(icon: LucideIcons.squareCheck, color: LifeColors.iris),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_preview!.title, style: LifeText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                              Text(_preview!.dueLabel ?? 'No date', style: LifeText.caption),
                            ],
                          ),
                        ),
                        GradientButton(label: 'Add', compact: true, onPressed: _submit),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: Space.xl),
        Text('Or create', style: LifeText.eyebrow),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final a in actions)
              GlassChip(
                data: FilterChipData(a.$2, icon: a.$1, accent: a.$3),
                selected: false,
                onTap: () => _then(a.$4),
              ),
          ],
        ),
      ],
    );
  }
}
