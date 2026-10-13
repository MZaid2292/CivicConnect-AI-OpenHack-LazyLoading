import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/models/app_role.dart';
import '../../../../core/models/media_attachment.dart';
import '../../../../core/presentation/watch_cubit.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/civic_map.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../../core/widgets/media_widgets.dart';
import '../../../admin/presentation/widgets/admin_dialogs.dart';
import '../../../auth/presentation/cubit/session_cubit.dart';
import '../../../jobs/domain/job_repositories.dart';
import '../../../jobs/domain/job_service.dart';
import '../../../jobs/domain/work_job.dart';
import '../../domain/complaint.dart';
import '../../domain/complaint_repository.dart';
import '../../domain/services/complaint_service.dart';
import '../cubit/complaint_detail_cubit.dart';
import '../widgets/badges.dart';
import '../widgets/smart_insights.dart';
import '../widgets/status_timeline.dart';

class ComplaintDetailScreen extends StatelessWidget {
  const ComplaintDetailScreen(
      {super.key, required this.complaintId, this.heroTag});
  final String complaintId;

  /// Hero tag of the list thumbnail that opened this page, if any.
  final String? heroTag;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => ComplaintDetailCubit(
          complaintId: complaintId,
          actor: context.read<SessionCubit>().state.actor!,
          complaints: context.read<ComplaintRepository>(),
          jobs: context.read<JobRepository>(),
          complaintService: context.read<ComplaintService>(),
          jobService: context.read<JobService>(),
        ),
        child: _DetailView(heroTag: heroTag),
      );
}

class _DetailView extends StatelessWidget {
  const _DetailView({this.heroTag});
  final String? heroTag;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ComplaintDetailCubit, ComplaintDetailState>(
        listenWhen: (a, b) => a.eventId != b.eventId,
        listener: (context, state) {
          if (state.error != null) {
            showMessage(context, state.error!, error: true);
          } else if (state.message != null) {
            showMessage(context, state.message!);
          }
        },
        builder: (context, state) {
          final c = state.complaint;
          return Scaffold(
            appBar: CivicAppBar(
              title: c?.id ?? 'Report',
              subtitle: c?.category.label,
              fallbackLocation: Routes.home,
            ),
            body: switch (state.status) {
              LoadStatus.loading => const CivicLoadingState(),
              LoadStatus.failure when c == null => CivicErrorState(
                  message: state.error ?? 'Report not found.',
                  onRetry: () => context.pop()),
              _ => _DetailBody(
                  complaint: c!,
                  job: state.job,
                  busy: state.busy,
                  heroTag: heroTag),
            },
          );
        },
      );
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.complaint,
    required this.job,
    required this.busy,
    this.heroTag,
  });
  final Complaint complaint;
  final WorkJob? job;
  final bool busy;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final actor = context.read<ComplaintDetailCubit>().actor;
    final config = context.read<AppConfig>();
    final wide = isWide(context);
    final civic = context.civic;

    final header =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        CivicStatusBadge(c.status),
        CategoryChip(c.category),
        if (c.status.isOpen) PriorityBadge(c.priority),
      ]),
      Space.gapMd,
      Text(c.title, style: context.textStyles.headlineSmall),
      Space.gapSm,
      Row(children: [
        CivicAvatar(name: c.reporterName, radius: 14),
        Space.gapSm,
        Expanded(
          child: Text('${c.reporterName} · ${formatDateTime(c.createdAt)}',
              style:
                  context.textStyles.bodySmall?.copyWith(color: civic.muted)),
        ),
      ]),
    ]);

    final notices = <Widget>[
      if (c.status == ComplaintStatus.rejected && c.rejectionReason != null)
        InfoBanner(
            icon: Icons.block,
            color: AppColors.red,
            title: 'Not accepted',
            message: c.rejectionReason!),
      if (c.status == ComplaintStatus.duplicate && c.duplicateOfId != null)
        CivicCard(
          onTap: () => context.push(Routes.complaint(c.duplicateOfId!)),
          child: Row(children: [
            Icon(Icons.merge_type, color: civic.muted),
            Space.gapMd,
            Expanded(
                child: Text('Merged into ${c.duplicateOfId}. Follow progress '
                    'there — your support was carried over.')),
            const Icon(Icons.chevron_right),
          ]),
        ),
    ];

    final main =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Space.gapLg,
      if (c.photos.isNotEmpty) ...[
        EvidenceGallery(photos: c.photos, heroTag: heroTag),
        Space.gapLg,
      ],
      for (final n in notices) ...[n, Space.gapMd],
      if (c.status.isPublic && c.status != ComplaintStatus.rejected) ...[
        CivicCard(child: StatusTracker(status: c.status)),
        Space.gapLg,
      ],
      _ActionPanel(complaint: c, job: job, actor: actor, busy: busy),
      const CivicSectionHeader('Details', icon: Icons.notes_outlined),
      CivicCard(
        child: Text(c.description, style: context.textStyles.bodyLarge),
      ),
      if (job != null &&
          (job!.beforePhotos.isNotEmpty || job!.afterPhotos.isNotEmpty)) ...[
        const CivicSectionHeader('Repair evidence',
            subtitle: 'Submitted by the contractor for inspection',
            icon: Icons.compare_outlined),
        BeforeAfter(job: job!),
      ],
      if (c.feedback != null && c.reporterId != actor.id) ...[
        const CivicSectionHeader('Public feedback', icon: Icons.star_outline),
        _FeedbackView(feedback: c.feedback!),
      ],
      const CivicSectionHeader('Location', icon: Icons.place_outlined),
      CivicCard(
        padding: EdgeInsets.zero,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (c.location != null)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
              child: AspectRatio(
                aspectRatio: 16 / 7,
                child: CivicMap(
                    config: config,
                    center: c.location!,
                    interactive: false,
                    pins: [MapPin(point: c.location!, color: c.status.color)]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(children: [
              LabeledValue('Address', c.address, icon: Icons.place_outlined),
              LabeledValue('Source', c.locationSource.label,
                  icon: Icons.my_location_outlined),
            ]),
          ),
        ]),
      ),
      _CommentsSection(complaint: c),
    ]);

    final side =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _PriorityCard(complaint: c),
      Space.gapLg,
      _ClassificationCard(complaint: c),
      Space.gapLg,
      CivicCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.timeline, color: context.colors.primary, size: 20),
            Space.gapSm,
            Flexible(
                child: Text('Status history',
                    style: context.textStyles.titleSmall)),
          ]),
          Space.gapLg,
          CivicTimeline(events: c.timeline),
        ]),
      ),
      if (job != null) ...[
        Space.gapLg,
        _WorkOrderCard(job: job!, actor: actor),
      ],
    ]);

    return SingleChildScrollView(
      padding: pagePadding(context, top: Space.sm),
      child: ResponsiveCenter(
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: main),
                Space.gapXl,
                Expanded(flex: 2, child: side),
              ])
            : Column(children: [main, Space.gapLg, side]),
      ),
    );
  }
}

