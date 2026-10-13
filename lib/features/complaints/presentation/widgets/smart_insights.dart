import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../domain/complaint.dart';
import '../../domain/services/category_classifier.dart';
import '../../domain/services/priority_engine.dart';
import 'badges.dart';

class SmartInsightCard extends StatelessWidget {
  const SmartInsightCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.method = 'Rule-based',
    this.footnote,
    this.trailing,
    this.color,
  });
  final IconData icon;
  final String title;
  final Widget child;
  final String method;
  final String? footnote;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) => CivicCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CivicIconBadge(
                icon: icon, color: color ?? AppColors.teal, size: 36),
            Space.gapMd,
            Expanded(
                flex: 3,
                child: Text(title, style: context.textStyles.titleSmall)),
            Space.gapSm,
            Flexible(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: trailing ?? Pill(label: method, color: AppColors.teal),
              ),
            ),
          ]),
          Space.gapMd,
          child,
          if (footnote != null) ...[
            Space.gapSm,
            Text(footnote!,
                style: context.textStyles.labelSmall?.copyWith(
                    color: context.civic.subtle, fontWeight: FontWeight.w500)),
          ],
        ]),
      );
}

class CategoryMatchBars extends StatelessWidget {
  const CategoryMatchBars(
      {super.key, required this.classification, this.max = 3});
  final ClassificationResult classification;
  final int max;

  @override
  Widget build(BuildContext context) {
    final civic = context.civic;
    return Column(children: [
      for (final s in classification.suggestions.take(max))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Semantics(
            label:
                '${s.category.label}: ${(s.confidence * 100).round()} percent of matched keywords',
            excludeSemantics: true,
            child: Row(children: [
              Icon(s.category.icon, size: 18, color: civic.muted),
              Space.gapSm,
              Expanded(
                flex: 3,
                child: Text(s.category.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Space.gapSm,
              Expanded(
                flex: 2,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: s.confidence),
                  duration: Motion.of(context, Motion.medium),
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${(s.confidence * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: context.textStyles.labelMedium),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class MatchedTerms extends StatelessWidget {
  const MatchedTerms({super.key, required this.terms});
  final List<String> terms;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final t in terms)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Text('"$t"', style: context.textStyles.labelMedium),
          ),
      ]);
}

class PriorityMeter extends StatelessWidget {
  const PriorityMeter(
      {super.key, required this.assessment, required this.rules});
  final PriorityAssessment assessment;
  final PriorityRules rules;

  @override
  Widget build(BuildContext context) {
    final civic = context.civic;
    final scaleMax = [
      assessment.score,
      rules.criticalThreshold + 20,
    ].reduce((a, b) => a > b ? a : b).toDouble();
    final fill = civic.tone(assessment.level.color);
    return Semantics(
      label: 'Priority ${assessment.level.label}, score ${assessment.score}',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, c) {
          double x(num v) => c.maxWidth * (v / scaleMax).clamp(0, 1);
          return SizedBox(
            height: 26,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                top: 8,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(5)),
                ),
              ),
              Positioned(
                left: 0,
                top: 8,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: x(assessment.score)),
                  duration: Motion.of(context, Motion.slow),
                  curve: Motion.curve,
                  builder: (_, w, __) => Container(
                    width: w,
                    height: 10,
                    decoration: BoxDecoration(
                        color: fill, borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              ),
              for (final (level, t) in [
                (PriorityLevel.medium, rules.mediumThreshold),
                (PriorityLevel.high, rules.highThreshold),
                (PriorityLevel.critical, rules.criticalThreshold),
              ])
                Positioned(
                  left: x(t) - 1,
                  top: 4,
                  child: Tooltip(
                    message: '${level.label} from $t',
                    child: Container(
                        width: 2, height: 18, color: civic.tone(level.color)),
                  ),
                ),
            ]),
          );
        }),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('0',
              style:
                  context.textStyles.labelSmall?.copyWith(color: civic.subtle)),
          Space.gapSm,
          Expanded(
            child: Text(
                'M ${rules.mediumThreshold} · H ${rules.highThreshold} · C ${rules.criticalThreshold}',
                textAlign: TextAlign.end,
                style: context.textStyles.labelSmall
                    ?.copyWith(color: civic.subtle)),
          ),
        ]),
      ]),
    );
  }
}

class PriorityFactors extends StatelessWidget {
  const PriorityFactors({super.key, required this.assessment});
  final PriorityAssessment assessment;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final f in assessment.factors)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                  child: Text(f.label, style: context.textStyles.bodyMedium)),
              Text('+${f.points}',
                  style: context.textStyles.labelLarge
                      ?.copyWith(color: context.colors.primary)),
            ]),
          ),
        const Divider(height: Space.lg),
        Row(children: [
          Expanded(
              child: Text('Total score', style: context.textStyles.titleSmall)),
          Text('${assessment.score}', style: context.textStyles.titleSmall),
        ]),
      ]);
}
