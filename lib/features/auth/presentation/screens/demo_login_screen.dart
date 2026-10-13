import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend_mode.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../cubit/session_cubit.dart';

/// Sign-in / sign-up. Live backend: real Supabase Auth (sign-up always
/// creates a citizen account; the role comes from the server). Local preview
/// build: validates input and leads to the demo role selector.
class DemoLoginScreen extends StatefulWidget {
  const DemoLoginScreen({super.key});

  @override
  State<DemoLoginScreen> createState() => _DemoLoginScreenState();
}

class _DemoLoginScreenState extends State<DemoLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    if (!context.isLiveBackend) {
      showMessage(context,
          'Demo mode: no account was ${_signUp ? 'created' : 'checked'}. Choose a role to preview.');
      context.go(Routes.role);
      return;
    }
    final session = context.read<SessionCubit>();
    setState(() => _busy = true);
    try {
      if (_signUp) {
        final signedIn =
            await session.signUp(_name.text, _email.text, _password.text);
        if (!signedIn && mounted) {
          showMessage(context,
              'Check your email to confirm your account, then sign in.');
          setState(() => _signUp = false);
        }
      } else {
        await session.signIn(_email.text, _password.text);
      }
      // On success the router moves to the dashboard.
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final session = context.read<SessionCubit>();
    final email = await promptForText(context,
        title: 'Reset password',
        label: 'Email',
        confirmLabel: 'Send link',
        initial: _email.text.trim(),
        minLength: 5);
    if (email == null || !mounted) return;
    try {
      await session.sendPasswordReset(email);
      if (mounted) {
        showMessage(context,
            'If an account exists for $email, a reset link is on its way.');
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CivicIconBadge(icon: Icons.location_city, size: 56),
                      Space.gapLg,
                      Text(_signUp ? 'Create your account' : 'Welcome back',
                          style: context.textStyles.headlineMedium),
                      Space.gapXs,
                      Text(
                          _signUp
                              ? 'Join your neighbours in fixing the city.'
                              : 'Sign in to report and track civic issues.',
                          style: context.textStyles.bodyLarge
                              ?.copyWith(color: context.civic.muted)),
                      Space.gapLg,
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                              value: false,
                              icon: Icon(Icons.login),
                              label: Text('Sign in')),
                          ButtonSegment(
                              value: true,
                              icon: Icon(Icons.person_add_alt),
                              label: Text('Sign up')),
                        ],
                        selected: {_signUp},
                        onSelectionChanged: (s) =>
                            setState(() => _signUp = s.first),
                      ),
                      Space.gapLg,
                      AnimatedSize(
                        duration: Motion.of(context, Motion.medium),
                        curve: Motion.curve,
                        child: _signUp
                            ? Padding(
                                padding:
                                    const EdgeInsets.only(bottom: Space.md),
                                child: TextFormField(
                                  controller: _name,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.name],
                                  decoration: const InputDecoration(
                                      labelText: 'Full name',
                                      prefixIcon: Icon(Icons.person_outline)),
                                  validator: (v) => (v ?? '').trim().length < 2
                                      ? 'Enter your name'
                                      : null,
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline)),
                        validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch((v ?? '').trim())
                            ? null
                            : 'Enter a valid email address',
                      ),
                      Space.gapMd,
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: 'At least 8 characters',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip:
                                _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v ?? '').length < 8
                            ? 'Use at least 8 characters'
                            : null,
                      ),
                      Space.gapXl,
                      CivicButton(
                        onPressed: _submit,
                        expand: true,
                        loading: _busy,
                        icon: Icons.arrow_forward,
                        label: context.isLiveBackend
                            ? (_signUp ? 'Create account' : 'Sign in')
                            : (_signUp
                                ? 'Continue (demo sign-up)'
                                : 'Continue (demo sign-in)'),
                      ),
                      Space.gapSm,
                      if (!context.isLiveBackend)
                        CivicButton(
                          variant: CivicButtonVariant.text,
                          onPressed: () => context.go(Routes.role),
                          label: 'Skip — choose a demo role',
                        )
                      else if (!_signUp)
                        CivicButton(
                          variant: CivicButtonVariant.text,
                          onPressed: _busy ? null : _forgotPassword,
                          label: 'Forgot password?',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
