import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend_mode.dart';
import '../../../../core/presentation/watch_cubit.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/geo.dart';
import '../../../../core/utils/text_similarity.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/services/duplicate_detector.dart';
import '../../../complaints/presentation/widgets/badges.dart';
import '../../../complaints/presentation/widgets/smart_insights.dart';
import '../cubit/duplicate_review_cubit.dart';

class DuplicateReviewTab extends StatelessWidget {
  const DuplicateReviewTab({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DuplicateReviewCubit, DuplicateReviewState>(
        listenWhen: (a, b) => a.eventId != b.eventId,
        listener: (context, s) {
          if (s.error != null) showMessage(context, s.error!, error: true);
          if (s.message != null) showMessage(context, s.message!);
        },
        builder: (context, state) {
          if (state.status == LoadStatus.loading) {
            return const CivicLoadingState(label: 'Checking for duplicates…');
          }
          if (state.status == LoadStatus.failure) {
            return CivicErrorState(
                message: state.error ?? 'Could not run detection.');
          }
          if (state.items.isEmpty) {
            return ListView(padding: pagePadding(context), children: const [
              ResponsiveCenter(
                maxWidth: 760,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CivicEmptyState(
                          icon: Icons.verified_outlined,
                          title: 'No likely duplicates',
                          message: 'New and verified reports are checked '
                              'automatically by distance, category and '
                              'wording.'),
                      _ScoringMethodCard(),
                    ]),
              ),
            ]);
          }

          final matchCount =
              state.items.fold<int>(0, (n, i) => n + i.matches.length);
          final top = state.items.first.matches.first.score;
          final summary = AdaptiveGrid(minTileWidth: 170, children: [
            CivicStatCard(
                label: 'Reports to review',
                value: '${state.items.length}',
                icon: Icons.content_copy_outlined,
                color: AppColors.orange),
            CivicStatCard(
                label: 'Possible matches',
                value: '$matchCount',
                icon: Icons.compare_arrows,
                color: AppColors.indigo),
            CivicStatCard(
                label: 'Strongest match',
                value: '${(top * 100).round()}%',
                icon: Icons.insights_outlined,
                color: _strength(top).$2),
          ]);
          final cards = [
            for (final item in state.items)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.lg),
                child: _ReviewCard(item: item),
              ),
          ];

          return LayoutBuilder(builder: (context, box) {
            final twoColumn = box.maxWidth >= 1100;
            return ListView(padding: pagePadding(context), children: [
              ResponsiveCenter(
                child: twoColumn
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _intro(context),
                                    Space.gapLg,
                                    ...cards,
                                  ]),
                            ),
                            Space.gapXl,
                            SizedBox(
                              width: 340,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    summary,
                                    Space.gapLg,
                                    const _ScoringMethodCard(),
                                  ]),
                            ),
                          ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            _intro(context),
                            Space.gapLg,
                            summary,
                            Space.gapLg,
                            const _ScoringMethodCard(),
                            Space.gapLg,
                            ...cards,
                          ]),
              ),
            ]);
          });
        },
      );

  Widget _intro(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Review flagged pairs', style: context.textStyles.titleLarge),
        Space.gapXs,
        Text(
            'Compare each new report with the existing one it resembles. '
            'Merge true duplicates so supporters and updates stay in one '
            'place; keep the rest as separate reports.',
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.civic.muted)),
      ]);
}

(String, Color) _strength(double score) => score >= 0.8
    ? ('Strong match', AppColors.red)
    : score >= 0.65
        ? ('Likely match', AppColors.orange)
        : ('Possible match', AppColors.amber);

class _ScoringMethodCard extends StatelessWidget {
  const _ScoringMethodCard();

