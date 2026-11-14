// "New …" sheets for goals, milestones, projects, skills, roadmaps, topics and
// time blocks. Each validates input and writes through the stores.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/widgets.dart';
import '../data/models.dart';
import '../data/seed.dart';
import '../data/stores.dart';
import '../data/styles.dart';

/// Scrollable sheet body with a primary save button that enables when [canSave].
class _SheetForm extends StatelessWidget {
  const _SheetForm({required this.children, required this.saveLabel, required this.canSave, required this.onSave});

  final List<Widget> children;
  final String saveLabel;
  final bool canSave;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...children,
            const SizedBox(height: Space.xl),
            GradientButton(label: saveLabel, expand: true, onPressed: canSave ? onSave : null),
          ],
        ),
      ),
    );
  }
}

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
      child: Text(text, style: LifeText.eyebrow),
    );

Future<DateTime?> _pickDate(BuildContext context, DateTime? initial) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    firstDate: dateOnly(now),
    lastDate: DateTime(now.year + 5),
    initialDate: initial ?? now.add(const Duration(days: 30)),
  );
}

Widget _dateChip(BuildContext context, DateTime? value, ValueChanged<DateTime?> onChanged, {String empty = 'No deadline'}) {
  return Wrap(
    spacing: Space.sm,
    runSpacing: Space.sm,
    children: [
      GlassChip(
        data: FilterChipData(value == null ? 'Pick a date' : DateFormat('EEE d MMM yyyy').format(value), icon: LucideIcons.calendarDays),
        selected: value != null,
        onTap: () async => onChanged(await _pickDate(context, value) ?? value),
      ),
      if (value != null) GlassChip(data: FilterChipData(empty), selected: false, onTap: () => onChanged(null)),
    ],
  );
}

List<String> _lines(String text) =>
    text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

// ---------------------------------------------------------------- goal

Future<void> showGoalEditor(BuildContext context) =>
    showGlassSheet<void>(context, title: 'New goal', builder: (_) => const _GoalEditor());

class _GoalEditor extends ConsumerStatefulWidget {
  const _GoalEditor();

