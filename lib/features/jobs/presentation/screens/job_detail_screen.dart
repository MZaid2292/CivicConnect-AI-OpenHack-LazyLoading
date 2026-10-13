import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/app_role.dart';
import '../../../../core/models/media_attachment.dart';
import '../../../../core/presentation/watch_cubit.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/media_picker_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../../core/widgets/media_widgets.dart';
import '../../../auth/presentation/cubit/session_cubit.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/complaint_repository.dart';
import '../../../complaints/presentation/screens/complaint_detail_screen.dart';
import '../../../complaints/presentation/widgets/badges.dart';
import '../../domain/job_repositories.dart';
import '../../domain/job_service.dart';
import '../../domain/work_job.dart';
import '../cubit/job_detail_cubit.dart';

/// Creates the job view model for a route.
Widget provideJobCubit(BuildContext context, String jobId, Widget child) =>
    BlocProvider(
      create: (context) => JobDetailCubit(
        jobId: jobId,
        actor: context.read<SessionCubit>().state.actor!,
        jobs: context.read<JobRepository>(),
        complaints: context.read<ComplaintRepository>(),
        service: context.read<JobService>(),
        media: context.read<MediaPickerService>(),
      ),
      child: child,
    );

void jobFeedbackListener(BuildContext context, JobDetailState s) {
  if (s.error != null) showMessage(context, s.error!, error: true);
  if (s.message != null) showMessage(context, s.message!);
}

class JobDetailScreen extends StatelessWidget {
  const JobDetailScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context) => provideJobCubit(
        context,
        jobId,
        BlocConsumer<JobDetailCubit, JobDetailState>(
          listenWhen: (a, b) => a.eventId != b.eventId,
          listener: jobFeedbackListener,
          builder: (context, state) => Scaffold(
            appBar: CivicAppBar(
                title: state.job?.id ?? 'Job',
                subtitle: state.job?.department,
                fallbackLocation: Routes.home),
            body: switch (state.status) {
              LoadStatus.loading => const CivicLoadingState(),
              LoadStatus.failure when state.job == null =>
                CivicErrorState(message: state.error ?? 'Job not found.'),
              _ => _JobBody(state: state),
            },
          ),
        ),
      );
}

class _JobBody extends StatelessWidget {
  const _JobBody({required this.state});
  final JobDetailState state;

  @override
  Widget build(BuildContext context) {
    final job = state.job!;
    final complaint = state.complaint;
    final actor = context.read<JobDetailCubit>().actor;
    final wide = isWide(context);
    final civic = context.civic;

    final header = CivicCard(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CivicIconBadge(icon: job.category.icon, size: 52),
          Space.gapLg,
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                JobStatusChip(job.status),
                CategoryChip(job.category),
              ]),
              Space.gapSm,
              Text(job.title, style: context.textStyles.titleLarge),
            ]),
          ),
        ]),
        Space.gapLg,
        Wrap(spacing: Space.xl, runSpacing: Space.md, children: [
          _Figure(
              label: job.awardedAmount != null ? 'Agreed amount' : 'Budget',
              value: formatAmount(job.awardedAmount ?? job.budgetEstimate),
              emphasis: true),
          _Figure(label: 'Bids', value: '${job.bids.length}'),
          _Figure(label: 'Opened', value: formatDate(job.createdAt)),
          _Figure(label: 'Payment', value: job.paymentStatus.label),
        ]),
      ]),
    );

    final main =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Space.gapLg,
      if (complaint != null)
        CivicCard(
          onTap: () => context.push(Routes.complaint(complaint.id)),
          child: Row(children: [
            Icon(Icons.description_outlined, color: civic.muted),
            Space.gapMd,
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Citizen report ${complaint.id}',
                        style: context.textStyles.labelSmall
                            ?.copyWith(color: civic.muted)),
                    Text(complaint.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.titleSmall),
                    Text(complaint.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: civic.muted)),
                  ]),
            ),
            Space.gapSm,
            Flexible(child: CivicStatusBadge(complaint.status)),
          ]),
        ),
      Space.gapLg,
      _ActionArea(
          job: job, complaint: complaint, actor: actor, busy: state.busy),
      const CivicSectionHeader('Before / after evidence',
          icon: Icons.compare_outlined),
      BeforeAfter(job: job),
      const CivicSectionHeader('Progress log', icon: Icons.update),
      if (job.progressLogs.isEmpty)
        Text('No progress updates yet.', style: TextStyle(color: civic.muted))
      else
        CivicCard(
          child: Column(children: [
            for (var i = job.progressLogs.length - 1; i >= 0; i--)
              _LogRow(log: job.progressLogs[i], last: i == 0),
          ]),
        ),
    ]);

    final side = CivicCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Contract', style: context.textStyles.titleSmall),
        Space.gapSm,
        LabeledValue('Department', job.department),
        LabeledValue('Budget', formatAmount(job.budgetEstimate)),
        LabeledValue('Contractor', job.contractorName ?? 'Not awarded'),
        if (job.awardedAmount != null)
          LabeledValue('Agreed', formatAmount(job.awardedAmount!)),
        LabeledValue('Payment', job.paymentStatus.label),
        LabeledValue('Opened', formatDate(job.createdAt)),
        if (job.completedAt != null)
          LabeledValue('Completed', formatDate(job.completedAt!)),
        if (job.inspectionNote != null)
          LabeledValue('Inspection', job.inspectionNote!),
      ]),
    );

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

