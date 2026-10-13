import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend_mode.dart';
import '../../../core/models/app_role.dart';
import '../../../core/presentation/watch_cubit.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/civic_navigation.dart';
import '../../../core/widgets/civic_widgets.dart';
import '../../auth/presentation/cubit/session_cubit.dart';
import '../../notifications/domain/app_notification.dart';

class ShellTab {
  const ShellTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.child,
    this.fab,
    this.title,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget child;
  final Widget? fab;

  /// App bar title when different from the navigation label.
  final String? title;
}

/// Lets nested pages switch shell tabs (e.g. KPI card → queue).
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.goToTab, required super.child});
  final void Function(int index) goToTab;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}

typedef NotificationsCubit = WatchCubit<List<AppNotification>>;

/// Role dashboard shell on top of [CivicResponsiveScaffold].
class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.role, required this.tabs});
  final AppRole role;
  final List<ShellTab> tabs;

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  int _index = 0;

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final tab = widget.tabs[_index];
    final live = context.isLiveBackend;
    final actor =
        context.read<SessionCubit>().state.actor ?? Actor.demoFor(widget.role);
    return ShellScope(
      goToTab: _select,
      child: CivicResponsiveScaffold(
        items: [
          for (final t in widget.tabs)
            CivicNavItem(
                label: t.label, icon: t.icon, selectedIcon: t.selectedIcon),
        ],
        pages: [for (final t in widget.tabs) t.child],
        index: _index,
        onSelect: _select,
        title: tab.title ?? tab.label,
        subtitle: live ? widget.role.label : '${widget.role.label} · demo',
        floatingActionButton: tab.fab,
        actions: [
          const _NotificationBell(),
          _AccountMenu(role: widget.role),
          Space.gapSm,
        ],
        brand: const _Brand(extended: true),
        compactBrand: const _Brand(extended: false),
        sidebarFooter: CivicCard(
          flat: true,
          padding: const EdgeInsets.all(Space.md),
          color: context.colors.surfaceContainerLow,
          child: Row(children: [
            CivicAvatar(name: actor.name),
            Space.gapMd,
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(actor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.labelLarge),
                    Text(live ? widget.role.label : 'Demo identity',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.civic.muted)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        borderRadius: Radii.brMd,
        gradient: LinearGradient(
            colors: [context.civic.heroStart, context.civic.heroEnd]),
      ),
      child: const Icon(Icons.location_city, color: Colors.white),
    );
    if (!extended) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md), child: logo);
    }
    return Row(children: [
      logo,
      Space.gapMd,
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CivicConnect', style: context.textStyles.titleMedium),
          Text('Smart civic reporting',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.civic.muted)),
        ]),
      ),
    ]);
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<NotificationsCubit, DataState<List<AppNotification>>>(
        builder: (context, state) {
          final unread = state.data?.where((n) => !n.read).length ?? 0;
          return IconButton(
            tooltip: 'Notifications ($unread unread)',
            onPressed: () => context.push(Routes.notifications),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          );
        },
      );
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.role});
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final live = context.isLiveBackend;
    final actor =
        context.read<SessionCubit>().state.actor ?? Actor.demoFor(role);
    // MenuAnchor (not PopupMenuButton): its overlay belongs to the anchor, so
    // logging out — which replaces this whole shell — cannot leave a popup
    // route referencing a disposed widget.
    return MenuAnchor(
      alignmentOffset: const Offset(-180, 4),
      menuChildren: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.sm),
          child: Row(children: [
            CivicAvatar(name: actor.name),
            Space.gapMd,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(actor.name, style: context.textStyles.labelLarge),
              Text(live ? role.label : '${role.label} · demo identity',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.civic.muted)),
            ]),
          ]),
        ),
        const Divider(height: 1),
        MenuItemButton(
          leadingIcon: const Icon(Icons.public),
          onPressed: () => context.push(Routes.transparency),
          child: const Text('Public transparency'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => context.read<SessionCubit>().logout(),
          child: Text(live ? 'Log out' : 'Switch role / log out'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Account',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: CivicAvatar(name: actor.name, radius: 16),
      ),
    );
  }
}
