import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/services/priority_engine.dart';
import '../../../complaints/presentation/widgets/badges.dart';
import '../cubit/priority_rules_cubit.dart';

/// Municipal editor for the configurable priority rules, with a live preview
/// of how open reports would be re-ranked before saving.
class PriorityRulesTab extends StatelessWidget {
  const PriorityRulesTab({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<PriorityRulesCubit, PriorityRulesState>(
        listenWhen: (a, b) => a.eventId != b.eventId,
        listener: (context, s) {
          if (s.error != null) showMessage(context, s.error!, error: true);
          if (s.message != null) showMessage(context, s.message!);
        },
        builder: (context, state) {
          final cubit = context.read<PriorityRulesCubit>();
          final r = state.draft;
          final s = state.saved;
          final preview = cubit.preview();
          final changed = preview.where((p) => p.$2.level != p.$3.level).length;

          final editor = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RuleSection(
                icon: Icons.category_outlined,
                title: 'Issue type base points',
                description: 'Every report starts with points for its '
                    'category.',
                children: [
                  for (final cat in ComplaintCategory.values)
                    _RuleSlider(
                      label: cat.shortLabel,
                      icon: cat.icon,
                      value: r.categoryBase[cat] ?? 0,
                      saved: s.categoryBase[cat] ?? 0,
                      max: 60,
                      onChanged: (v) => cubit.setCategoryBase(cat, v),
                    ),
                ],
              ),
              _RuleSection(
                icon: Icons.groups_outlined,
                title: 'Community & age',
                description: 'Reports gain points as residents support them '
                    'and while they stay open, up to a cap.',
                children: [
                  _RuleSlider(
                      label: 'Per supporter',
                      icon: Icons.thumb_up_alt_outlined,
                      value: r.pointsPerSupporter,
                      saved: s.pointsPerSupporter,
                      max: 10,
                      onChanged: (v) => cubit
                          .update((x) => x.copyWith(pointsPerSupporter: v))),
                  _RuleSlider(
                      label: 'Support cap',
                      icon: Icons.vertical_align_top,
                      value: r.maxSupportPoints,
                      saved: s.maxSupportPoints,
                      max: 60,
                      onChanged: (v) =>
                          cubit.update((x) => x.copyWith(maxSupportPoints: v))),
                  _RuleSlider(
                      label: 'Per day open',
                      icon: Icons.today_outlined,
                      value: r.pointsPerDayOpen,
                      saved: s.pointsPerDayOpen,
                      max: 10,
                      onChanged: (v) =>
                          cubit.update((x) => x.copyWith(pointsPerDayOpen: v))),
                  _RuleSlider(
                      label: 'Age cap',
                      icon: Icons.hourglass_bottom,
                      value: r.maxAgePoints,
                      saved: s.maxAgePoints,
                      max: 60,
                      onChanged: (v) =>
                          cubit.update((x) => x.copyWith(maxAgePoints: v))),
                ],
              ),
              _RuleSection(
                icon: Icons.flag_outlined,
                title: 'Level thresholds',
                description: 'A report reaches a level when its score is at '
                    'or above the threshold.',
                children: [
                  _ThresholdScale(rules: r),
                  Space.gapSm,
                  for (final (level, value, saved, apply) in [
                    (
                      PriorityLevel.medium,
                      r.mediumThreshold,
                      s.mediumThreshold,
                      (PriorityRules x, int v) =>
                          x.copyWith(mediumThreshold: v),
                    ),
                    (
                      PriorityLevel.high,
                      r.highThreshold,
                      s.highThreshold,
                      (PriorityRules x, int v) => x.copyWith(highThreshold: v),
                    ),
                    (
                      PriorityLevel.critical,
                      r.criticalThreshold,
                      s.criticalThreshold,
                      (PriorityRules x, int v) =>
                          x.copyWith(criticalThreshold: v),
                    ),
                  ])
                    _RuleSlider(
                        label: '${level.label} from',
                        icon: Icons.flag,
                        value: value,
                        saved: saved,
                        max: 150,
                        color: level.color,
                        onChanged: (v) => cubit.update((x) => apply(x, v))),
                  if (!r.thresholdsValid) ...[
                    Space.gapSm,
                    const InfoBanner(
                        icon: Icons.error_outline,
                        color: AppColors.red,
                        message: 'Thresholds must increase: '
                            'Medium < High < Critical.'),
                  ],
                ],
              ),
              _RuleSection(
                icon: Icons.priority_high,
                title: 'Severity words',
                description: 'Words in a report\'s title or description that '
                    'add points. Tap a word to change its points.',
                children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e
                        in (r.severityKeywords.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value))))
                      InputChip(
                        label: Text('${e.key} +${e.value}'),
                        onPressed: () => _editKeyword(context, e.key, e.value),
                        onDeleted: () => cubit.removeKeyword(e.key),
                        deleteButtonTooltipMessage: 'Remove ${e.key}',
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Add word'),
                      onPressed: () => _editKeyword(context, '', 10),
                    ),
                  ]),
                ],
              ),
            ],
          );

          final previewPanel = _PreviewPanel(
              preview: preview, changed: changed, dirty: state.dirty);

          return Column(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final wide = box.maxWidth >= 900;
                return SingleChildScrollView(
                  padding: pagePadding(context),
                  child: ResponsiveCenter(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(
                              dirty: state.dirty,
                              openCount: preview.length,
                              onRestoreDefaults: cubit.restoreDefaults),
                          Space.gapLg,
                          if (wide)
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: editor),
                                  Space.gapLg,
                                  Expanded(flex: 2, child: previewPanel),
                                ])
                          else ...[
                            editor,
                            previewPanel,
                          ],
                        ]),
                  ),
                );
              }),
            ),
            _SaveBar(
              dirty: state.dirty,
              valid: r.thresholdsValid,
              saving: state.saving,
              changed: changed,
              onSave: cubit.save,
              onDiscard: cubit.reset,
            ),
          ]);
        },
      );

  Future<void> _editKeyword(
      BuildContext context, String word, int points) async {
    final cubit = context.read<PriorityRulesCubit>();
    final wordCtrl = TextEditingController(text: word);
    var value = points.toDouble();
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(word.isEmpty ? 'Add severity word' : 'Edit "$word"'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: wordCtrl,
                enabled: word.isEmpty,
                decoration: const InputDecoration(
                    labelText: 'Word or phrase', hintText: 'e.g. collapsed'),
              ),
              const SizedBox(height: Space.md),
              Text('Points: ${value.round()}'),
              Slider(
                value: value,
                max: 50,
                divisions: 50,
                label: '${value.round()}',
                onChanged: (v) => setState(() => value = v),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () =>
                    Navigator.pop(context, (wordCtrl.text, value.round())),
                child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (result != null) cubit.setKeyword(result.$1, result.$2);
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.dirty,
      required this.openCount,
      required this.onRestoreDefaults});
  final bool dirty;
  final int openCount;
  final VoidCallback onRestoreDefaults;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Priority scoring', style: context.textStyles.titleLarge),
        Space.gapXs,
        Text(
            'Score = issue type base + severity words + supporters + days '
            'open. Adjust the rules, check the live preview, then save to '
            're-score every report.',
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.civic.muted)),
        Space.gapSm,
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Pill(
                label: dirty ? 'Unsaved draft' : 'Live rules',
                color: dirty ? AppColors.amber : AppColors.teal,
                icon: dirty ? Icons.edit_note : Icons.check_circle_outline),
            Pill(
                label: '$openCount open reports',
                color: AppColors.civicBlue,
                icon: Icons.inbox_outlined),
            TextButton.icon(
                onPressed: onRestoreDefaults,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Restore defaults')),
          ],
        ),
      ]);
}

