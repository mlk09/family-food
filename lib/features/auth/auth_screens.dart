import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_error.dart';
import '../../core/utils/validators.dart';
import '../../data/session.dart';
import '../../routes/app_router.dart';
import '../../widgets/common.dart';
import 'widgets/brand.dart';

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.icon, required this.children, this.showBack = false});
  final String title, subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showBack)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(onPressed: () => context.go(Routes.login), icon: const Icon(Icons.arrow_back_rounded)),
                      ),
                    const Center(child: BrandLogo()),
                    const SizedBox(height: 16),
                    const Center(child: BrandTitle()),
                    const SizedBox(height: 4),
                    Center(
                      child: Text('Cook smarter with what you have', style: TextStyle(color: context.palette.muted)),
                    ),
                    const SizedBox(height: 26),
                    AppCard(
                      padding: const EdgeInsets.all(22),
                      color: context.palette.card.withValues(alpha: 0.92),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            IconChip(icon: icon, color: AppColors.saffron),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(title, style: context.text.titleLarge),
                                Text(subtitle, style: context.text.bodySmall),
                              ]),
                            ),
                          ]),
                          const SizedBox(height: 22),
                          ...children,
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _FeatureRow(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow();

  @override
  Widget build(BuildContext context) {
    Widget f(String e, String l) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Text(e, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 4),
              Text(l, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
        );
    return Row(children: [
      f('✨', 'AI recipes'),
      const SizedBox(width: 10),
      f('🛒', 'Smart lists'),
      const SizedBox(width: 10),
      f('👨‍👩‍👧', 'Family'),
    ]);
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          const Expanded(child: Divider()),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('OR', style: context.text.bodySmall)),
          const Expanded(child: Divider()),
        ]),
      );
}

class _DemoButton extends ConsumerWidget {
  const _DemoButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => OutlinedButton.icon(
        onPressed: () async {
          await ref.read(sessionProvider.notifier).enterDemo();
          if (context.mounted) context.go(Routes.home);
        },
        icon: const Text('🧪', style: TextStyle(fontSize: 18)),
        label: const Text('Try Demo Mode'),
      );
}

class _GoogleButton extends ConsumerWidget {
  const _GoogleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.googleSignInEnabled || !Env.isSupabaseConfigured) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton.icon(
        onPressed: () async {
          try {
            await ref.read(authServiceProvider).signInWithGoogle();
          } catch (e) {
            if (context.mounted) showSnack(context, friendlyError(e));
          }
        },
        icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.sky)),
        label: const Text('Continue with Google'),
      ),
    );
  }
}

class _NotConfiguredNote extends StatelessWidget {
  const _NotConfiguredNote();

  @override
  Widget build(BuildContext context) {
    if (Env.isSupabaseConfigured) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: SafetyBanner('Cloud accounts are not connected yet. Use Demo Mode to explore — your data stays on this device.'),
    );
  }
}

// ───────────────────────── Login ─────────────────────────

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true, _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).signIn(_email.text, _password.text);
      await ref.read(sessionProvider.notifier).refreshFromAuth();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Log in to your family kitchen',
      icon: Icons.lock_outline_rounded,
      children: [
        const _NotConfiguredNote(),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email', hintText: 'you@example.com', prefixIcon: Icon(Icons.mail_outline_rounded)),
                validator: Validators.email,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: _hide,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _hide ? 'Show password' : 'Hide password',
                    icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
                validator: Validators.password,
              ),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => context.go(Routes.forgot), child: const Text('Forgot password?')),
        ),
        GradientButton(label: 'Log in', icon: Icons.arrow_forward_rounded, loading: _busy, onPressed: _submit),
        const _OrDivider(),
        const _GoogleButton(),
        OutlinedButton.icon(
          onPressed: () => context.go(Routes.signup),
          icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.saffron),
          label: const Text('Create new account'),
        ),
        const SizedBox(height: 10),
        const _DemoButton(),
      ],
    );
  }
}

// ───────────────────────── Sign up ─────────────────────────

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true, _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final needsConfirm = await ref.read(authServiceProvider).signUp(_name.text, _email.text, _password.text);
      if (!mounted) return;
      if (needsConfirm) {
        showSnack(context, '📧 Check your inbox to confirm your email, then log in.');
        context.go(Routes.login);
      } else {
        await ref.read(sessionProvider.notifier).refreshFromAuth();
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Create your account',
      subtitle: 'Free. No credit card needed.',
      icon: Icons.person_add_alt_rounded,
      showBack: true,
      children: [
        const _NotConfiguredNote(),
        Form(
          key: _form,
          child: Column(children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.badge_outlined)),
              validator: Validators.name,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
              validator: Validators.email,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _hide,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'At least 6 characters',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
              validator: Validators.password,
            ),
          ]),
        ),
        const SizedBox(height: 20),
        GradientButton(label: 'Create account', icon: Icons.arrow_forward_rounded, loading: _busy, onPressed: _submit),
        const _OrDivider(),
        const _GoogleButton(),
        const _DemoButton(),
        const SizedBox(height: 8),
        TextButton(onPressed: () => context.go(Routes.login), child: const Text('Already have an account? Log in')),
      ],
    );
  }
}

// ───────────────────────── Forgot password ─────────────────────────

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false, _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Reset password',
      subtitle: "We'll email you a reset link",
      icon: Icons.key_rounded,
      showBack: true,
      children: _sent
          ? [
              const Text('📬', textAlign: TextAlign.center, style: TextStyle(fontSize: 48)),
              const SizedBox(height: 10),
              Text('If an account exists for ${_email.text.trim()}, a reset link is on its way.',
                  textAlign: TextAlign.center, style: context.text.bodyLarge),
              const SizedBox(height: 20),
              GradientButton(label: 'Back to log in', onPressed: () => context.go(Routes.login)),
            ]
          : [
              const _NotConfiguredNote(),
              Form(
                key: _form,
                child: TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  validator: Validators.email,
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(label: 'Send reset link', icon: Icons.send_rounded, loading: _busy, onPressed: _submit),
            ],
    );
  }
}
