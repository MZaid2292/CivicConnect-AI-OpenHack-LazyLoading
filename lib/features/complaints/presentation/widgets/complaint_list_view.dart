import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/presentation/watch_cubit.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../domain/complaint.dart';
import '../cubit/complaint_list_cubit.dart';
import 'badges.dart';
import 'complaint_card.dart';

/// Status filter presets shown as chips.
class StatusPreset {
  const StatusPreset(this.label, this.statuses);
  final String label;
  final Set<ComplaintStatus> statuses;

  static const citizen = [
    StatusPreset('All', {}),
    StatusPreset('Open', {
      ComplaintStatus.submitted,
      ComplaintStatus.verified,
      ComplaintStatus.assigned,
    }),
    StatusPreset('In progress', {
      ComplaintStatus.inProgress,
      ComplaintStatus.awaitingInspection,
      ComplaintStatus.reworkRequired,
    }),
    StatusPreset('Resolved', {ComplaintStatus.resolved}),
  ];
}

/// Search + status/category filters + sort + results, bound to a
/// [ComplaintListCubit] provided above. Cards on phones (one column, two on
/// tablets); optional table layout on desktop for admin queues.
class ComplaintListView extends StatefulWidget {
  const ComplaintListView({
    super.key,
    this.presets = StatusPreset.citizen,
    this.header,
    this.headerBuilder,
    this.emptyTitle = 'No reports yet',
    this.emptyMessage = 'Reports will appear here as soon as they are filed.',
    this.trailingBuilder,
    this.heroScope,
    this.tableOnWide = false,
    this.resultsLabel = 'reports',
  });

  final List<StatusPreset> presets;
  final Widget? header;
  final Widget Function(BuildContext, ComplaintListState)? headerBuilder;
  final String emptyTitle;
  final String emptyMessage;
  final Widget? Function(Complaint)? trailingBuilder;
  final String? heroScope;
  final bool tableOnWide;
  final String resultsLabel;

  @override
  State<ComplaintListView> createState() => _ComplaintListViewState();
}

class _ComplaintListViewState extends State<ComplaintListView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(BuildContext context, Complaint c) {
    if (c.status == ComplaintStatus.draft) {
      context.push(Routes.editDraft(c.id));
    } else {
      context.push(Routes.complaint(c.id),
          extra: widget.heroScope == null
              ? null
              : complaintHeroTag(widget.heroScope!, c.id));
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ComplaintListCubit, ComplaintListState>(
        builder: (context, state) {
          final cubit = context.read<ComplaintListCubit>();
          final padding = pagePadding(context, top: Space.md);
          final filters = _FilterBar(
            search: _search,
            state: state,
            presets: widget.presets,
          );

          Widget body;
          switch (state.status) {
            case LoadStatus.loading:
              body = const SliverFillRemaining(
                  hasScrollBody: false, child: CivicLoadingState());
            case LoadStatus.failure:
              body = SliverFillRemaining(
                  hasScrollBody: false,
                  child: CivicErrorState(
                      message: state.error ?? 'Could not load reports.',
                      onRetry: cubit.retry));
            case LoadStatus.ready:
              final items = state.visible;
              if (items.isEmpty) {
                body = SliverFillRemaining(
                  hasScrollBody: false,
                  child: CivicEmptyState(
                    icon: state.hasFilters
                        ? Icons.filter_alt_off_outlined
                        : Icons.inbox_outlined,
                    title: state.hasFilters
                        ? 'No matching reports'
                        : widget.emptyTitle,
                    message: state.hasFilters
                        ? 'Try a different search or clear the filters.'
                        : widget.emptyMessage,
                    action: state.hasFilters
                        ? CivicButton(
                            label: 'Clear filters',
                            variant: CivicButtonVariant.outlined,
                            onPressed: () {
                              _search.clear();
                              cubit.clearFilters();
                            })
                        : null,
                  ),
                );
              } else {
                body = SliverLayoutBuilder(builder: (context, c) {
                  final w = c.crossAxisExtent;
                  if (widget.tableOnWide && w >= 960) {
                    return SliverToBoxAdapter(
                      child: _ComplaintTable(
                          items: items, onOpen: (x) => _open(context, x)),
                    );
                  }
                  final columns = w >= 1040 ? 2 : 1;
                  if (columns == 1) {
                    return SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Space.gapMd,
                      itemBuilder: (context, i) => _card(context, items[i]),
                    );
                  }
                  // Two-column masonry-free grid: pair rows.
                  final rows = (items.length / 2).ceil();
                  return SliverList.separated(
                    itemCount: rows,
                    separatorBuilder: (_, __) => Space.gapMd,
                    itemBuilder: (context, r) => Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _card(context, items[r * 2])),
                          Space.gapMd,
                          Expanded(
                              child: r * 2 + 1 < items.length
                                  ? _card(context, items[r * 2 + 1])
                                  : const SizedBox.shrink()),
                        ]),
                  );
                });
              }
          }

          final header =
              widget.headerBuilder?.call(context, state) ?? widget.header;
          return CustomScrollView(slivers: [
            SliverPadding(
              padding: padding.copyWith(bottom: 0),
              sliver: SliverToBoxAdapter(
                child: ResponsiveCenter(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (header != null) header,
                        filters,
                        if (state.status == LoadStatus.ready)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: Space.sm, bottom: Space.md),
                            child: Text(
                                '${state.visible.length} ${widget.resultsLabel}'
                                '${state.hasFilters ? ' match your filters' : ''}',
                                style: context.textStyles.labelMedium
                                    ?.copyWith(color: context.civic.muted)),
                          ),
                      ]),
                ),
              ),
            ),
            SliverPadding(
              padding: padding.copyWith(top: 0, bottom: 112),
              sliver: SliverCrossAxisConstrained(maxWidth: 1180, sliver: body),
            ),
          ]);
        },
      );

  Widget _card(BuildContext context, Complaint c) => CivicComplaintCard(
        complaint: c,
        heroScope: widget.heroScope,
        trailing: widget.trailingBuilder?.call(c),
        onTap: () => _open(context, c),
      );
}

