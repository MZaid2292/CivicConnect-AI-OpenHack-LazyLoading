import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend_mode.dart';
import '../../../../core/models/app_role.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../domain/auth_repository.dart';
import '../../domain/login_role_check.dart';
import '../cubit/session_cubit.dart';
import 'role_selection_screen.dart';

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
  final _business = TextEditingController();
  final _description = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;
  bool _busy = false;

  AppRole _role = AppRole.citizen;
  List<MunicipalityOption>? _municipalities;
  String? _municipalityId;
  String? _municipalityError;

  (String, String)? _notice;

  bool get _contractorSignUp =>
      context.isLiveBackend && _signUp && _role == AppRole.contractor;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _business.dispose();
    _description.dispose();
    super.dispose();
  }

  void _selectRole(AppRole role) => setState(() {
        _role = role;
        _notice = null;
        if (role == AppRole.municipalAdmin) _signUp = false;
        if (_contractorSignUp) _loadMunicipalities();
      });

  Future<void> _loadMunicipalities() async {
    if (_municipalities != null) return;
    final session = context.read<SessionCubit>();
    try {
      final list = await session.listMunicipalities();
      if (mounted) {
        setState(() {
          _municipalities = list;
          _municipalityError = list.isEmpty
              ? 'No municipalities are accepting applications yet.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _municipalityError = e.toString());
    }
  }

  Future<void> _submitContractorApplication(SessionCubit session) async {
    final municipality =
        _municipalities!.firstWhere((m) => m.id == _municipalityId);
    final outcome = await session.signUpContractor(
      _name.text,
      _email.text,
      _password.text,
      ContractorApplication(
        businessName: _business.text,
        municipalityId: municipality.id,
        municipalityName: municipality.name,
        description: _description.text,
      ),
    );
    if (!mounted) return;
    setState(() {
      _signUp = false;
      _notice = switch (outcome) {
        ContractorSignUpOutcome.submitted => (
            'Application submitted',
            '${municipality.name} will review your application. Sign in as '
                'Contractor once it is approved.'
          ),
        ContractorSignUpOutcome.confirmEmailFirst => (
            'Confirm your email',
            'We sent a link to ${_email.text.trim()}. After confirming, sign '
                'in here as Contractor to send your application to '
                '${municipality.name}.'
          ),
      };
    });
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
      if (_contractorSignUp) {
        await _submitContractorApplication(session);
      } else if (_signUp) {
        final signedIn =
            await session.signUp(_name.text, _email.text, _password.text);
        if (!signedIn && mounted) {
          showMessage(context,
              'Check your email to confirm your account, then sign in.');
          setState(() => _signUp = false);
        }
      } else {
        await session.signIn(_email.text, _password.text, as: _role);
      }
    } on RoleAccessException catch (e) {
      if (!mounted) return;
      if (e.pendingApproval) {
        setState(() => _notice = ('Application pending', e.message));
      } else {
        showMessage(context, e.message, error: true);
      }
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

  List<Widget> _contractorFields(BuildContext context) => [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: TextFormField(
            key: const Key('businessNameField'),
            controller: _business,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Business / company name',
                prefixIcon: Icon(Icons.business_outlined)),
            validator: (v) =>
                (v ?? '').trim().length < 2 ? 'Enter your business name' : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: DropdownButtonFormField<String>(
            key: const Key('municipalityField'),
            initialValue: _municipalityId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Municipality',
              prefixIcon: const Icon(Icons.location_city_outlined),
              helperText: _municipalities == null && _municipalityError == null
                  ? 'Loading municipalities…'
                  : null,
              errorText: _municipalityError,
            ),
            items: [
              for (final m in _municipalities ?? const <MunicipalityOption>[])
                DropdownMenuItem(
                    value: m.id,
                    child: Text(m.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _municipalityId = v),
            validator: (v) => v == null ? 'Choose your municipality' : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: TextFormField(
            controller: _description,
            minLines: 1,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
                labelText: 'Business description (optional)',
                prefixIcon: Icon(Icons.notes_outlined)),
          ),
        ),
      ];

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
                      if (_notice != null) ...[
                        InfoBanner(
                            icon: Icons.hourglass_top,
                            color: AppColors.amber,
                            title: _notice!.$1,
                            message: _notice!.$2),
                        Space.gapLg,
                      ],
                      if (context.isLiveBackend) ...[
                        _RoleSelector(selected: _role, onSelected: _selectRole),
                        Space.gapMd,
                      ],
                      if (!context.isLiveBackend ||
                          _role != AppRole.municipalAdmin) ...[
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
                          onSelectionChanged: (s) => setState(() {
                            _signUp = s.first;
                            _notice = null;
                            if (_contractorSignUp) _loadMunicipalities();
                          }),
                        ),
                        Space.gapLg,
                      ] else
                        Space.gapSm,
                      AnimatedSize(
                        duration: Motion.of(context, Motion.medium),
                        curve: Motion.curve,
                        child: _signUp
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: Space.md),
                                    child: TextFormField(
                                      controller: _name,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.name],
                                      decoration: const InputDecoration(
                                          labelText: 'Full name',
                                          prefixIcon:
                                              Icon(Icons.person_outline)),
                                      validator: (v) =>
                                          (v ?? '').trim().length < 2
                                              ? 'Enter your name'
                                              : null,
                                    ),
                                  ),
                                  if (_contractorSignUp)
                                    ..._contractorFields(context),
                                ],
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
                            ? (_contractorSignUp
                                ? 'Submit application'
                                : (_signUp ? 'Create account' : 'Sign in'))
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

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.selected, required this.onSelected});
  final AppRole selected;
  final ValueChanged<AppRole> onSelected;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 400 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Semantics(
      label: 'Sign in as',
      container: true,
      child: SegmentedButton<AppRole>(
        showSelectedIcon: false,
        segments: [
          for (final role in AppRole.values)
            ButtonSegment(
              value: role,
              icon: compact ? null : Icon(RoleSelectionScreen.iconFor(role)),
              label: Text(role.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onSelected(s.first),
      ),
    );
  }
}
