import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/app_role.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../cubit/session_cubit.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  static IconData iconFor(AppRole role) => switch (role) {
        AppRole.citizen => Icons.people_alt_outlined,
        AppRole.municipalAdmin => Icons.account_balance_outlined,
        AppRole.contractor => Icons.engineering_outlined,
      };

  static Color hueFor(AppRole role) => switch (role) {
        AppRole.citizen => AppColors.civicBlue,
        AppRole.municipalAdmin => AppColors.indigo,
        AppRole.contractor => AppColors.teal,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CivicAppBar(
            title: 'Choose a demo role', subtitle: 'Preview each experience'),
        body: SingleChildScrollView(
          padding: pagePadding(context),
          child: ResponsiveCenter(
            maxWidth: 1040,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdaptiveGrid(
                  minTileWidth: 300,
                  spacing: Space.lg,
                  children: [
                    for (final role in AppRole.values) _RoleCard(role: role),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role});
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final hue = RoleSelectionScreen.hueFor(role);
    return Semantics(
      button: true,
      label: 'Continue as ${role.label}',
      excludeSemantics: true,
      child: CivicCard(
        onTap: () => context.read<SessionCubit>().enterDemo(role),
        padding: const EdgeInsets.all(Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CivicIconBadge(
                icon: RoleSelectionScreen.iconFor(role), color: hue, size: 52),
            const Spacer(),
            Icon(Icons.arrow_forward, color: context.civic.subtle),
          ]),
          Space.gapLg,
          Text('Continue as ${role.label}',
              style: context.textStyles.titleMedium),
          Space.gapXs,
          Text(role.tagline,
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: context.civic.muted)),
          Space.gapMd,
          Pill(
              label: 'Demo identity: ${Actor.demoFor(role).name}',
              color: hue,
              icon: Icons.badge_outlined),
        ]),
      ),
    );
  }
}
