import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/widgets.dart';
import '../data/models.dart';
import '../data/stores.dart';

/// Create or edit a task in a glass sheet.
Future<void> showTaskEditor(BuildContext context, {Task? task, DateTime? defaultDue}) {
  return showGlassSheet<void>(
    context,
    title: task == null ? 'New task' : 'Edit task',
    builder: (_) => _TaskEditor(task: task, defaultDue: defaultDue),
  );
}

class _TaskEditor extends ConsumerStatefulWidget {
  const _TaskEditor({this.task, this.defaultDue});

  final Task? task;
  final DateTime? defaultDue;

  @override
  ConsumerState<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<_TaskEditor> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _notes = TextEditingController(text: widget.task?.description);
  late Priority _priority = widget.task?.priority ?? Priority.medium;
  late DateTime? _due = widget.task?.due ?? widget.defaultDue;
  late bool _hasTime = widget.task?.hasTime ?? false;
  late int? _estimate = widget.task?.estimatedMinutes;
  late String? _goalId = widget.task?.goalId;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final tasks = ref.read(tasksProvider.notifier);
    final existing = widget.task;
    if (existing == null) {
      tasks.add(Task(
        id: newId(),
        title: title,
        description: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        priority: _priority,
        due: _due,
        hasTime: _hasTime,
        estimatedMinutes: _estimate,
        goalId: _goalId,
      ));
    } else {
      tasks.update(Task(
        id: existing.id,
        title: title,
        description: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        priority: _priority,
        due: _due,
        hasTime: _hasTime,
        estimatedMinutes: _estimate,
        goalId: _goalId,
        done: existing.done,
        completedAt: existing.completedAt,
        subtasks: existing.subtasks,
        tags: existing.tags,
      ));
    }
    Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      initialDate: _due ?? now,
    );
    if (picked != null) {
      setState(() => _due = _hasTime && _due != null
        ? DateTime(picked.year, picked.month, picked.day, _due!.hour, _due!.minute)
        : picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _due != null && _hasTime ? TimeOfDay.fromDateTime(_due!) : const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked == null) return;
    final base = _due ?? DateTime.now();
    setState(() {
      _due = DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
      _hasTime = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = dateOnly(DateTime.now());
    final goals = ref.watch(goalsProvider);
    final task = widget.task;
    final live = task == null ? null : ref.watch(tasksProvider).where((t) => t.id == task.id).firstOrNull;
    final dueChips = <(String, DateTime?)>[
      ('Today', now),
      ('Tomorrow', now.add(const Duration(days: 1))),
      ('Next week', now.add(Duration(days: 8 - now.weekday))),
      ('No date', null),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: task == null,
              textCapitalization: TextCapitalization.sentences,
              style: LifeText.title,
              decoration: const InputDecoration(hintText: 'What needs doing?'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              style: LifeText.body,
              decoration: const InputDecoration(hintText: 'Notes (optional)'),
            ),
            const SizedBox(height: Space.xl),
            Text('Priority', style: LifeText.eyebrow),
            const SizedBox(height: Space.sm),
            SegmentedGlass(
              segments: const ['Low', 'Medium', 'High'],
              index: _priority.index,
              onChanged: (i) => setState(() => _priority = Priority.values[i]),
            ),
            const SizedBox(height: Space.xl),
            Row(
              children: [
                Expanded(child: Text('Due', style: LifeText.eyebrow)),
                if (_due != null)
                  Text(
                    _hasTime ? DateFormat('EEE d MMM · h:mm a').format(_due!) : DateFormat('EEE d MMM').format(_due!),
                    style: LifeText.mono.copyWith(color: LifeColors.text),
                  ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final c in dueChips)
                  GlassChip(
                    data: FilterChipData(c.$1),
                    selected: c.$2 == null ? _due == null : (_due != null && sameDay(_due!, c.$2!)),
                    onTap: () => setState(() {
                      _due = c.$2;
                      if (c.$2 == null) _hasTime = false;
                    }),
                  ),
                GlassChip(data: const FilterChipData('Pick date', icon: LucideIcons.calendarDays), selected: false, onTap: _pickDate),
                GlassChip(
                  data: FilterChipData(_hasTime ? 'Change time' : 'Add time', icon: LucideIcons.clock),
                  selected: false,
                  onTap: _pickTime,
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            Text('Estimate', style: LifeText.eyebrow),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final m in [15, 30, 45, 60, 90])
                  GlassChip(
                    data: FilterChipData(formatMinutes(m.toDouble())),
                    selected: _estimate == m,
                    onTap: () => setState(() => _estimate = _estimate == m ? null : m),
                  ),
              ],
            ),
            if (goals.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              Text('Goal', style: LifeText.eyebrow),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final g in goals)
                    GlassChip(
                      data: FilterChipData(g.title, icon: g.icon, accent: g.color),
                      selected: _goalId == g.id,
                      onTap: () => setState(() => _goalId = _goalId == g.id ? null : g.id),
                    ),
                ],
              ),
            ],
            if (live != null && live.subtasks.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              Text('Steps', style: LifeText.eyebrow),
              for (final s in live.subtasks)
                Row(
                  children: [
                    AnimatedCheck(
                      checked: s.done,
                      size: 20,
                      onChanged: (_) => ref.read(tasksProvider.notifier).toggleSubtask(live.id, s.id),
                    ),
                    Expanded(
                      child: Text(
                        s.title,
                        style: LifeText.body.copyWith(
                          color: s.done ? LifeColors.text3 : LifeColors.text,
                          decoration: s.done ? TextDecoration.lineThrough : null,
                          decorationColor: LifeColors.text3,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: Space.xxl),
            Row(
              children: [
                if (task != null) ...[
                  GradientButton(
                    label: 'Delete',
                    icon: LucideIcons.trash2,
                    variant: ButtonVariant.danger,
                    onPressed: () {
                      ref.read(tasksProvider.notifier).delete(task.id);
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: Space.sm),
                ],
                Expanded(
                  child: ListenableBuilder(
                    listenable: _title,
                    builder: (context, _) => GradientButton(
                      label: task == null ? 'Add task' : 'Save',
                      expand: true,
                      onPressed: _title.text.trim().isEmpty ? null : _save,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
