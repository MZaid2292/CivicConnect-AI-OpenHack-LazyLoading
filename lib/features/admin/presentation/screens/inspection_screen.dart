import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend_mode.dart';
import '../../../../core/presentation/watch_cubit.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../complaints/presentation/screens/complaint_detail_screen.dart';
import '../../../complaints/presentation/widgets/badges.dart';
import '../../../jobs/domain/work_job.dart';
import '../../../jobs/presentation/cubit/job_detail_cubit.dart';
import '../../../jobs/presentation/screens/job_detail_screen.dart';

class InspectionScreen extends StatelessWidget {
  const InspectionScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context) => provideJobCubit(
        context,
        jobId,
        BlocConsumer<JobDetailCubit, JobDetailState>(
          listenWhen: (a, b) => a.eventId != b.eventId,
          listener: (context, s) {
            jobFeedbackListener(context, s);
            if (s.done && s.error == null && context.canPop()) context.pop();
          },
          builder: (context, state) => Scaffold(
            appBar: CivicAppBar(
                title: 'Inspect ${state.job?.id ?? ''}',
                subtitle: 'Quality check before resolving',
                fallbackLocation: Routes.home),
            body: switch (state.status) {
              LoadStatus.loading => const CivicLoadingState(),
              LoadStatus.failure when state.job == null =>
                CivicErrorState(message: state.error ?? 'Job not found.'),
              _ => _InspectionBody(state: state),
            },
          ),
        ),
      );
}

class _InspectionBody extends StatelessWidget {
  const _InspectionBody({required this.state});
  final JobDetailState state;

  @override
  Widget build(BuildContext context) {
    final job = state.job!;
    final c = state.complaint;
    final cubit = context.read<JobDetailCubit>();
    final ready = job.status == JobStatus.completionSubmitted;
    final civic = context.civic;
    return SingleChildScrollView(
      padding: pagePadding(context, top: Space.sm),
      child: ResponsiveCenter(
        maxWidth: 960,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (c != null)
            CivicCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Text('${c.id} · ${c.title}',
                                  style: context.textStyles.titleMedium)),
                          Space.gapSm,
                          Flexible(child: CivicStatusBadge(c.status)),
                        ]),
                    Space.gapSm,
                    Text(c.description),
                    Space.gapSm,
                    Text('${c.address} · reported ${formatDate(c.createdAt)}',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: civic.muted)),
                  ]),
            ),
          Space.gapLg,
          CivicCard(
            child: Column(children: [
              LabeledValue('Contractor', job.contractorName ?? '—',
                  icon: Icons.engineering_outlined),
              LabeledValue('Last update',
                  job.progressLogs.isEmpty ? '—' : job.progressLogs.last.note,
                  icon: Icons.update),
              LabeledValue('Agreed', formatAmount(job.awardedAmount ?? 0),
                  icon: Icons.payments_outlined),
            ]),
          ),
          const CivicSectionHeader('Evidence comparison',
              icon: Icons.compare_outlined,
              subtitle: 'Check the after photos against the original report'),
          BeforeAfter(job: job),
          Space.gapLg,
          InfoBanner(
              message: context.isLiveBackend
                  ? 'Accepting resolves the report for the citizen. The '
                      'simulated payment is then handled by finance.'
                  : 'Accepting resolves the report for the citizen and '
                      'marks the simulated payment as released.'),
          Space.gapLg,
          if (!ready)
            InfoBanner(
                color: AppColors.amber,
                message: 'Nothing to inspect: job is "${job.status.label}".')
          else
            CivicCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Decision', style: context.textStyles.titleSmall),
                    Space.gapMd,
                    Wrap(spacing: Space.md, runSpacing: Space.md, children: [
                      FilledButton.icon(
                        key: const Key('acceptWork'),
                        style: FilledButton.styleFrom(
                            backgroundColor: context.colors.secondary,
                            foregroundColor: context.colors.onSecondary),
                        onPressed: state.busy
                            ? null
                            : () async {
                                final note = await promptForText(context,
                                    title: 'Accept work',
                                    label: 'Inspection note (optional)',
                                    confirmLabel: 'Accept & resolve',
                                    initial: 'Inspection passed.');
                                if (note != null) {
                                  await cubit.inspect(accept: true, note: note);
                                }
                              },
                        icon: const Icon(Icons.verified),
                        label: const Text('Accept & resolve'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('requestRework'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: civic.tone(AppColors.orange),
                            side: BorderSide(
                                color: civic.tone(AppColors.orange))),
                        onPressed: state.busy
                            ? null
                            : () async {
                                final note = await promptForText(context,
                                    title: 'Request rework',
                                    label: 'What must be fixed?',
                                    confirmLabel: 'Send back',
                                    minLength: 5);
                                if (note != null) {
                                  await cubit.inspect(
                                      accept: false, note: note);
                                }
                              },
                        icon: const Icon(Icons.replay),
                        label: const Text('Request rework'),
                      ),
                    ]),
                  ]),
            ),
        ]),
      ),
    );
  }
}
