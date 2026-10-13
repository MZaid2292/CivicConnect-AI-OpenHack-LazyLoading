import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend_mode.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../cubit/session_cubit.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _features = [
    (
      Icons.add_a_photo_outlined,
      'Report in seconds',
      'Photo, map pin and a short description — we suggest the category.'
    ),
    (
      Icons.merge_type,
      'No duplicate noise',
      'Nearby similar reports are detected so neighbours can add support.'
    ),
    (
      Icons.flag_outlined,
      'Fair prioritisation',
      'Transparent rules rank issues by severity, impact and age.'
    ),
    (
      Icons.timeline,
      'Track every step',
      'From verification to contractor work and inspection, publicly.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
    final hero = _HeroContent(wide: wide);
    final features = _Features(features: _features);

    if (wide) {
      return Scaffold(
        body: Row(children: [
          Expanded(
            flex: 5,
            child: _GradientPanel(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Space.xxxl),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: hero),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Space.xxl),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: features),
                ),
              ),
            ),
          ),
        ]),
      );
    }
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          _GradientPanel(
            bottomRadius: true,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.xl, Space.xl, Space.xl, Space.xxl),
                child: hero,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.all(Space.xl), child: features),
          ),
        ]),
      ),
    );
  }
}

class _GradientPanel extends StatelessWidget {
  const _GradientPanel({required this.child, this.bottomRadius = false});
  final Widget child;
  final bool bottomRadius;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [context.civic.heroStart, context.civic.heroEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: bottomRadius
              ? const BorderRadius.vertical(bottom: Radius.circular(Radii.xl))
              : null,
        ),
        child: child,
      );
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: Radii.brMd),
                child: const Icon(Icons.location_city, color: Colors.white),
              ),
              Space.gapMd,
              Flexible(
                child: Text('CivicConnect AI',
                    style: context.textStyles.titleMedium
                        ?.copyWith(color: Colors.white)),
              ),
            ]),
            SizedBox(height: wide ? Space.xxxl : Space.xl),
            Text('Fix your city,\ntogether.',
                style: (wide
                        ? context.textStyles.displayMedium
                        : context.textStyles.displaySmall)
                    ?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.05)),
            Space.gapMd,
            Text(
              'Citizens report civic issues, the municipality prioritises and '
              'assigns them, and contractors deliver verified fixes.',
              style: context.textStyles.bodyLarge
                  ?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
            ),
            SizedBox(height: wide ? Space.xxl : Space.xl),
            const ExcludeSemantics(child: _HeroIllustration()),
          ],
        ),
      );
}

/// Illustration composed from widgets: a report flowing to "resolved".
class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String title, String sub, Color color) =>
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: Radii.brLg,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            Space.gapMd,
            Flexible(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12)),
                  ]),
            ),
          ]),
        );
    return Wrap(spacing: Space.md, runSpacing: Space.md, children: [
      chip(Icons.add_road, 'Pothole reported', 'Main Market · 2m ago',
          const Color(0xFFF97316)),
      chip(Icons.construction, 'Crew on site', 'Metro Roads & Works',
          const Color(0xFFF59E0B)),
      chip(Icons.verified, 'Resolved', 'Inspection passed ★★★★★',
          const Color(0xFF14B8A6)),
    ]);
  }
}

class _Features extends StatelessWidget {
  const _Features({required this.features});
  final List<(IconData, String, String)> features;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How it works', style: context.textStyles.titleLarge),
          Space.gapLg,
          for (final (icon, title, body) in features)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.lg),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CivicIconBadge(icon: icon, color: AppColors.teal, size: 44),
                Space.gapMd,
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.textStyles.titleSmall),
                        Text(body,
                            style: context.textStyles.bodyMedium
                                ?.copyWith(color: context.civic.muted)),
                      ]),
                ),
              ]),
            ),
          Space.gapSm,
          CivicButton(
            label: 'Get started',
            icon: Icons.arrow_forward,
            expand: true,
            onPressed: () async {
              await context.read<SessionCubit>().completeOnboarding();
              if (context.mounted) context.go(Routes.login);
            },
          ),
          // The role selector exists only in the local preview build; real
          // accounts get their role from the server.
          if (!context.isLiveBackend) ...[
            Space.gapSm,
            CivicButton(
              label: 'Skip to demo role selector',
              variant: CivicButtonVariant.outlined,
              expand: true,
              onPressed: () async {
                await context.read<SessionCubit>().completeOnboarding();
                if (context.mounted) context.go(Routes.role);
              },
            ),
          ],
        ],
      );
}