class _RuleSection extends StatelessWidget {
  const _RuleSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });
  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: CivicCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CivicIconBadge(icon: icon, size: 36),
              Space.gapMd,
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.textStyles.titleMedium),
                      Text(description,
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: context.civic.muted)),
                    ]),
              ),
            ]),
            Space.gapMd,
            ...children,
          ]),
        ),
      );
}

/// Label + value on one line, a full-width slider below — stays readable at
/// large text sizes and narrow widths. A dot marks unsaved changes.
class _RuleSlider extends StatelessWidget {
  const _RuleSlider({
    required this.label,
    required this.value,
    required this.saved,
    required this.max,
    required this.onChanged,
    this.icon,
    this.color,
  });
  final String label;
  final int value;
  final int saved;
  final int max;
  final ValueChanged<int> onChanged;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hue = color == null ? null : context.civic.tone(color!);
    final modified = value != saved;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: hue ?? context.civic.muted),
            Space.gapSm,
          ],
          Expanded(child: Text(label, style: context.textStyles.bodyMedium)),
          if (modified)
            Tooltip(
              message: 'Changed from $saved',
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: Space.sm),
                decoration: BoxDecoration(
                    color: context.civic.tone(AppColors.amber),
                    shape: BoxShape.circle),
              ),
            ),
          Text('$value',
              style: context.textStyles.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700, color: hue)),
        ]),
        Slider(
          value: value.clamp(0, max).toDouble(),
          max: max.toDouble(),
          divisions: max,
          label: '$value',
          activeColor: hue,
          semanticFormatterCallback: (v) => '$label ${v.round()}',
          onChanged: (v) => onChanged(v.round()),
        ),
      ]),
    );
  }
}

