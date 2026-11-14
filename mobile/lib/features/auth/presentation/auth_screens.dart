import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routing/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/stores.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Shared layout: mesh background, AI mark, serif title, one glass card.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.child, this.footer});

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LifeColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground(mode: AmbientMode.home)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.screen),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: AiMark(size: 84)),
                      const SizedBox(height: Space.lg),
                      Text(title, textAlign: TextAlign.center, style: LifeText.display),
                      const SizedBox(height: Space.xs),
                      Text(subtitle, textAlign: TextAlign.center, style: LifeText.body.copyWith(color: LifeColors.text2)),
                      const SizedBox(height: Space.xxl),
                      StaggeredEntry(index: 1, child: GlassCard(child: child)),
                      if (footer != null) ...[const SizedBox(height: Space.xl), footer!],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: Motion.size(context, Motion.card),
        child: message == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: Row(
                  children: [
                    const Icon(LucideIcons.circleAlert, size: 15, color: LifeColors.danger),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(message!, style: LifeText.caption.copyWith(color: LifeColors.danger))),
                  ],
                ),
              ),
      );
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, this.hint = 'Password', this.onSubmitted});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _hidden,
        autofillHints: const [AutofillHints.password],
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(LucideIcons.lockKeyhole, size: 18, color: LifeColors.text3),
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Show password' : 'Hide password',
            icon: Icon(_hidden ? LucideIcons.eye : LucideIcons.eyeOff, size: 18, color: LifeColors.text3),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
      );
}