  @override
  Widget build(BuildContext context) {
    if (context.isLiveBackend) {
      return const SmartInsightCard(
        icon: Icons.rule_outlined,
        title: 'How matches are scored',
        color: AppColors.indigo,
        footnote: 'Nothing is merged automatically.',
        child: Text("Scores come from the server's duplicate check, which "
            'compares location, category and wording when a report is '
            'submitted.'),
      );
    }
    return const SmartInsightCard(
      icon: Icons.rule_outlined,
      title: 'How matches are scored',
      color: AppColors.indigo,
      footnote: 'Without GPS on either report: 35% category + 65% wording, '
          'labelled text-only. Nothing is merged automatically.',
      child: Column(children: [
        _WeightRow(
            icon: Icons.near_me_outlined,
            label: 'Proximity (Haversine, ≤300 m)',
            weight: 0.45),
        _WeightRow(
            icon: Icons.category_outlined,
            label: 'Same category',
            weight: 0.25),
        _WeightRow(
            icon: Icons.short_text,
            label: 'Wording overlap (Jaccard)',
            weight: 0.30),
      ]),
    );
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow(
      {required this.icon, required this.label, required this.weight});
  final IconData icon;
  final String label;
  final double weight;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(children: [
          Icon(icon, size: 18, color: context.civic.muted),
          Space.gapSm,
          Expanded(child: Text(label, style: context.textStyles.bodyMedium)),
          Space.gapSm,
          Text('${(weight * 100).round()}%',
              style: context.textStyles.labelLarge),
        ]),
      );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item});
  final DuplicateReviewItem item;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DuplicateReviewCubit>();
    final c = item.complaint;
    final (label, hue) = _strength(item.matches.first.score);
    final n = item.matches.length;
    return CivicCard(
      borderColor: context.civic.tone(hue).withValues(alpha: 0.45),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CivicIconBadge(icon: Icons.content_copy_outlined, color: hue),
          Space.gapMd,
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c.id} may repeat $n existing report${n == 1 ? '' : 's'}',
                  style: context.textStyles.titleMedium),
              const SizedBox(height: Space.xxs),
              Text('Reported ${timeAgo(c.createdAt)} · ${c.address}',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.civic.muted)),
            ]),
          ),
        ]),
        Space.gapSm,
        Align(
            alignment: Alignment.centerLeft,
            child: Pill(label: label, color: hue, icon: Icons.insights)),
        for (final m in item.matches) ...[
          Space.gapLg,
          _MatchComparison(
            complaint: c,
            match: m,
            onMerge: () => _confirmMerge(context, c, m.complaint, cubit),
          ),
        ],
        const Divider(height: Space.xxl),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CivicButton(
              variant: CivicButtonVariant.outlined,
              icon: Icons.call_split,
              label: 'Not a duplicate',
              onPressed: () => cubit.keepSeparate(c.id),
            ),
            Text('Keeps ${c.id} as its own report.',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.civic.muted)),
          ],
        ),
      ]),
    );
  }

  Future<void> _confirmMerge(BuildContext context, Complaint duplicate,
      Complaint original, DuplicateReviewCubit cubit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.merge_type),
        title: Text('Merge ${duplicate.id}?'),
        content: Text('${duplicate.id} will be closed as a duplicate and '
            'linked to ${original.id}. Merged reports cannot be reopened.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Merge')),
        ],
      ),
    );
    if (ok ?? false) await cubit.merge(duplicate.id, original.id);
  }
}