/// Coloured bands showing the score ranges each level covers.
class _ThresholdScale extends StatelessWidget {
  const _ThresholdScale({required this.rules});
  final PriorityRules rules;

  @override
  Widget build(BuildContext context) {
    const end = 150;
    final cuts = [
      0,
      rules.mediumThreshold.clamp(0, end),
      rules.highThreshold.clamp(0, end),
      rules.criticalThreshold.clamp(0, end),
      end,
    ];
    final bands = [
      for (var i = 0; i < PriorityLevel.values.length; i++)
        (PriorityLevel.values[i], cuts[i], cuts[i + 1]),
    ];
    return Semantics(
      label: 'Level ranges: ${[
        for (final (l, from, to) in bands)
          if (to > from) '${l.label} $from to ${to - 1}'
      ].join(', ')}',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              for (final (l, from, to) in bands)
                if (to > from)
                  Expanded(
                      flex: to - from,
                      child: ColoredBox(color: context.civic.tone(l.color))),
            ]),
          ),
        ),
        Space.gapSm,
        Wrap(spacing: Space.md, runSpacing: Space.xs, children: [
          for (final (l, from, to) in bands)
            Text.rich(
              TextSpan(children: [
                WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.circle,
                        size: 10, color: context.civic.tone(l.color))),
                TextSpan(
                    text: to > from
                        ? ' ${l.label} $from–${to == end ? '$end+' : to - 1}'
                        : ' ${l.label} —'),
              ]),
              style: context.textStyles.labelMedium
                  ?.copyWith(color: context.civic.muted),
            ),
        ]),
      ]),
    );
  }
}

class _PreviewPanel extends StatefulWidget {
  const _PreviewPanel(
      {required this.preview, required this.changed, required this.dirty});
  final List<(Complaint, PriorityAssessment, PriorityAssessment)> preview;
  final int changed;
  final bool dirty;

