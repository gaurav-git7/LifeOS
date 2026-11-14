import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