class _Figure extends StatelessWidget {
  const _Figure(
      {required this.label, required this.value, this.emphasis = false});
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: context.textStyles.labelSmall
                  ?.copyWith(color: context.civic.muted)),
          Text(value,
              style: (emphasis
                      ? context.textStyles.titleLarge
                      : context.textStyles.titleSmall)
                  ?.copyWith(color: emphasis ? context.colors.primary : null)),
        ],
      );
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log, required this.last});
  final ProgressLog log;
  final bool last;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Column(children: [
            CivicIconBadge(
                icon: Icons.construction, color: AppColors.amber, size: 30),
            if (!last)
              Expanded(child: Container(width: 2, color: context.civic.border)),
          ]),
          Space.gapMd,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: Space.lg),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log.note, style: context.textStyles.bodyMedium),
                    Text('${log.authorName} · ${formatDateTime(log.at)}',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.civic.muted)),
                  ]),
            ),
          ),
        ]),
      );
}

class _ActionArea extends StatelessWidget {
  const _ActionArea(
      {required this.job,
      required this.complaint,
      required this.actor,
      required this.busy});
  final WorkJob job;
  final Complaint? complaint;
  final Actor actor;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobDetailCubit>();
    if (actor.role == AppRole.municipalAdmin) {
      final sorted = [...job.bids]
        ..sort((a, b) => a.amount.compareTo(b.amount));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (job.status == JobStatus.completionSubmitted)
          CivicButton(
            onPressed: () => context.push(Routes.inspect(job.id)),
            icon: Icons.fact_check_outlined,
            label: 'Inspect submitted work',
            expand: true,
          ),
        if (job.bids.isNotEmpty) ...[
          CivicSectionHeader('Bids (${job.bids.length})',
              icon: Icons.gavel_outlined,
              subtitle: job.status == JobStatus.openForBids
                  ? 'Award a bid to assign the contractor'
                  : null),
          for (var i = 0; i < sorted.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: CivicCard(
                child: Row(children: [
                  CivicAvatar(name: sorted[i].contractorName),
                  Space.gapMd,
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            Text(sorted[i].contractorName,
                                style: context.textStyles.titleSmall),
                            if (i == 0 && sorted.length > 1)
                              const Pill(
                                  label: 'Lowest', color: AppColors.teal),
                          ]),
                          Text(
                              '${formatAmount(sorted[i].amount)} · ${sorted[i].days} days',
                              style: context.textStyles.bodyMedium?.copyWith(
                                  color: context.colors.primary,
                                  fontWeight: FontWeight.w600)),
                          if (sorted[i].note.isNotEmpty)
                            Text(sorted[i].note,
                                style: context.textStyles.bodySmall
                                    ?.copyWith(color: context.civic.muted)),
                        ]),
                  ),
                  Space.gapSm,
                  if (job.status == JobStatus.openForBids)
                    FilledButton(
                        onPressed:
                            busy ? null : () => cubit.award(sorted[i].id),
                        child: const Text('Award'))
                  else if (job.contractorId == sorted[i].contractorId)
                    const Pill(label: 'Awarded', color: AppColors.teal),
                ]),
              ),
            ),
        ] else if (job.status == JobStatus.openForBids)
          const InfoBanner(
              icon: Icons.hourglass_top,
              message: 'Waiting for contractor bids.'),
      ]);
    }

    // Contractor
    final mine = job.contractorId == actor.id;
    if (job.status == JobStatus.openForBids) {
      final myBid =
          job.bids.where((b) => b.contractorId == actor.id).firstOrNull;
      return myBid != null
          ? InfoBanner(
              icon: Icons.hourglass_top,
              title: 'Bid submitted',
              message: 'Your bid: ${formatAmount(myBid.amount)} · '
                  '${myBid.days} days. Awaiting municipal decision.')
          : _NextStep(
              title: 'Interested in this job?',
              message: 'Submit a price and timeline. The municipality '
                  'compares bids before awarding.',
              children: [
                CivicButton(
                  key: const Key('bidButton'),
                  onPressed: busy ? null : () => _showBidSheet(context, job),
                  icon: Icons.gavel_outlined,
                  label: 'Submit a bid (mock)',
                ),
              ],
            );
    }
    if (!mine) {
      return const InfoBanner(
          message: 'This job is assigned to another contractor.');
    }
    switch (job.status) {
      case JobStatus.awarded:
        return _NextStep(
          title: 'Ready to start',
          message: 'Add a "before" photo when you arrive, then start work.',
          children: [
            CivicButton(
                key: const Key('startWork'),
                onPressed: busy ? null : cubit.startWork,
                icon: Icons.play_arrow,
                label: 'Start work'),
            const _EvidenceButton(stage: EvidenceStage.before),
          ],
        );
      case JobStatus.inProgress:
        return _NextStep(
          title: 'Work in progress',
          message: 'Log updates as you go. Add at least one "after" photo, '
              'then request inspection.',
          children: [
            OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final note = await promptForText(context,
                            title: 'Log progress',
                            label: 'What was done?',
                            confirmLabel: 'Log',
                            minLength: 3);
                        if (note != null) await cubit.logProgress(note);
                      },
                icon: const Icon(Icons.edit_note),
                label: const Text('Log progress')),
            const _EvidenceButton(stage: EvidenceStage.before),
            const _EvidenceButton(stage: EvidenceStage.after),
            FilledButton.icon(
                key: const Key('requestCompletion'),
                onPressed: busy
                    ? null
                    : () async {
                        final note = await promptForText(context,
                            title: 'Request inspection',
                            label: 'Completion summary',
                            confirmLabel: 'Submit',
                            initial: 'Work completed as per scope.');
                        if (note != null) await cubit.requestCompletion(note);
                      },
                icon: const Icon(Icons.task_alt),
                label: const Text('Request inspection')),
          ],
        );
      case JobStatus.reworkRequested:
        return _NextStep(
          title: 'Rework requested',
          message: job.inspectionNote ?? 'The inspector asked for changes.',
          color: AppColors.orange,
          children: [
            CivicButton(
                onPressed: busy ? null : cubit.startWork,
                icon: Icons.play_arrow,
                label: 'Resume work'),
          ],
        );
      case JobStatus.completionSubmitted:
        return const InfoBanner(
            icon: Icons.hourglass_top,
            title: 'Submitted for inspection',
            message: 'The municipality will inspect the work.');
      case JobStatus.completed:
        return const InfoBanner(
            icon: Icons.verified,
            color: AppColors.teal,
            title: 'Accepted',
            message: 'Payment marked released (simulation).');
      case JobStatus.openForBids || JobStatus.cancelled:
        return const SizedBox.shrink();
    }
  }

  Future<void> _showBidSheet(BuildContext context, WorkJob job) async {
    final cubit = context.read<JobDetailCubit>();
    final amount = TextEditingController();
    final days = TextEditingController(text: '3');
    final note = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
            child: Form(
              key: formKey,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Bid on ${job.id}',
                        style: Theme.of(sheet).textTheme.titleLarge),
                    Text(
                        '${job.title} · budget ${formatAmount(job.budgetEstimate)}',
                        style: TextStyle(color: sheet.civic.muted)),
                    Space.gapLg,
                    TextFormField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Your price (simulated Rs)',
                          prefixIcon: Icon(Icons.payments_outlined)),
                      validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                          ? 'Enter a price'
                          : null,
                    ),
                    Space.gapMd,
                    TextFormField(
                      controller: days,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Days to complete',
                          prefixIcon: Icon(Icons.event_outlined)),
                      validator: (v) {
                        final d = int.tryParse(v ?? '') ?? 0;
                        return d < 1 || d > 90 ? '1–90 days' : null;
                      },
                    ),
                    Space.gapMd,
                    TextFormField(
                      controller: note,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Method / note (optional)'),
                    ),
                    Space.gapLg,
                    CivicButton(
                      expand: true,
                      icon: Icons.send,
                      onPressed: () {
                        if (!formKey.currentState!.validate()) return;
                        Navigator.pop(sheet);
                        cubit.submitBid(int.parse(amount.text),
                            int.parse(days.text), note.text);
                      },
                      label: 'Submit bid',
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Guidance card for the contractor's next action.
class _NextStep extends StatelessWidget {
  const _NextStep({
    required this.title,
    required this.message,
    required this.children,
    this.color,
  });
  final String title;
  final String message;
  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hue = color ?? AppColors.civicBlue;
    return CivicCard(
      borderColor: context.civic.tone(hue).withValues(alpha: 0.4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CivicIconBadge(
              icon: Icons.flag_circle_outlined, color: hue, size: 36),
          Space.gapMd,
          Expanded(
              child: Text(title,
                  style: context.textStyles.titleSmall
                      ?.copyWith(color: context.civic.tone(hue)))),
        ]),
        Space.gapSm,
        Text(message,
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.civic.muted)),
        Space.gapMd,
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: children),
      ]),
    );
  }
}

class _EvidenceButton extends StatelessWidget {
  const _EvidenceButton({required this.stage});
  final EvidenceStage stage;

  @override
  Widget build(BuildContext context) {
    final after = stage == EvidenceStage.after;
    return OutlinedButton.icon(
      key: Key(after ? 'addAfter' : 'addBefore'),
      onPressed: () async {
        final camera = await askCameraOrGallery(context);
        if (camera == null || !context.mounted) return;
        await context.read<JobDetailCubit>().addEvidence(
            stage, camera ? MediaSource.camera : MediaSource.gallery);
      },
      icon:
          Icon(after ? Icons.add_photo_alternate : Icons.add_a_photo_outlined),
      label: Text(after ? 'Add after photo' : 'Add before photo'),
    );
  }
}