class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({required this.job, required this.actor});
  final WorkJob job;
  final Actor actor;

  @override
  Widget build(BuildContext context) => CivicCard(
        onTap: actor.role == AppRole.citizen
            ? null
            : () => context.push(Routes.job(job.id)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
            spacing: Space.sm,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Work order ${job.id}',
                  style: context.textStyles.titleSmall),
              JobStatusChip(job.status),
            ],
          ),
          Space.gapSm,
          LabeledValue('Department', job.department),
          LabeledValue('Contractor', job.contractorName ?? 'Not yet awarded'),
          if (job.progressLogs.isNotEmpty)
            LabeledValue('Latest update', job.progressLogs.last.note),
        ]),
      );
}

/// Before/after evidence side-by-side (stacks on narrow widths).
class BeforeAfter extends StatelessWidget {
  const BeforeAfter({super.key, required this.job});
  final WorkJob job;

  @override
  Widget build(BuildContext context) {
    Widget column(String label, List<MediaAttachment> photos, Color color) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Pill(
              label: '$label (${photos.length})',
              color: color,
              icon: label == 'After' ? Icons.verified : Icons.history),
          Space.gapSm,
          if (photos.isEmpty)
            Container(
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLow,
                  borderRadius: Radii.brMd,
                  border: Border.all(color: context.civic.border)),
              child: Text('No photos yet',
                  style: TextStyle(color: context.civic.muted)),
            )
          else
            LayoutBuilder(builder: (context, c) {
              final size = (c.maxWidth).clamp(96.0, 180.0);
              return Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                for (final p in photos) PhotoTile(media: p, size: size),
              ]);
            }),
        ]);
    return CivicCard(
      child: LayoutBuilder(builder: (context, c) {
        final before = column('Before', job.beforePhotos, AppColors.orange);
        final after = column('After', job.afterPhotos, AppColors.teal);
        if (c.maxWidth < 360) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                before,
                Space.gapLg,
                after,
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: before),
          Space.gapLg,
          Expanded(child: after),
        ]);
      }),
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context) => SmartInsightCard(
        icon: Icons.flag_outlined,
        title: 'Priority',
        color: AppColors.civicBlue,
        trailing: PriorityBadge(complaint.priority),
        footnote: 'Computed by the municipality\'s published priority rules.',
        child: Column(children: [
          PriorityMeter(
              assessment: complaint.priority,
              rules: context.read<ComplaintService>().rules),
          Space.gapMd,
          PriorityFactors(assessment: complaint.priority),
        ]),
      );
}

