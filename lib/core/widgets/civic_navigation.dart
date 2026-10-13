import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'civic_widgets.dart';

class CivicNavItem {
  const CivicNavItem(
      {required this.label, required this.icon, required this.selectedIcon});
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class CivicBottomNavigation extends StatelessWidget {
  const CivicBottomNavigation(
      {super.key,
      required this.items,
      required this.index,
      required this.onSelect});
  final List<CivicNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return DecoratedBox(
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.civic.border))),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        labelBehavior: narrow
            ? NavigationDestinationLabelBehavior.onlyShowSelected
            : NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final i in items)
            NavigationDestination(
                icon: Icon(i.icon),
                selectedIcon: Icon(i.selectedIcon),
                label: i.label,
                tooltip: i.label),
        ],
      ),
    );
  }
}

class CivicNavigationRail extends StatelessWidget {
  const CivicNavigationRail({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    required this.extended,
    this.header,
    this.footer,
  });
  final List<CivicNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final bool extended;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    if (!extended) {
      return DecoratedBox(
        decoration: BoxDecoration(
            border: Border(right: BorderSide(color: context.civic.border))),
        child: LayoutBuilder(builder: (context, box) {
          final short = box.maxHeight < 520;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: onSelect,
                  labelType: short
                      ? NavigationRailLabelType.selected
                      : NavigationRailLabelType.all,
                  groupAlignment: -0.9,
                  leading: short ? null : header,
                  destinations: [
                    for (final i in items)
                      NavigationRailDestination(
                          icon: short
                              ? Tooltip(message: i.label, child: Icon(i.icon))
                              : Icon(i.icon),
                          selectedIcon: Icon(i.selectedIcon),
                          label: Text(i.label)),
                  ],
                ),
              ),
            ),
          );
        }),
      );
    }
    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(right: BorderSide(color: context.civic.border)),
      ),
      child: SafeArea(
        right: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (header != null)
            Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.lg, Space.xl, Space.lg, Space.lg),
                child: header),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              children: [
                for (var i = 0; i < items.length; i++)
                  _SidebarItem(
                    item: items[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),
          if (footer != null)
            Padding(padding: const EdgeInsets.all(Space.md), child: footer),
        ]),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem(
      {required this.item, required this.selected, required this.onTap});
  final CivicNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: Radii.brMd,
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.md, vertical: Space.md),
              decoration: BoxDecoration(
                color: selected ? colors.primaryContainer : Colors.transparent,
                borderRadius: Radii.brMd,
              ),
              child: Row(children: [
                Icon(selected ? item.selectedIcon : item.icon,
                    color: selected
                        ? colors.onPrimaryContainer
                        : context.civic.muted),
                Space.gapMd,
                Expanded(
                  child: Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.labelLarge?.copyWith(
                          color: selected
                              ? colors.onPrimaryContainer
                              : colors.onSurface)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class CivicResponsiveScaffold extends StatefulWidget {
  const CivicResponsiveScaffold({
    super.key,
    required this.items,
    required this.pages,
    required this.index,
    required this.onSelect,
    required this.title,
    this.subtitle,
    this.actions,
    this.floatingActionButton,
    this.brand,
    this.compactBrand,
    this.sidebarFooter,
  });
  final List<CivicNavItem> items;
  final List<Widget> pages;
  final int index;
  final ValueChanged<int> onSelect;
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? brand;
  final Widget? compactBrand;
  final Widget? sidebarFooter;

  @override
  State<CivicResponsiveScaffold> createState() =>
      _CivicResponsiveScaffoldState();
}

class _CivicResponsiveScaffoldState extends State<CivicResponsiveScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: Motion.medium, value: 1);

  @override
  void didUpdateWidget(covariant CivicResponsiveScaffold old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (Motion.of(context, Motion.medium) == Duration.zero) {
        _fade.value = 1;
      } else {
        _fade.forward(from: 0.2);
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = windowSizeOf(context);
    final body = FadeTransition(
      opacity: CurvedAnimation(parent: _fade, curve: Motion.curve),
      child: IndexedStack(index: widget.index, children: widget.pages),
    );
    final appBar = CivicAppBar(
        title: widget.title,
        subtitle: widget.subtitle,
        actions: widget.actions);

    if (size == WindowSize.compact) {
      return Scaffold(
        appBar: appBar,
        body: body,
        floatingActionButton: widget.floatingActionButton,
        bottomNavigationBar: CivicBottomNavigation(
            items: widget.items,
            index: widget.index,
            onSelect: widget.onSelect),
      );
    }
    final extended = size == WindowSize.large;
    return Scaffold(
      body: Row(children: [
        CivicNavigationRail(
          items: widget.items,
          index: widget.index,
          onSelect: widget.onSelect,
          extended: extended,
          header: extended ? widget.brand : widget.compactBrand,
          footer: extended ? widget.sidebarFooter : null,
        ),
        Expanded(
          child: Scaffold(
            appBar: appBar,
            body: body,
            floatingActionButton: widget.floatingActionButton,
          ),
        ),
      ]),
    );
  }
}