  @override
  ConsumerState<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<_GoalEditor> {
  final _title = TextEditingController();
  final _milestones = TextEditingController();
  final _target = TextEditingController();
  final _unit = TextEditingController();
  String _category = 'learning';
  int _type = 0; // 0 milestones/tasks, 1 numeric
  DateTime? _date;

  @override
  void dispose() {
    for (final c in [_title, _milestones, _target, _unit]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty && (_type == 0 || (double.tryParse(_target.text.trim()) ?? 0) > 0);

  void _save() {
    final (icon, color) = goalStyle(_category);
    ref.read(goalsProvider.notifier).add(Goal(
          id: newId(),
          title: _title.text.trim(),
          category: categoryLabel(_category),
          icon: icon,
          color: color,
          progressType: _type == 1 ? GoalProgressType.numeric : GoalProgressType.tasks,
          target: _type == 1 ? double.tryParse(_target.text.trim()) : null,
          current: _type == 1 ? 0 : null,
          unit: _type == 1 && _unit.text.trim().isNotEmpty ? _unit.text.trim() : null,
          targetDate: _date,
          milestones: _type == 0 ? [for (final l in _lines(_milestones.text)) Milestone(id: newId(), title: l)] : const [],
        ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_title, _target]),
      builder: (context, _) => _SheetForm(
        saveLabel: 'Create goal',
        canSave: _valid,
        onSave: _save,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: LifeText.title,
            decoration: const InputDecoration(hintText: 'e.g. Crack DSA interviews'),
          ),
          _label('Category'),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final c in goalCategories)
                GlassChip(
                  data: FilterChipData(categoryLabel(c), icon: goalStyle(c).$1, accent: goalStyle(c).$2),
                  selected: _category == c,
                  onTap: () => setState(() => _category = c),
                ),
            ],
          ),
          _label('Track progress by'),
          SegmentedGlass(segments: const ['Milestones & tasks', 'A number'], index: _type, onChanged: (i) => setState(() => _type = i)),
          if (_type == 0) ...[
            _label('Milestones (one per line, optional)'),
            TextField(
              controller: _milestones,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(hintText: 'Arrays & hashing\nTrees & graphs\nDynamic programming'),
            ),
          ] else ...[
            _label('Target'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _target,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: '12'),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(child: TextField(controller: _unit, decoration: const InputDecoration(hintText: 'books'))),
              ],
            ),
          ],
          _label('Target date'),
          _dateChip(context, _date, (d) => setState(() => _date = d)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- milestone (goal or project)

Future<void> showMilestoneAdder(BuildContext context, {String? goalId, String? projectId}) {
  final c = TextEditingController();
  return showGlassSheet<void>(
    context,
    title: 'Add milestone',
    builder: (sheet) => Consumer(
      builder: (context, ref, _) => ListenableBuilder(
        listenable: c,
        builder: (context, _) => _SheetForm(
          saveLabel: 'Add',
          canSave: c.text.trim().isNotEmpty,
          onSave: () {
            final m = Milestone(id: newId(), title: c.text.trim());
            if (goalId != null) ref.read(goalsProvider.notifier).addMilestone(goalId, m);
            if (projectId != null) ref.read(learningProvider.notifier).addProjectMilestone(projectId, m);
            Navigator.of(sheet).pop();
          },
          children: [
            TextField(
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. Compose & networking'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- project

Future<void> showProjectEditor(BuildContext context) =>
    showGlassSheet<void>(context, title: 'New project', builder: (_) => const _ProjectEditor());

class _ProjectEditor extends ConsumerStatefulWidget {
  const _ProjectEditor();

  @override
  ConsumerState<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends ConsumerState<_ProjectEditor> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _stack = TextEditingController();
  final _milestones = TextEditingController();
  DateTime? _deadline;

  @override
  void dispose() {
    for (final c in [_name, _desc, _stack, _milestones]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final ms = [for (final l in _lines(_milestones.text)) Milestone(id: newId(), title: l)];
    ref.read(learningProvider.notifier).addProject(Project(
          id: newId(),
          name: _name.text.trim(),
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          stack: _stack.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
          progress: 0,
          color: projectColor(_name.text.trim()),
          deadline: _deadline,
          nextMilestone: ms.isEmpty ? null : ms.first.title,
          milestones: ms,
        ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _name,
      builder: (context, _) => _SheetForm(
        saveLabel: 'Create project',
        canSave: _name.text.trim().isNotEmpty,
        onSave: _save,
        children: [
          TextField(controller: _name, autofocus: true, style: LifeText.title, decoration: const InputDecoration(hintText: 'Project name')),
          const SizedBox(height: Space.md),
          TextField(controller: _desc, maxLines: 2, decoration: const InputDecoration(hintText: 'What is it? (optional)')),
          _label('Tech stack (comma-separated)'),
          TextField(controller: _stack, decoration: const InputDecoration(hintText: 'Flutter, FastAPI, Postgres')),
          _label('Milestones (one per line, optional)'),
          TextField(controller: _milestones, minLines: 2, maxLines: 5, decoration: const InputDecoration(hintText: 'MVP\nBeta\nLaunch')),
          _label('Deadline'),
          _dateChip(context, _deadline, (d) => setState(() => _deadline = d)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- skill

Future<void> showSkillEditor(BuildContext context) =>
    showGlassSheet<void>(context, title: 'Track a skill', builder: (_) => const _SkillEditor());

class _SkillEditor extends ConsumerStatefulWidget {
  const _SkillEditor();

  @override
  ConsumerState<_SkillEditor> createState() => _SkillEditorState();
}

class _SkillEditorState extends ConsumerState<_SkillEditor> {
  final _name = TextEditingController();
  int _level = 1;
  int _target = 3;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const levels = ['Aware', 'Beginner', 'Comfortable', 'Proficient', 'Expert'];
    return ListenableBuilder(
      listenable: _name,
      builder: (context, _) => _SheetForm(
        saveLabel: 'Add skill',
        canSave: _name.text.trim().isNotEmpty,
        onSave: () {
          final (icon, color) = skillStyle(_name.text.trim());
          ref.read(learningProvider.notifier).addSkill(Skill(
                id: newId(),
                name: _name.text.trim(),
                icon: icon,
                color: color,
                level: _level,
                target: _target < _level ? _level : _target,
              ));
          Navigator.of(context).pop();
        },
        children: [
          TextField(controller: _name, autofocus: true, style: LifeText.title, decoration: const InputDecoration(hintText: 'e.g. Kubernetes')),
          _label('Where you are now · ${levels[_level - 1]}'),
          SegmentedGlass(segments: const ['1', '2', '3', '4', '5'], index: _level - 1, onChanged: (i) => setState(() => _level = i + 1)),
          _label('Where you want to be · ${levels[_target - 1]}'),
          SegmentedGlass(segments: const ['1', '2', '3', '4', '5'], index: _target - 1, onChanged: (i) => setState(() => _target = i + 1)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- roadmap + topic

Future<void> showRoadmapEditor(BuildContext context) =>
    showGlassSheet<void>(context, title: 'New roadmap', builder: (_) => const _RoadmapEditor());

class _RoadmapEditor extends ConsumerStatefulWidget {
  const _RoadmapEditor();

  @override
  ConsumerState<_RoadmapEditor> createState() => _RoadmapEditorState();
}

class _RoadmapEditorState extends ConsumerState<_RoadmapEditor> {
  final _title = TextEditingController();
  final _topics = TextEditingController();
  String? _skillId;
  DateTime? _date;

  @override
  void dispose() {
    _title.dispose();
    _topics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skills = ref.watch(learningProvider.select((s) => s.skills));
    return ListenableBuilder(
      listenable: Listenable.merge([_title, _topics]),
      builder: (context, _) => _SheetForm(
        saveLabel: 'Create roadmap',
        canSave: _title.text.trim().isNotEmpty && _lines(_topics.text).isNotEmpty,
        onSave: () {
          final lines = _lines(_topics.text);
          ref.read(learningProvider.notifier).addPath(LearningPath(
                id: newId(),
                title: _title.text.trim(),
                skillId: _skillId,
                targetDate: _date,
                topics: [
                  for (final (i, l) in lines.indexed)
                    Topic(id: newId(), title: l, difficulty: i < lines.length / 3 ? Difficulty.easy : (i < lines.length * 2 / 3 ? Difficulty.medium : Difficulty.hard)),
                ],
              ));
          Navigator.of(context).pop();
        },
        children: [
          TextField(controller: _title, autofocus: true, style: LifeText.title, decoration: const InputDecoration(hintText: 'e.g. System design basics')),
          _label('Topics, in order (one per line)'),
          TextField(
            controller: _topics,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(hintText: 'Scalability\nCaching\nLoad balancing\nDatabases'),
          ),
          if (skills.isNotEmpty) ...[
            _label('Skill (optional)'),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final s in skills)
                  GlassChip(
                    data: FilterChipData(s.name, icon: s.icon, accent: s.color),
                    selected: _skillId == s.id,
                    onTap: () => setState(() => _skillId = _skillId == s.id ? null : s.id),
                  ),
              ],
            ),
          ],
          _label('Target date'),
          _dateChip(context, _date, (d) => setState(() => _date = d)),
        ],
      ),
    );
  }
}

Future<void> showTopicAdder(BuildContext context, String pathId) {
  final c = TextEditingController();
  var difficulty = Difficulty.medium;
  return showGlassSheet<void>(
    context,
    title: 'Add topic',
    builder: (sheet) => Consumer(
      builder: (context, ref, _) => StatefulBuilder(
        builder: (context, setState) => ListenableBuilder(
          listenable: c,
          builder: (context, _) => _SheetForm(
            saveLabel: 'Add topic',
            canSave: c.text.trim().isNotEmpty,
            onSave: () {
              ref.read(learningProvider.notifier).addTopic(pathId, Topic(id: newId(), title: c.text.trim(), difficulty: difficulty));
              Navigator.of(sheet).pop();
            },
            children: [
              TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Heaps & priority queues')),
              _label('Difficulty'),
              SegmentedGlass(
                segments: const ['Easy', 'Medium', 'Hard'],
                index: difficulty.index,
                onChanged: (i) => setState(() => difficulty = Difficulty.values[i]),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- time block

Future<void> showBlockEditor(BuildContext context, DateTime day) =>
    showGlassSheet<void>(context, title: 'Block time', builder: (_) => _BlockEditor(day: day));

class _BlockEditor extends ConsumerStatefulWidget {
  const _BlockEditor({required this.day});

  final DateTime day;

  @override
  ConsumerState<_BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<_BlockEditor> {
  final _title = TextEditingController();
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  int _minutes = 60;
  BlockType _type = BlockType.focus;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
    return ListenableBuilder(
      listenable: _title,
      builder: (context, _) => _SheetForm(
        saveLabel: 'Add to ${DateFormat('EEE d MMM').format(d)}',
        canSave: _title.text.trim().isNotEmpty,
        onSave: () {
          ref.read(scheduleProvider.notifier).add(ScheduleBlock(
                id: newId(),
                title: _title.text.trim(),
                start: start,
                end: start.add(Duration(minutes: _minutes)),
                type: _type,
              ));
          Navigator.of(context).pop();
        },
        children: [
          TextField(controller: _title, autofocus: true, style: LifeText.title, decoration: const InputDecoration(hintText: 'e.g. Deep work · DSA')),
          _label('Starts'),
          GlassChip(
            data: FilterChipData(_start.format(context), icon: LucideIcons.clock),
            selected: true,
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _start);
              if (t != null) setState(() => _start = t);
            },
          ),
          _label('Length'),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final m in [25, 45, 60, 90, 120])
                GlassChip(data: FilterChipData(formatMinutes(m.toDouble())), selected: _minutes == m, onTap: () => setState(() => _minutes = m)),
            ],
          ),
          _label('Type'),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final t in [BlockType.focus, BlockType.study, BlockType.task, BlockType.breakTime, BlockType.other])
                GlassChip(data: FilterChipData(t.label, accent: t.color), selected: _type == t, onTap: () => setState(() => _type = t)),
            ],
          ),
        ],
      ),
    );
  }
}