class _ClassificationCard extends StatelessWidget {
  const _ClassificationCard({required this.complaint});
  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final cls = complaint.classification;
    return SmartInsightCard(
      icon: Icons.auto_awesome_outlined,
      title: 'Category check',
      method: 'Rule-based NLP',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(cls?.explanation ?? 'No classification stored.'),
        if (cls?.top != null) ...[
          Space.gapSm,
          MatchedTerms(terms: cls!.top!.matchedTerms),
        ],
        if (complaint.categoryOverridden)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: InfoBanner(
                color: AppColors.amber,
                icon: Icons.swap_horiz,
                message: 'Reporter chose "${complaint.category.label}" '
                    'instead of the suggestion.'),
          ),
      ]),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel(
      {required this.complaint,
      required this.job,
      required this.actor,
      required this.busy});
  final Complaint complaint;
  final WorkJob? job;
  final Actor actor;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComplaintDetailCubit>();
    final c = complaint;
    final children = <Widget>[];
    final extras = <Widget>[];
    var title = 'Actions';

    switch (actor.role) {
      case AppRole.citizen:
        title = 'Your involvement';
        final supporting = c.supporterIds.contains(actor.id);
        if (c.status.isOpen && c.reporterId != actor.id) {
          children.add(FilledButton.tonalIcon(
            key: const Key('supportButton'),
            onPressed: busy ? null : cubit.toggleSupport,
            icon: AnimatedSwitcher(
              duration: Motion.of(context, Motion.fast),
              child: Icon(
                  supporting ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                  key: ValueKey(supporting)),
            ),
            label: Text(supporting
                ? 'Supporting (${c.supportCount})'
                : 'I have this issue too (${c.supportCount})'),
          ));
        } else {
          children.add(Pill(
              label: '${c.supportCount} neighbours support this',
              color: AppColors.teal,
              icon: Icons.thumb_up_alt_outlined));
        }
        if (c.status == ComplaintStatus.resolved && c.reporterId == actor.id) {
          extras.add(c.feedback == null
              ? const _RatingForm()
              : _FeedbackView(feedback: c.feedback!));
        }
      case AppRole.municipalAdmin:
        title = 'Review & assignment';
        if (c.status == ComplaintStatus.submitted ||
            c.status == ComplaintStatus.verified) {
          if (c.status == ComplaintStatus.submitted) {
            children.add(FilledButton.icon(
              key: const Key('verifyButton'),
              onPressed: busy
                  ? null
                  : () async {
                      final r = await showVerifyDialog(context, c);
                      if (r != null) await cubit.verify(r.$1, r.$2);
                    },
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Verify'),
            ));
          }
          if (c.status == ComplaintStatus.verified && job == null) {
            children.add(FilledButton.icon(
              key: const Key('assignButton'),
              onPressed: busy
                  ? null
                  : () async {
                      final contractors = await context
                          .read<ContractorRepository>()
                          .listContractors();
                      if (!context.mounted) return;
                      final r = await showAssignDialog(context, c, contractors);
                      if (r != null) await cubit.assignDirectly(r.$1, r.$2);
                    },
              icon: const Icon(Icons.assignment_ind_outlined),
              label: const Text('Assign contractor'),
            ));
            children.add(OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final r = await showTenderDialog(context, c);
                      if (r != null) await cubit.openTender(r.$1, r.$2);
                    },
              icon: const Icon(Icons.gavel_outlined),
              label: const Text('Open tender'),
            ));
          }
          children.add(OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final candidates = await cubit.duplicateCandidates();
                    if (!context.mounted) return;
                    final id = await showDuplicatePicker(context, candidates);
                    if (id != null) await cubit.markDuplicate(id);
                  },
            icon: const Icon(Icons.merge_type),
            label: const Text('Mark duplicate'),
          ));
          children.add(CivicButton(
            variant: CivicButtonVariant.danger,
            icon: Icons.block,
            label: 'Reject',
            onPressed: busy
                ? null
                : () async {
                    final reason = await promptForText(context,
                        title: 'Reject ${c.id}',
                        label: 'Reason shown to the citizen',
                        confirmLabel: 'Reject',
                        minLength: 5);
                    if (reason != null) await cubit.reject(reason);
                  },
          ));
        }
        if (job != null && job!.status == JobStatus.completionSubmitted) {
          children.add(FilledButton.icon(
            onPressed: () => context.push(Routes.inspect(job!.id)),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Inspect work'),
          ));
        }
        if (job != null) {
          children.add(OutlinedButton.icon(
            onPressed: () => context.push(Routes.job(job!.id)),
            icon: const Icon(Icons.work_outline),
            label: Text(job!.status == JobStatus.openForBids
                ? 'Review ${job!.bids.length} bid(s)'
                : 'Open ${job!.id}'),
          ));
        }
      case AppRole.contractor:
        title = 'Work';
        if (job != null && job!.contractorId == actor.id) {
          children.add(FilledButton.icon(
            onPressed: () => context.push(Routes.job(job!.id)),
            icon: const Icon(Icons.construction),
            label: Text('Open my job ${job!.id}'),
          ));
        } else if (job != null && job!.status == JobStatus.openForBids) {
          children.add(FilledButton.icon(
            onPressed: () => context.push(Routes.job(job!.id)),
            icon: const Icon(Icons.gavel_outlined),
            label: const Text('View tender & bid'),
          ));
        }
    }

    if (children.isEmpty && extras.isEmpty) return const SizedBox.shrink();
    return CivicCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: context.textStyles.titleSmall),
        Space.gapMd,
        if (children.isNotEmpty)
          Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children),
        for (final e in extras) ...[Space.gapMd, e],
      ]),
    );
  }
}

