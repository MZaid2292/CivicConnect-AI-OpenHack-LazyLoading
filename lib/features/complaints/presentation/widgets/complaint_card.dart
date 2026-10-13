import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../../core/widgets/media_widgets.dart';
import '../../domain/complaint.dart';
import 'badges.dart';

String complaintHeroTag(String scope, String id) => 'complaint-$scope-$id';

class CivicComplaintCard extends StatelessWidget {
  const CivicComplaintCard({
    super.key,
    required this.complaint,
    this.onTap,
    this.trailing,
    this.showPriority = true,
    this.heroScope,
  });
  final Complaint complaint;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showPriority;

  final String? heroScope;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final civic = context.civic;
    return Semantics(
      container: true,
      label: '${c.id}, ${c.status.label}',
      child: CivicCard(
        onTap: onTap,
        padding: const EdgeInsets.all(Space.md + 2),
        child: LayoutBuilder(builder: (context, constraints) {
          final thumbSize = constraints.maxWidth < 340 ? 60.0 : 80.0;
          Widget thumb = c.photos.isNotEmpty
              ? PhotoTile(
                  media: c.photos.first,
                  size: thumbSize,
                  showCaption: false,
                  showStorageLabel: false)
              : CivicIconBadge(
                  icon: c.category.icon,
                  color: c.status.color,
                  size: thumbSize);
          if (heroScope != null && c.photos.isNotEmpty) {
            thumb = Hero(tag: complaintHeroTag(heroScope!, c.id), child: thumb);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                thumb,
                Space.gapMd,
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text('${c.id} · ${timeAgo(c.createdAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textStyles.labelSmall
                                    ?.copyWith(color: civic.muted)),
                          ),
                          if (trailing != null) ...[Space.gapSm, trailing!],
                        ]),
                        const SizedBox(height: 2),
                        Text(c.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.textStyles.titleMedium),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.place_outlined,
                              size: 14, color: civic.muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(c.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textStyles.bodySmall
                                    ?.copyWith(color: civic.muted)),
                          ),
                        ]),
                      ]),
                ),
              ]),
              Space.gapMd,
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CivicStatusBadge(c.status),
                  CategoryChip(c.category),
                  if (showPriority && c.status.isOpen)
                    PriorityBadge(c.priority),
                  _Counter(
                      icon: Icons.thumb_up_alt_outlined,
                      value: c.supportCount,
                      label: 'supporters'),
                  if (c.comments.isNotEmpty)
                    _Counter(
                        icon: Icons.chat_bubble_outline,
                        value: c.comments.length,
                        label: 'comments'),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter(
      {required this.icon, required this.value, required this.label});
  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: context.civic.muted),
            const SizedBox(width: 4),
            Text('$value',
                style: context.textStyles.labelMedium
                    ?.copyWith(color: context.civic.muted)),
          ]),
        ),
      );
}