class _MatchComparison extends StatelessWidget {
  const _MatchComparison(
      {required this.complaint, required this.match, required this.onMerge});
  final Complaint complaint;
  final DuplicateCandidate match;
  final VoidCallback onMerge;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final shared = sharedTokens('${complaint.title} ${complaint.description}',
            '${m.complaint.title} ${m.complaint.description}')
        .take(6)
        .toList();
    final newSide =
        _ReportPanel(label: 'New report', complaint: complaint, accent: true);
    final oldSide =
        _ReportPanel(label: 'Possible original', complaint: m.complaint);
    final dial = _ScoreDial(score: m.score);

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: Radii.brLg,
        border: Border.all(color: context.civic.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, box) {
          final sideBySide = box.maxWidth >= 560 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.5;
          if (sideBySide) {
            return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: newSide),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.md),
                      child: dial),
                  Expanded(child: oldSide),
                ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                newSide,
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Center(child: dial),
                ),
                oldSide,
              ]);
        }),
        Space.gapMd,
        Text('Why it matched',
            style: context.textStyles.labelLarge
                ?.copyWith(color: context.civic.muted)),
        Space.gapXs,
        if (m.distanceMeters != null)
          _SignalBar(
              icon: Icons.near_me_outlined,
              label: 'Distance',
              value: formatDistance(m.distanceMeters!),
              fraction: (1 -
                      m.distanceMeters! /
                          const DuplicateDetector().radiusMeters)
                  .clamp(0, 1),
              color: AppColors.civicBlue)
        else
          const _SignalBar(
              icon: Icons.location_off_outlined,
              label: 'Location',
              value: 'Unavailable · text-only',
              color: AppColors.slate),
        _SignalBar(
            icon: Icons.category_outlined,
            label: 'Category',
            value: m.sameCategory ? 'Same' : 'Different',
            fraction: m.sameCategory ? 1 : 0,
            color: AppColors.teal),
        _SignalBar(
            icon: Icons.short_text,
            label: 'Wording overlap',
            value: '${(m.textSimilarity * 100).round()}%',
            fraction: m.textSimilarity,
            color: AppColors.indigo),
        if (shared.isNotEmpty) ...[
          Space.gapSm,
          Text('Shared words',
              style: context.textStyles.labelMedium
                  ?.copyWith(color: context.civic.muted)),
          Space.gapXs,
          MatchedTerms(terms: shared),
        ],
        Space.gapMd,
        Align(
          alignment: Alignment.centerLeft,
          child: CivicButton(
            icon: Icons.merge_type,
            label: 'Merge into ${m.complaint.id}',
            onPressed: onMerge,
          ),
        ),
      ]),
    );
  }
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel(
      {required this.label, required this.complaint, this.accent = false});
  final String label;
  final Complaint complaint;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    return Semantics(
      button: true,
      label: '$label ${c.id}, open details',
      excludeSemantics: false,
      child: CivicCard(
        flat: true,
        padding: const EdgeInsets.all(Space.md),
        borderColor: accent
            ? context.civic.tone(AppColors.orange).withValues(alpha: 0.5)
            : null,
        onTap: () => context.push(Routes.complaint(c.id)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: context.textStyles.labelSmall?.copyWith(
                  color: accent
                      ? context.civic.tone(AppColors.orange)
                      : context.civic.muted,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700)),
          Space.gapXs,
          Text(c.id, style: context.textStyles.labelLarge),
          Text(c.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.titleSmall),
          Space.gapSm,
          Wrap(spacing: 6, runSpacing: 6, children: [
            CivicStatusBadge(c.status),
            CategoryChip(c.category),
          ]),
          Space.gapSm,
          Text.rich(
            TextSpan(children: [
              WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Icons.place_outlined,
                      size: 14, color: context.civic.muted)),
              TextSpan(text: ' ${c.address}'),
            ]),
            style: context.textStyles.bodySmall
                ?.copyWith(color: context.civic.muted),
          ),
          Text(
              '${timeAgo(c.createdAt)} · ${c.supportCount} '
              'supporter${c.supportCount == 1 ? '' : 's'}',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.civic.muted)),
        ]),
      ),
    );
  }
}

class _ScoreDial extends StatelessWidget {
  const _ScoreDial({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final hue = context.civic.tone(_strength(score).$2);
    final size = MediaQuery.textScalerOf(context).scale(60).clamp(60.0, 104.0);
    final pct = '${(score * 100).round()}%';
    return Semantics(
      label: 'Match score $pct',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(fit: StackFit.expand, children: [
          CircularProgressIndicator(
            value: score.clamp(0, 1),
            strokeWidth: 6,
            strokeCap: StrokeCap.round,
            color: hue,
            backgroundColor: context.colors.surfaceContainerHighest,
          ),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(pct,
                  style: context.textStyles.titleSmall
                      ?.copyWith(color: hue, fontWeight: FontWeight.w800)),
              Text('match',
                  style: context.textStyles.labelSmall
                      ?.copyWith(color: context.civic.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SignalBar extends StatelessWidget {
  const _SignalBar({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.fraction,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final hue = context.civic.tone(color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          spacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, size: 16, color: hue),
            Text(label, style: context.textStyles.bodyMedium),
            Text(value,
                style: context.textStyles.labelLarge?.copyWith(color: hue)),
          ],
        ),
        if (fraction != null) ...[
          const SizedBox(height: Space.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: fraction!.clamp(0, 1),
              minHeight: 6,
              color: hue,
              backgroundColor: context.colors.surfaceContainerHighest,
            ),
          ),
        ],
      ]),
    );
  }
}