  @override
  State<_PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<_PreviewPanel> {
  bool _onlyChanges = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final rows = _onlyChanges && widget.changed > 0
        ? preview.where((p) => p.$2.level != p.$3.level).toList()
        : preview;
    int count(PriorityLevel l, {bool before = false}) =>
        preview.where((p) => (before ? p.$2 : p.$3).level == l).length;

    return CivicCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CivicIconBadge(
              icon: Icons.auto_graph, color: AppColors.indigo, size: 36),
          Space.gapMd,
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Live preview', style: context.textStyles.titleMedium),
              Text(
                  widget.dirty
                      ? '${widget.changed} of ${preview.length} open reports '
                          'change level'
                      : '${preview.length} open reports under current rules',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.civic.muted)),
            ]),
          ),
        ]),
        Space.gapMd,
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final l in PriorityLevel.values.reversed)
            Pill(
              color: l.color,
              label: () {
                final now = count(l);
                final delta = now - count(l, before: true);
                return '${l.label} $now'
                    '${delta == 0 ? '' : ' (${delta > 0 ? '+' : ''}$delta)'}';
              }(),
            ),
        ]),
        if (widget.dirty && widget.changed > 0) ...[
          Space.gapSm,
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Only changes'),
              selected: _onlyChanges,
              onSelected: (v) => setState(() => _onlyChanges = v),
            ),
          ),
        ],
        const Divider(height: Space.xl),
        if (rows.isEmpty)
          Text('No open reports to rank.',
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: context.civic.muted))
        else
          for (final (i, (c, before, after)) in rows.take(10).indexed)
            _PreviewRow(
                rank: preview.indexWhere((p) => p.$1.id == c.id) + 1,
                complaint: c,
                before: before,
                after: after,
                last: i == rows.take(10).length - 1),
        if (rows.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text('Showing the top 10 of ${rows.length}.',
                style: context.textStyles.labelSmall
                    ?.copyWith(color: context.civic.subtle)),
          ),
      ]),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.rank,
    required this.complaint,
    required this.before,
    required this.after,
    required this.last,
  });
  final int rank;
  final Complaint complaint;
  final PriorityAssessment before;
  final PriorityAssessment after;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final moved = before.level != after.level;
    return Container(
      margin: EdgeInsets.only(bottom: last ? 0 : Space.xs),
      padding:
          const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
      decoration: BoxDecoration(
        color: moved
            ? context.civic.tone(AppColors.amber).withValues(alpha: 0.10)
            : null,
        borderRadius: Radii.brSm,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: MediaQuery.textScalerOf(context).scale(24),
          child: Text('$rank',
              style: context.textStyles.labelLarge
                  ?.copyWith(color: context.civic.muted)),
        ),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${complaint.id} · ${complaint.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.bodyMedium),
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (moved) ...[
                  PriorityBadge(before, showScore: false),
                  Icon(Icons.arrow_right_alt,
                      size: 18,
                      color: context.civic.muted,
                      semanticLabel: 'becomes'),
                ],
                PriorityBadge(after),
              ],
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Pinned bar so Save / Discard stay reachable while editing long sections.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.dirty,
    required this.valid,
    required this.saving,
    required this.changed,
    required this.onSave,
    required this.onDiscard,
  });
  final bool dirty;
  final bool valid;
  final bool saving;
  final int changed;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final status = !dirty
        ? 'All changes saved'
        : !valid
            ? 'Fix the thresholds to save'
            : 'Unsaved changes · $changed report${changed == 1 ? '' : 's'} '
                'change level';
    final hue = !dirty
        ? AppColors.teal
        : valid
            ? AppColors.amber
            : AppColors.red;
    return Material(
      color: context.colors.surfaceContainerLow,
      child: Container(
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.civic.border))),
        padding: const EdgeInsets.symmetric(
            horizontal: Space.lg, vertical: Space.sm),
        child: SafeArea(
          top: false,
          child: ResponsiveCenter(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.md,
              runSpacing: Space.xs,
              children: [
                Text.rich(
                  TextSpan(children: [
                    WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(
                            dirty ? Icons.edit_note : Icons.cloud_done_outlined,
                            size: 18,
                            color: context.civic.tone(hue))),
                    TextSpan(text: '  $status'),
                  ]),
                  style: context.textStyles.bodyMedium,
                ),
                Wrap(spacing: Space.sm, runSpacing: Space.xs, children: [
                  OutlinedButton(
                      onPressed: dirty && !saving ? onDiscard : null,
                      child: const Text('Discard changes')),
                  FilledButton.icon(
                    key: const Key('saveRules'),
                    onPressed: dirty && valid && !saving ? onSave : null,
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save & re-score'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