class _RatingForm extends StatefulWidget {
  const _RatingForm();
  @override
  State<_RatingForm> createState() => _RatingFormState();
}

class _RatingFormState extends State<_RatingForm> {
  int _rating = 0;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('ratingForm'),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: context.colors.secondaryContainer.withValues(alpha: 0.5),
          borderRadius: Radii.brMd,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How was the fix?', style: context.textStyles.titleSmall),
          Text('Your rating is public and updates the contractor\'s score.',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.civic.muted)),
          Space.gapSm,
          Wrap(children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i star${i == 1 ? '' : 's'}',
                onPressed: () => setState(() => _rating = i),
                icon: AnimatedScale(
                  scale: i <= _rating ? 1.15 : 1,
                  duration: Motion.of(context, Motion.fast),
                  child: Icon(i <= _rating ? Icons.star : Icons.star_border,
                      color: context.civic.tone(AppColors.amber)),
                ),
              ),
          ]),
          TextField(
            controller: _comment,
            maxLines: 2,
            decoration: const InputDecoration(
                hintText: 'Optional comment for the municipality'),
          ),
          Space.gapMd,
          CivicButton(
            onPressed: _rating == 0
                ? null
                : () => context
                    .read<ComplaintDetailCubit>()
                    .rate(_rating, _comment.text),
            label: 'Submit rating',
            icon: Icons.send,
          ),
        ]),
      );
}

class _FeedbackView extends StatelessWidget {
  const _FeedbackView({required this.feedback});
  final CitizenFeedback feedback;

  @override
  Widget build(BuildContext context) => CivicCard(
        child: Row(children: [
          Semantics(
            label: '${feedback.rating} out of 5 stars',
            excludeSemantics: true,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 1; i <= 5; i++)
                Icon(i <= feedback.rating ? Icons.star : Icons.star_border,
                    color: context.civic.tone(AppColors.amber), size: 20),
            ]),
          ),
          Space.gapMd,
          Expanded(
            child: Text(
                feedback.comment.isEmpty
                    ? 'Rated by reporter'
                    : '"${feedback.comment}"',
                style: const TextStyle(fontStyle: FontStyle.italic)),
          ),
        ]),
      );
}

class _CommentsSection extends StatefulWidget {
  const _CommentsSection({required this.complaint});
  final Complaint complaint;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_text.text.trim().isEmpty) return;
    await context.read<ComplaintDetailCubit>().addComment(_text.text);
    if (mounted) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final comments = widget.complaint.comments;
    final civic = context.civic;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CivicSectionHeader('Comments & activity',
          subtitle:
              '${comments.length} comment${comments.length == 1 ? '' : 's'}',
          icon: Icons.forum_outlined),
      if (comments.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Text('No comments yet. Share updates or details.',
              style: TextStyle(color: civic.muted)),
        ),
      for (final cm in comments)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CivicAvatar(name: cm.authorName, radius: 16),
            Space.gapMd,
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  border: Border.all(color: civic.border),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(Radii.md),
                    bottomLeft: Radius.circular(Radii.md),
                    bottomRight: Radius.circular(Radii.md),
                  ),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(cm.authorName,
                                style: context.textStyles.labelLarge),
                            if (cm.authorRole != AppRole.citizen)
                              Pill(
                                  label: cm.authorRole.label,
                                  color: AppColors.civicBlue),
                            Text(timeAgo(cm.at),
                                style: context.textStyles.bodySmall
                                    ?.copyWith(color: civic.muted)),
                          ]),
                      const SizedBox(height: 4),
                      Text(cm.text),
                    ]),
              ),
            ),
          ]),
        ),
      if (widget.complaint.status != ComplaintStatus.draft)
        Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              maxLength: 500,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                  hintText: 'Add a comment', counterText: ''),
              onSubmitted: (_) => _post(),
            ),
          ),
          Space.gapSm,
          IconButton.filled(
              tooltip: 'Post comment',
              onPressed: _post,
              icon: const Icon(Icons.send)),
        ]),
    ]);
  }
}