// ---------------------------------------------------------------- login

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _email.text = auth.email;
    _error = auth.notice;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_emailRe.hasMatch(_email.text.trim())) return setState(() => _error = 'Enter a valid email.');
    if (_password.text.isEmpty) return setState(() => _error = 'Enter your password.');
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await ref.read(authProvider.notifier).signIn(_email.text.trim(), _password.text);
    if (mounted) {
      setState(() {
      _loading = false;
      _error = err;
    });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to your LifeOS',
      footer: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('New here?', style: LifeText.body.copyWith(color: LifeColors.text2)),
              GradientButton(label: 'Create an account', variant: ButtonVariant.ghost, compact: true, onPressed: () => context.go(Routes.register)),
            ],
          ),
          const _SampleDataButton(),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                hintText: 'Email',
                prefixIcon: Icon(LucideIcons.mail, size: 18, color: LifeColors.text3),
              ),
            ),
            const SizedBox(height: Space.md),
            _PasswordField(controller: _password, onSubmitted: (_) => _submit()),
            Align(
              alignment: Alignment.centerRight,
              child: GradientButton(
                label: 'Forgot password?',
                variant: ButtonVariant.ghost,
                compact: true,
                onPressed: () => context.push(Routes.forgot),
              ),
            ),
            _ErrorText(_error),
            const SizedBox(height: Space.md),
            GradientButton(label: 'Sign in', expand: true, loading: _loading, onPressed: _submit),
            if (_loading) const _WakeHint(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- register

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  bool _showInvite = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _invite]) {
      c.dispose();
    }
    super.dispose();
  }

  (double, String, Color) _strength(String pw) {
    var score = 0;
    if (pw.length >= 10) score++;
    if (pw.length >= 14) score++;
    if (RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw)) score++;
    if (RegExp(r'[0-9]').hasMatch(pw)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) score++;
    if (pw.length < 10) return (pw.length / 20, 'At least 10 characters', LifeColors.danger);
    return switch (score) {
      <= 2 => (0.5, 'Okay', LifeColors.amber),
      3 => (0.75, 'Good', LifeColors.sky),
      _ => (1.0, 'Strong', LifeColors.mint),
    };
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'What should we call you?');
    if (!_emailRe.hasMatch(_email.text.trim())) return setState(() => _error = 'Enter a valid email.');
    if (_password.text.length < 10) return setState(() => _error = 'Password must be at least 10 characters.');
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await ref
        .read(authProvider.notifier)
        .register(_name.text.trim(), _email.text.trim(), _password.text, inviteCode: _invite.text.trim());
    if (mounted) {
      setState(() {
      _loading = false;
      _error = err;
    });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Create your OS',
      subtitle: 'One place for your day, your goals and your growth',
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Have an account?', style: LifeText.body.copyWith(color: LifeColors.text2)),
          GradientButton(label: 'Sign in', variant: ButtonVariant.ghost, compact: true, onPressed: () => context.go(Routes.login)),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.givenName],
              decoration: const InputDecoration(hintText: 'Your name', prefixIcon: Icon(LucideIcons.user, size: 18, color: LifeColors.text3)),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(LucideIcons.mail, size: 18, color: LifeColors.text3)),
            ),
            const SizedBox(height: Space.md),
            _PasswordField(controller: _password, hint: 'Password (10+ characters)'),
            ListenableBuilder(
              listenable: _password,
              builder: (context, _) {
                if (_password.text.isEmpty) return const SizedBox(height: Space.sm);
                final (v, label, color) = _strength(_password.text);
                return Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Row(
                    children: [
                      Expanded(child: GlowBar(value: v, color: color, height: 4)),
                      const SizedBox(width: Space.md),
                      Text(label, style: LifeText.caption.copyWith(color: color)),
                    ],
                  ),
                );
              },
            ),
            AnimatedSize(
              duration: Motion.size(context, Motion.card),
              child: _showInvite
                  ? Padding(
                      padding: const EdgeInsets.only(top: Space.md),
                      child: TextField(
                        controller: _invite,
                        decoration: const InputDecoration(hintText: 'Invite code', prefixIcon: Icon(LucideIcons.ticket, size: 18, color: LifeColors.text3)),
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: GradientButton(
                        label: 'Have an invite code?',
                        variant: ButtonVariant.ghost,
                        compact: true,
                        onPressed: () => setState(() => _showInvite = true),
                      ),
                    ),
            ),
            _ErrorText(_error),
            const SizedBox(height: Space.md),
            GradientButton(label: 'Create account', expand: true, loading: _loading, onPressed: _submit),
            if (_loading) const _WakeHint(),
            const SizedBox(height: Space.md),
            Text(
              'Your journal and mood stay private. AI only sees them if you turn that on.',
              textAlign: TextAlign.center,
              style: LifeText.caption,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- forgot

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_emailRe.hasMatch(_email.text.trim())) return setState(() => _error = 'Enter a valid email.');
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await ref.read(authProvider.notifier).forgotPassword(_email.text.trim());
    if (mounted) {
      setState(() {
        _loading = false;
        _sent = err == null;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Reset password',
      subtitle: 'We’ll email you a link',
      footer: Center(
        child: GradientButton(label: 'Back to sign in', variant: ButtonVariant.ghost, compact: true, onPressed: () => context.go(Routes.login)),
      ),
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.card),
        child: _sent
            ? Column(
                key: const ValueKey('sent'),
                children: [
                  const IconChip(icon: LucideIcons.mailCheck, color: LifeColors.mint, size: 52),
                  const SizedBox(height: Space.lg),
                  Text('Check your inbox', style: LifeText.title),
                  const SizedBox(height: Space.xs),
                  Text(
                    'If an account exists for ${_email.text.trim()}, a reset link is on its way. It works for 1 hour.',
                    textAlign: TextAlign.center,
                    style: LifeText.body.copyWith(color: LifeColors.text2),
                  ),
                ],
              )
            : Column(
                key: const ValueKey('form'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(LucideIcons.mail, size: 18, color: LifeColors.text3)),
                  ),
                  _ErrorText(_error),
                  const SizedBox(height: Space.lg),
                  GradientButton(label: 'Send reset link', expand: true, loading: _loading, onPressed: _submit),
                ],
              ),
      ),
    );
  }
}

/// Shown while waiting: the free server sleeps when idle.
class _WakeHint extends StatelessWidget {
  const _WakeHint();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.md),
        child: Text(
          'The server may take up to a minute to wake up the first time.',
          textAlign: TextAlign.center,
          style: LifeText.caption,
        ),
      );
}

/// Try the app without an account. Everything stays on this phone.
class _SampleDataButton extends ConsumerWidget {
  const _SampleDataButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => GradientButton(
        label: 'Explore with sample data',
        icon: LucideIcons.sparkles,
        variant: ButtonVariant.ghost,
        compact: true,
        onPressed: () => ref.read(authProvider.notifier).useSampleData(),
      );
}

/// While the saved session is being restored (a few milliseconds, offline-first).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: LifeColors.bg,
        body: Stack(
          children: [
            Positioned.fill(child: AmbientBackground(mode: AmbientMode.home)),
            Center(child: AiMark(size: 96)),
          ],
        ),
      );
}
