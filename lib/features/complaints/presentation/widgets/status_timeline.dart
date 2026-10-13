import 'package:flutter/material.dart';

import '../../../../core/models/app_role.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/complaint.dart';
import '../../domain/complaint_workflow.dart';
import 'badges.dart';

/// Progress along the happy path. Full stepper on wide layouts, compact
/// progress bar + current step on narrow ones or with large text.
class StatusTracker extends StatelessWidget {
  const StatusTracker({super.key, required this.status});
  final ComplaintStatus status;

  int get _reached => switch (status) {
        ComplaintStatus.reworkRequired => 3,
        ComplaintStatus.rejected || ComplaintStatus.duplicate => 0,
        ComplaintStatus.draft => -1,
        _ => ComplaintWorkflow.happyPath.indexOf(status),
      };

  @override
  Widget build(BuildContext context) {
    final steps = ComplaintWorkflow.happyPath;
    final civic = context.civic;
    final active = civic.tone(status.color);
    return Semantics(
      label:
          'Progress: step ${_reached + 1} of ${steps.length}, ${status.label}',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        if (c.maxWidth < 520 || textScale > 1.3) {
          final progress = ((_reached + 1) / steps.length).clamp(0.0, 1.0);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(status.icon, color: active, size: 20),
                  Space.gapSm,
                  Expanded(
                    child: Text(status.label,
                        style: context.textStyles.titleSmall
                            ?.copyWith(color: active)),
                  ),
                  Flexible(
                    child: Text(
                        'Step ${(_reached + 1).clamp(0, steps.length)} of ${steps.length}',
                        textAlign: TextAlign.end,
                        style: context.textStyles.labelMedium
                            ?.copyWith(color: civic.muted)),
                  ),
                ]),
                Space.gapSm,
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: Motion.of(context, Motion.slow),
                  curve: Motion.curve,
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 8,
                    color: active,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Container(
                      height: 3,
                      color: i == 0
                          ? Colors.transparent
                          : (i <= _reached
                              ? civic.tone(steps[i].color)
                              : civic.border),
                    ),
                  ),
                  AnimatedContainer(
                    duration: Motion.of(context, Motion.medium),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= _reached
                          ? civic.tone(steps[i].color)
                          : context.colors.surfaceContainerHigh,
                      border: i == _reached
                          ? Border.all(
                              color: civic.tint(steps[i].color), width: 4)
                          : null,
                    ),
                    child: Icon(i < _reached ? Icons.check : steps[i].icon,
                        size: 15,
                        color: i <= _reached
                            ? context.colors.surface
                            : civic.subtle),
                  ),
                  Expanded(
                    child: Container(
                      height: 3,
                      color: i == steps.length - 1
                          ? Colors.transparent
                          : (i < _reached
                              ? civic.tone(steps[i + 1].color)
                              : civic.border),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(steps[i].label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.labelSmall?.copyWith(
                        color: i <= _reached
                            ? context.colors.onSurface
                            : civic.muted)),
              ]),
            ),
        ]);
      }),
    );
  }
}

/// Vertical, audit-style list of every status change, newest first. The
/// latest event is highlighted as the current state.
class CivicTimeline extends StatelessWidget {
  const CivicTimeline({super.key, required this.events});
  final List<TimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Text('Not submitted yet.',
          style: TextStyle(color: context.civic.muted));
    }
    return Column(children: [
      for (var i = events.length - 1; i >= 0; i--)
        _TimelineRow(
            event: events[i],
            isCurrent: i == events.length - 1,
            isLast: i == 0),
    ]);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow(
      {required this.event, required this.isLast, required this.isCurrent});
  final TimelineEvent event;
  final bool isLast;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final civic = context.civic;
    final hue = civic.tone(event.status.color);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 36,
          child: Column(children: [
            Container(
              width: isCurrent ? 32 : 26,
              height: isCurrent ? 32 : 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent ? hue : civic.tint(event.status.color),
                border: isCurrent
                    ? Border.all(
                        color: civic.tint(event.status.color), width: 4)
                    : null,
              ),
              child: Icon(event.status.icon,
                  size: 14, color: isCurrent ? context.colors.surface : hue),
            ),
            if (!isLast)
              Expanded(
                  child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: civic.border)),
          ]),
        ),
        Space.gapMd,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Space.lg, top: 2),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  spacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(event.status.label,
                        style: context.textStyles.titleSmall
                            ?.copyWith(color: isCurrent ? hue : null)),
                    if (isCurrent)
                      Text('CURRENT',
                          style: context.textStyles.labelSmall
                              ?.copyWith(color: hue)),
                  ]),
              const SizedBox(height: 2),
              Text(
                  '${event.actorName} · ${event.actorRole.label} · ${formatDateTime(event.at)}',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: civic.muted)),
              if (event.note != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: Space.sm),
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                      color: context.colors.surfaceContainer,
                      borderRadius: Radii.brMd),
                  child:
                      Text(event.note!, style: context.textStyles.bodyMedium),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