/// Constrains a sliver's cross-axis width and centers it.
class SliverCrossAxisConstrained extends StatelessWidget {
  const SliverCrossAxisConstrained(
      {super.key, required this.maxWidth, required this.sliver});
  final double maxWidth;
  final Widget sliver;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, c) {
          final extra =
              (c.crossAxisExtent - maxWidth).clamp(0.0, double.infinity);
          return SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: extra / 2),
              sliver: sliver);
        },
      );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar(
      {required this.search, required this.state, required this.presets});
  final TextEditingController search;
  final ComplaintListState state;
  final List<StatusPreset> presets;

  bool _sameSet(Set<ComplaintStatus> a, Set<ComplaintStatus> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComplaintListCubit>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: search,
            onChanged: cubit.search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search title, area or ID',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: state.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        search.clear();
                        cubit.search('');
                      }),
            ),
          ),
        ),
        Space.gapSm,
        MenuAnchor(
          menuChildren: [
            for (final s in ComplaintSort.values)
              MenuItemButton(
                leadingIcon: Icon(s == state.sort
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                onPressed: () => cubit.setSort(s),
                child: Text(s.label),
              ),
          ],
          builder: (context, controller, _) => Tooltip(
            message: 'Sort: ${state.sort.label}',
            child: InkWell(
              borderRadius: Radii.brMd,
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                decoration: BoxDecoration(
                  color: context.theme.inputDecorationTheme.fillColor,
                  border: Border.all(color: context.civic.border),
                  borderRadius: Radii.brMd,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.swap_vert, size: 20),
                  if (MediaQuery.sizeOf(context).width >= 420) ...[
                    Space.gapXs,
                    Text(state.sort.label,
                        style: context.textStyles.labelLarge),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
      Space.gapMd,
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: ChoiceChip(
                  label: Text(p.label),
                  selected: _sameSet(state.statuses, p.statuses),
                  showCheckmark: false,
                  onSelected: (_) => cubit.setStatuses(p.statuses),
                ),
              ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(
                  horizontal: Space.xs, vertical: Space.sm),
              color: context.civic.border,
            ),
            Space.gapSm,
            for (final c in ComplaintCategory.values)
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: FilterChip(
                  avatar: Icon(c.icon, size: 16),
                  label: Text(c.shortLabel),
                  selected: state.category == c,
                  showCheckmark: false,
                  onSelected: (on) => cubit.setCategory(on ? c : null),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}

/// Desktop admin table: scan many reports at once; rows open the detail.
class _ComplaintTable extends StatelessWidget {
  const _ComplaintTable({required this.items, required this.onOpen});
  final List<Complaint> items;
  final ValueChanged<Complaint> onOpen;

  @override
  Widget build(BuildContext context) {
    final civic = context.civic;
    TextStyle? head =
        context.textStyles.labelSmall?.copyWith(color: civic.muted);
    Widget row(List<Widget> cells, {VoidCallback? onTap, bool header = false}) {
      const flex = [3, 7, 3, 3, 3, 2, 2];
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.lg, vertical: Space.md),
          decoration: BoxDecoration(
            color: header ? context.colors.surfaceContainerLow : null,
            border: Border(bottom: BorderSide(color: civic.border)),
          ),
          child: Row(children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                flex: flex[i],
                child: Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child:
                      Align(alignment: Alignment.centerLeft, child: cells[i]),
                ),
              ),
          ]),
        ),
      );
    }

    return CivicCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: Radii.brLg,
        child: Column(children: [
          row(header: true, [
            Text('ID', style: head),
            Text('REPORT', style: head),
            Text('STATUS', style: head),
            Text('CATEGORY', style: head),
            Text('PRIORITY', style: head),
            Text('SUPPORT', style: head),
            Text('AGE', style: head),
          ]),
          for (final c in items)
            row(onTap: () => onOpen(c), [
              Text(c.id, style: context.textStyles.labelLarge),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(c.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: civic.muted)),
              ]),
              CivicStatusBadge(c.status),
              CategoryChip(c.category),
              c.status.isOpen
                  ? PriorityBadge(c.priority)
                  : Text('—', style: TextStyle(color: civic.subtle)),
              Text('${c.supportCount}'),
              Text(timeAgo(c.createdAt),
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: civic.muted)),
            ]),
        ]),
      ),
    );
  }
}
