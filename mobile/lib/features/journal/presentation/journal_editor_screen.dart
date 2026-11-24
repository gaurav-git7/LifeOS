import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';
import '../../../data/system_channel.dart';

/// Minimal full-screen editor with autosave. AI access is off unless the
/// entry is unlocked (lock icon). See docs/UI_UX.md §9.4.
class JournalEditorScreen extends ConsumerStatefulWidget {
  const JournalEditorScreen({super.key, this.entryId, this.prompt, this.day});

  final String? entryId;
  final String? prompt;
  final DateTime? day;

  @override
  ConsumerState<JournalEditorScreen> createState() => _JournalEditorScreenState();
}

class _JournalEditorScreenState extends ConsumerState<JournalEditorScreen> {
  late final String _id;
  late final DateTime _day;
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _aiAllowed;
  String? _prompt;
  Timer? _debounce;
  bool _saved = true;
  bool _everSaved = false;
  late final JournalNotifier _journal = ref.read(journalProvider.notifier); // usable in dispose()

  static String _draftKey(String id) => 'lifeos_draft_$id';

  @override
  void initState() {
    super.initState();
    final existing = widget.entryId == null
        ? null
        : ref.read(journalProvider).entries.where((e) => e.id == widget.entryId).firstOrNull;
    _id = existing?.id ?? newId();
    _day = existing?.day ?? dateOnly(widget.day ?? DateTime.now());
    _title = TextEditingController(text: existing?.title);
    _body = TextEditingController(text: existing?.content);
    _aiAllowed = existing?.aiAllowed ?? ref.read(prefsProvider).journalAi;
    _prompt = existing?.prompt ?? widget.prompt;
    _everSaved = existing != null;
    _journal; // initialise while ref is valid
    if (ref.read(prefsProvider).journalLock) SystemChannel.setSecure(true); // hide from recents / screenshots
    _title.addListener(_changed);
    _body.addListener(_changed);
    if (existing == null) Future.microtask(_restoreDraftIfAny);
  }

  Future<void> _restoreDraftIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey('new'));
      if (raw == null || !mounted) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final t = (m['title'] as String?) ?? '';
      final b = (m['body'] as String?) ?? '';
      if ((t.isNotEmpty || b.isNotEmpty) && _title.text.isEmpty && _body.text.isEmpty) {
        setState(() {
          _title.text = t;
          _body.text = b;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restored unsaved draft'), duration: Duration(seconds: 2)),
        );
      }
    } catch (_) {}
  }

  void _saveDraft() {
    unawaited(SharedPreferences.getInstance().then((p) {
      final draft = jsonEncode({'title': _title.text, 'body': _body.text, 'saved_at': DateTime.now().toUtc().toIso8601String()});
      p.setString(_draftKey(_id), draft);
      if (widget.entryId == null) p.setString(_draftKey('new'), draft);
    }).catchError((_) {}));
  }

  void _clearDraft() {
    unawaited(SharedPreferences.getInstance().then((p) {
      p.remove(_draftKey(_id));
      p.remove(_draftKey('new'));
    }).catchError((_) {}));
  }

  void _changed() {
    setState(() => _saved = false);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _save);
  }

  void _save() {
    if (_body.text.trim().isEmpty && _title.text.trim().isEmpty) return;
    _journal.upsertEntry(JournalEntry(
          id: _id,
          day: _day,
          title: _title.text.trim().isEmpty ? null : _title.text.trim(),
          content: _body.text,
          aiAllowed: _aiAllowed,
          prompt: _prompt,
        ));
    _saveDraft();
    if (mounted) {
      setState(() {
        _saved = true;
        _everSaved = true;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (!_saved) _save();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = _body.text.trim().isEmpty ? 0 : _body.text.trim().split(RegExp(r'\s+')).length;
    return Scaffold(
      backgroundColor: LifeColors.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.journal)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.screen, Space.md, Space.screen, 0),
                  child: Row(
                    children: [
                      IconGlassButton(icon: Icons.arrow_back_rounded, semanticLabel: 'Back', onPressed: () => context.pop()),
                      const SizedBox(width: Space.sm),
                      Expanded(child: Text(DateFormat('EEEE, d MMMM').format(_day), style: LifeText.label)),
                      AnimatedSwitcher(
                        duration: Motion.of(context, Motion.card),
                        child: Text(
                          _saved ? (_everSaved ? 'Saved' : '') : 'Saving…',
                          key: ValueKey(_saved),
                          style: LifeText.caption.copyWith(color: _saved ? LifeColors.mint : LifeColors.text3),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      IconGlassButton(
                        icon: _aiAllowed ? LucideIcons.sparkles : LucideIcons.lock,
                        semanticLabel: _aiAllowed ? 'Assistant can read this entry' : 'Private entry',
                        onPressed: () {
                          setState(() => _aiAllowed = !_aiAllowed);
                          _save();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(_aiAllowed
                                ? 'The assistant may read this entry (only if journal AI is on in Settings).'
                                : 'Private — the assistant can’t read this entry.'),
                          ));
                        },
                      ),
                      if (_everSaved)
                        IconGlassButton(
                          icon: LucideIcons.trash2,
                          semanticLabel: 'Delete entry',
                          onPressed: () async {
                            final ok = await showGlassConfirm(
                              context,
                              title: 'Delete this entry?',
                              message: 'It’s removed from all your devices. This can’t be undone.',
                            );
                            if (ok) {
                              _debounce?.cancel();
                              _saved = true;
                              _clearDraft();
                              ref.read(journalProvider.notifier).deleteEntry(_id);
                              if (context.mounted) context.pop();
                            }
                          },
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Space.screen, Space.xl, Space.screen, Space.xxl),
                    children: [
                      if (_prompt != null) ...[
                        Text(_prompt!, style: LifeText.titleSerifItalic.copyWith(fontSize: 22, color: LifeColors.text2)),
                        const SizedBox(height: Space.lg),
                      ],
                      TextField(
                        controller: _title,
                        style: LifeText.titleSerif,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Title',
                          hintStyle: LifeText.titleSerif.copyWith(color: LifeColors.text3),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      SizedBox(
                        height: 32,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final p in const [
                              'What went well?',
                              'What didn’t go as planned?',
                              'What did I learn?',
                              'What will I improve?',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: Space.xs),
                                child: Pressable(
                                  onTap: () {
                                    final header = '### $p\n\n';
                                    if (_body.text.contains(p)) return;
                                    final prefix = _body.text.trim().isEmpty ? '' : '\n\n';
                                    _body.text = '${_body.text}$prefix$header';
                                    _body.selection = TextSelection.collapsed(offset: _body.text.length);
                                    _changed();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: LifeColors.glass,
                                      borderRadius: BorderRadius.circular(Radii.pill),
                                      border: Border.all(color: LifeColors.glassBorder),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(LucideIcons.plus, size: 12, color: LifeColors.rose),
                                        const SizedBox(width: 4),
                                        Text(p, style: LifeText.caption.copyWith(color: LifeColors.text2, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      TextField(
                        controller: _body,
                        autofocus: widget.entryId == null,
                        maxLines: null,
                        minLines: 12,
                        style: LifeText.body.copyWith(fontSize: 17, height: 1.6),
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: 'Write freely. It saves as you type.',
                          hintStyle: LifeText.body.copyWith(fontSize: 17, color: LifeColors.text3),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.only(top: Space.md),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Text('$words words', style: LifeText.mono),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
