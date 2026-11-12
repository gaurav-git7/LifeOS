import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/models.dart';
import '../../../data/stores.dart';
import 'approval_cards.dart';

const _suggestions = [
  (LucideIcons.calendarCheck, 'Plan tomorrow'),
  (LucideIcons.chartSpline, 'How am I doing this week?'),
  (LucideIcons.rocket, 'Make a roadmap to learn Kubernetes'),
  (LucideIcons.zap, 'I feel unmotivated'),
  (LucideIcons.squareCheck, 'Add task review PRs tomorrow 10am'),
];

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key});

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty) return;
    ref.read(assistantProvider.notifier).send(t);
    _input.clear();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: Motion.of(context, Motion.card), curve: Motion.standard);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(assistantProvider);
    ref.listen(assistantProvider.select((s) => (s.messages.length, s.thinking)), (_, _) => _toBottom());
    final busy = s.thinking || s.messages.any((m) => m.streaming);
    final started = s.messages.any((m) => m.role == ChatRole.user);
    final navSpace = Sizes.navHeight + 10 + MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final items = <Widget>[
      for (final m in s.messages) _Bubble(message: m),
      if (s.thinking) const Padding(padding: EdgeInsets.only(top: Space.md), child: _TypingBubble()),
      if (!started)
        Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final sug in _suggestions)
                GlassChip(
                  data: FilterChipData(sug.$2, icon: sug.$1, accent: LifeColors.lilac),
                  selected: false,
                  onTap: () => _send(sug.$2),
                ),
            ],
          ),
        ),
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.fromLTRB(Space.screen, Space.sm, Space.screen, Space.lg),
            children: items.reversed.toList(),
          ),
        ),
        if (started && !busy)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.screen),
              children: [
                for (final sug in _suggestions.take(3))
                  Padding(
                    padding: const EdgeInsets.only(right: Space.sm),
                    child: GlassChip(data: FilterChipData(sug.$2), selected: false, onTap: () => _send(sug.$2)),
                  ),
              ],
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(Space.screen, Space.md, Space.screen, keyboard > 0 ? Space.md : navSpace + Space.md),
          child: AiGlowBorder(
            radius: Radii.pill,
            glow: _focus.hasFocus || busy,
            child: GlassSurface(
              radius: Radii.pill,
              child: Padding(
                padding: const EdgeInsets.only(left: Space.xl, right: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: LifeText.body,
                        decoration: InputDecoration(
                          hintText: 'Ask LifeOS anything…',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintStyle: LifeText.body.copyWith(color: LifeColors.text3),
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: _input,
                      builder: (context, _) {
                        final enabled = _input.text.trim().isNotEmpty && !busy;
                        return Pressable(
                          onTap: enabled ? _send : null,
                          scale: 0.9,
                          semanticLabel: 'Send',
                          child: AnimatedContainer(
                            duration: Motion.of(context, Motion.check),
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: enabled ? Colors.white : LifeColors.glassHigh,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(LucideIcons.arrowUp, size: 20, color: enabled ? LifeColors.onLight : LifeColors.text3),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == ChatRole.user;
    final maxW = MediaQuery.sizeOf(context).width * 0.8;
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: user
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
              decoration: const BoxDecoration(
                color: LifeColors.iris,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Text(message.text, style: LifeText.body.copyWith(color: Colors.white)),
            )
          : GlassCard(
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
              child: Text.rich(
                TextSpan(
                  text: message.text,
                  style: LifeText.body,
                  children: [if (message.streaming) const WidgetSpan(child: _Caret())],
                ),
              ),
            ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Column(
        crossAxisAlignment: user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (user)
            bubble
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Padding(padding: EdgeInsets.only(right: Space.sm, bottom: 4), child: AiMark(size: 24, showSpark: false)),
                Flexible(child: bubble),
              ],
            ),
          if (message.proposalIds.isNotEmpty && !message.streaming)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: Space.xs),
              child: StaggeredEntry(index: 0, child: ProposalsBlock(ids: message.proposalIds)),
            ),
        ],
      ),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(width: 2, height: 16, margin: const EdgeInsets.only(left: 2), color: LifeColors.lilac),
      );
}

/// Three dots pulsing in sequence while the assistant thinks.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Padding(padding: EdgeInsets.only(right: Space.sm), child: AiMark(size: 24, state: AiState.thinking, showSpark: false)),
        GlassCard(
          radius: 20,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 14),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: LifeColors.text.withValues(
                        alpha: 0.3 + 0.7 * (1 - ((_c.value * 3 - i) % 3).clamp(0, 1)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
