import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/backend_mode.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/media_picker_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/utils/geo.dart';
import '../../../../core/widgets/civic_map.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../../core/widgets/media_widgets.dart';
import '../../../auth/presentation/cubit/session_cubit.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/services/complaint_service.dart';
import '../../../complaints/domain/services/duplicate_detector.dart';
import '../../../complaints/presentation/widgets/badges.dart';
import '../../../complaints/presentation/widgets/smart_insights.dart';
import '../cubit/create_complaint_cubit.dart';
import 'location_picker_screen.dart';

class CreateComplaintScreen extends StatelessWidget {
  const CreateComplaintScreen({super.key, this.draftId});
  final String? draftId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => CreateComplaintCubit(
          service: context.read<ComplaintService>(),
          location: context.read<LocationService>(),
          media: context.read<MediaPickerService>(),
          actor: context.read<SessionCubit>().state.actor!,
          wardCentre: context.read<AppConfig>().defaultCenter,
          draftId: draftId,
        ),
        child: _CreateComplaintView(isEdit: draftId != null),
      );
}

class _CreateComplaintView extends StatefulWidget {
  const _CreateComplaintView({required this.isEdit});
  final bool isEdit;

  @override
  State<_CreateComplaintView> createState() => _CreateComplaintViewState();
}

class _CreateComplaintViewState extends State<_CreateComplaintView> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _duplicatesKey = GlobalKey();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _address.dispose();
    super.dispose();
  }

  void _listener(BuildContext context, CreateComplaintState state) {
    if (state.error != null) showMessage(context, state.error!, error: true);
    if (!state.loadingDraft && _title.text.isEmpty && state.title.isNotEmpty) {
      // Populate the fields once after a draft finishes loading.
      _title.text = state.title;
      _description.text = state.description;
      _address.text = state.address;
    }
    switch (state.outcome) {
      case CreateOutcome.submitted:
        // A partial photo-upload warning (state.error) is already showing.
        if (state.error == null) {
          showMessage(context, '${state.outcomeId} submitted. Thank you!');
        }
        context.pushReplacement(Routes.complaint(state.outcomeId!));
      case CreateOutcome.supportedExisting:
        showMessage(context,
            'Added your support to ${state.outcomeId} instead of a duplicate.');
        context.pushReplacement(Routes.complaint(state.outcomeId!));
      case CreateOutcome.draftSaved:
        showMessage(context, 'Draft ${state.outcomeId} saved to My reports.');
        context.pop();
      case CreateOutcome.none:
        break;
    }
  }

  Future<void> _submit(CreateComplaintCubit cubit) async {
    final duration = Motion.of(context, Motion.medium);
    final ok = await cubit.submit();
    if (!mounted) return;
    if (!ok && cubit.state.needsDuplicateDecision) {
      final ctx = _duplicatesKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, duration: duration);
      }
      showMessage(context,
          'Similar reports found nearby. Support one or choose "Report anyway".');
    }
  }

  /// Citizens attach evidence by taking a new photo; gallery is not offered.
  Future<void> _pickPhoto(CreateComplaintCubit cubit) async {
    final camera = await askCameraOrGallery(context, allowGallery: false);
    if (camera != true) return;
    await cubit.addPhoto(MediaSource.camera);
  }

  Future<void> _pickOnMap(CreateComplaintCubit cubit) async {
    final config = context.read<AppConfig>();
    final point = await Navigator.of(context).push<GeoPoint>(MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
            config: config, initial: cubit.state.location)));
    if (point != null) cubit.setPinnedLocation(point);
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<CreateComplaintCubit, CreateComplaintState>(
        listenWhen: (a, b) =>
            (b.error != null && a.error != b.error) ||
            a.outcome != b.outcome ||
            (a.loadingDraft && !b.loadingDraft),
        listener: _listener,
        builder: (context, state) {
          final cubit = context.read<CreateComplaintCubit>();
          if (state.loadingDraft) {
            return const Scaffold(
                body: CivicLoadingState(label: 'Opening draft…'));
          }
          final wide = isWide(context);
          final describe = _Section(
            step: 1,
            title: 'Describe the problem',
            subtitle: 'Short title, then the details a crew would need.',
            child: Column(children: [
              CivicTextField(
                fieldKey: const Key('titleField'),
                controller: _title,
                label: 'Title',
                hint: 'e.g. Deep pothole outside the school gate',
                maxLength: 90,
                textInputAction: TextInputAction.next,
                error: state.titleError,
                onChanged: (v) => cubit.updateText(title: v),
              ),
              Space.gapSm,
              CivicTextField(
                fieldKey: const Key('descriptionField'),
                controller: _description,
                label: 'Details',
                hint: 'What do you see? How long has it been like this?',
                helper: 'Tip: mention size, how long it has been there and any '
                    'risk to people (e.g. children, accidents).',
                minLines: 3,
                maxLines: 6,
                maxLength: 600,
                error: state.descriptionError,
                onChanged: (v) => cubit.updateText(description: v),
              ),
            ]),
          );
          final category = _Section(
            step: 2,
            title: 'Category',
            subtitle: 'We suggest one from your words — you decide.',
            child: _CategoryPicker(state: state),
          );
          final location = _Section(
            step: 3,
            title: 'Location',
            subtitle: 'An approximate spot is fine.',
            child: _LocationSection(
              address: _address,
              state: state,
              onPickMap: () => _pickOnMap(cubit),
            ),
          );
          final photos = _Section(
            step: 4,
            title: 'Photos',
            subtitle: 'Recommended — reports with photos are verified faster.',
            child: CivicImagePickerCard(
              photos: state.photos,
              onAdd: () => _pickPhoto(cubit),
              onRemove: cubit.removePhoto,
            ),
          );
          final checks =
              _SmartChecks(state: state, duplicatesKey: _duplicatesKey);

          return Scaffold(
            appBar: CivicAppBar(
              title: widget.isEdit ? 'Edit draft' : 'Report an issue',
              subtitle: context.isLiveBackend
                  ? '${context.read<SessionCubit>().state.profile?.municipalityName ?? 'Your municipality'} · takes about a minute'
                  : 'Ward 4 · takes about a minute',
              fallbackLocation: Routes.home,
              actions: [
                CivicAppBarAction(
                  icon: Icons.save_outlined,
                  label: 'Save draft',
                  onPressed: state.busy ? null : cubit.saveDraft,
                ),
                Space.gapSm,
              ],
            ),
            body: SingleChildScrollView(
              padding: pagePadding(context, top: Space.sm)
                  .copyWith(bottom: Space.xxxl),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ResponsiveCenter(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Expanded(
                              flex: 3,
                              child: Column(children: [
                                describe,
                                category,
                                location,
                                photos,
                              ]),
                            ),
                            Space.gapXl,
                            Expanded(flex: 2, child: checks),
                          ])
                    : Column(children: [
                        describe,
                        category,
                        location,
                        checks,
                        Space.gapLg,
                        photos,
                      ]),
              ),
            ),
            bottomNavigationBar: _SubmitBar(
              state: state,
              onSubmit: () => _submit(cubit),
            ),
          );
        },
      );
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.state, required this.onSubmit});
  final CreateComplaintState state;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.civic.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.lg, Space.md, Space.lg, Space.md),
            child: ResponsiveCenter(
              maxWidth: 640,
              child: CivicButton(
                expand: true,
                loading: state.busy,
                icon: state.needsDuplicateDecision
                    ? Icons.merge_type
                    : Icons.send_rounded,
                onPressed: onSubmit,
                label: state.needsDuplicateDecision
                    ? 'Review similar reports first'
                    : 'Submit report',
              ),
            ),
          ),
        ),
      );
}

/// Numbered form section card.
class _Section extends StatelessWidget {
  const _Section({
    required this.step,
    required this.title,
    required this.child,
    this.subtitle,
  });
  final int step;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.lg),
        child: CivicCard(
          padding: const EdgeInsets.all(Space.lg),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: context.colors.primary, shape: BoxShape.circle),
                child: Text('$step',
                    style: context.textStyles.labelLarge
                        ?.copyWith(color: context.colors.onPrimary)),
              ),
              Space.gapMd,
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.textStyles.titleMedium),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: context.textStyles.bodySmall
                                ?.copyWith(color: context.civic.muted)),
                    ]),
              ),
            ]),
            Space.gapLg,
            child,
          ]),
        ),
      );
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.state});
  final CreateComplaintState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateComplaintCubit>();
    final suggested = state.classification.top?.category;
    final classification = state.classification;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdaptiveGrid(
        minTileWidth: 150,
        spacing: Space.sm,
        children: [
          for (final c in ComplaintCategory.values)
            _CategoryTile(
              category: c,
              selected: state.category == c,
              suggested: suggested == c,
              onTap: () => cubit.selectCategory(c),
            ),
        ],
      ),
      if (state.categoryError != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Text(state.categoryError!,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.colors.error)),
        ),
      Space.gapLg,
      SmartInsightCard(
        icon: Icons.auto_awesome_outlined,
        title: 'Category suggestion',
        method: 'Rule-based NLP',
        footnote: 'Matches keywords in your text. It does not analyse photos. '
            'Percentages are the share of matched keywords, not a probability.',
        child: AnimatedSwitcher(
          duration: Motion.of(context, Motion.medium),
          child: Column(
            key: ValueKey(classification.top?.category),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(classification.explanation,
                  key: const Key('classificationExplanation')),
              if (classification.top != null) ...[
                Space.gapSm,
                MatchedTerms(terms: classification.top!.matchedTerms),
                Space.gapSm,
                CategoryMatchBars(classification: classification),
                if (state.category != classification.top!.category)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: Space.sm,
                        children: [
                          Text('You chose a different category — that\'s fine.',
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: context.civic.muted)),
                          TextButton(
                              onPressed: cubit.acceptSuggestion,
                              child: Text(
                                  'Use ${classification.top!.category.shortLabel}')),
                        ]),
                  ),
              ],
            ],
          ),
        ),
      ),
    ]);
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });
  final ComplaintCategory category;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      label: '${category.label}${suggested ? ', suggested' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.brMd,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
              horizontal: Space.md, vertical: Space.md),
          decoration: BoxDecoration(
            color:
                selected ? colors.primaryContainer : colors.surfaceContainerLow,
            borderRadius: Radii.brMd,
            border: Border.all(
                color: selected ? colors.primary : context.civic.border,
                width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            Icon(category.icon,
                color: selected ? colors.onPrimaryContainer : colors.primary),
            Space.gapSm,
            Expanded(
              child: Text(category.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelLarge?.copyWith(
                      color: selected ? colors.onPrimaryContainer : null)),
            ),
            if (suggested)
              Tooltip(
                message: 'Suggested from your description',
                child: Icon(Icons.auto_awesome,
                    size: 16, color: context.civic.tone(AppColors.teal)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _LocationSection extends StatelessWidget {
  const _LocationSection(
      {required this.address, required this.state, required this.onPickMap});
  final TextEditingController address;
  final CreateComplaintState state;
  final VoidCallback onPickMap;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateComplaintCubit>();
    final config = context.read<AppConfig>();
    final hasLocation = state.location != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CivicTextField(
        fieldKey: const Key('addressField'),
        controller: address,
        label: 'Address or landmark',
        hint: 'e.g. Main Market Road, opposite the pharmacy',
        icon: Icons.place_outlined,
        error: state.addressError,
        onChanged: (v) => cubit.updateText(address: v),
      ),
      Space.gapMd,
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        OutlinedButton.icon(
          onPressed: state.locating ? null : cubit.detectLocation,
          icon: state.locating
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location),
          label: const Text('Use my location'),
        ),
        OutlinedButton.icon(
          onPressed: onPickMap,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Pin on map'),
        ),
        TextButton(
          onPressed: cubit.useWardCentre,
          child: const Text('No GPS? Use ward centre'),
        ),
      ]),
      AnimatedSwitcher(
        duration: Motion.of(context, Motion.medium),
        child: state.locationMessage == null
            ? const SizedBox.shrink()
            : Padding(
                key: ValueKey(state.locationMessage),
                padding: const EdgeInsets.only(top: Space.md),
                child: InfoBanner(
                  message: state.locationMessage!,
                  icon: hasLocation
                      ? Icons.location_on_outlined
                      : Icons.location_off_outlined,
                  color: hasLocation ? AppColors.teal : AppColors.amber,
                ),
              ),
      ),
      if (hasLocation) ...[
        Space.gapMd,
        ClipRRect(
          borderRadius: Radii.brLg,
          child: AspectRatio(
            aspectRatio: 16 / 7,
            child: CivicMap(
              key: ValueKey(state.location),
              config: config,
              center: state.location!,
              interactive: false,
              zoom: 15,
              pins: [MapPin(point: state.location!, color: AppColors.red)],
            ),
          ),
        ),
        Space.gapSm,
        Row(children: [
          Icon(Icons.gps_fixed, size: 14, color: context.civic.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                '${state.locationSource.label} · ${state.location!.shortLabel}',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.civic.muted)),
          ),
        ]),
      ],
    ]);
  }
}

/// Priority preview + duplicate check, both computed by domain services.
class _SmartChecks extends StatelessWidget {
  const _SmartChecks({required this.state, required this.duplicatesKey});
  final CreateComplaintState state;
  final Key duplicatesKey;

  @override
  Widget build(BuildContext context) {
    final rules = context.read<ComplaintService>().rules;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (state.priority != null) ...[
        SmartInsightCard(
          icon: Icons.flag_outlined,
          title: 'Estimated priority',
          color: AppColors.civicBlue,
          trailing: PriorityBadge(state.priority!),
          footnote: 'Municipal rules. Supporters and days open raise it over '
              'time; officials can tune the rules.',
          child: Column(children: [
            PriorityMeter(assessment: state.priority!, rules: rules),
            Space.gapMd,
            PriorityFactors(assessment: state.priority!),
          ]),
        ),
        Space.gapLg,
      ],
      KeyedSubtree(
        key: duplicatesKey,
        child: AnimatedSwitcher(
          duration: Motion.of(context, Motion.medium),
          child: state.duplicates.isEmpty
              ? SmartInsightCard(
                  key: const ValueKey('noDuplicates'),
                  icon: Icons.verified_outlined,
                  title: 'Duplicate check',
                  child: Text(
                      state.location == null
                          ? 'No similar open reports found (text-only check '
                              'until a location is added).'
                          : 'No similar open reports nearby.',
                      style: context.textStyles.bodyMedium),
                )
              : _DuplicateWarning(state: state),
        ),
      ),
    ]);
  }
}

class _DuplicateWarning extends StatelessWidget {
  const _DuplicateWarning({required this.state});
  final CreateComplaintState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CreateComplaintCubit>();
    final warn = context.civic.tone(AppColors.orange);
    return CivicCard(
      key: const Key('duplicateWarning'),
      color: context.civic.tint(AppColors.orange),
      borderColor: warn.withValues(alpha: 0.4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.merge_type, color: warn),
          Space.gapSm,
          Expanded(
            child: Text('Possible duplicate',
                style: context.textStyles.titleSmall?.copyWith(color: warn)),
          ),
          const Pill(label: 'Distance + wording', color: AppColors.orange),
        ]),
        Space.gapSm,
        Text(
            'Supporting an existing report raises its priority faster than '
            'a new one.',
            style: context.textStyles.bodyMedium),
        Space.gapMd,
        for (final d in state.duplicates) _DuplicateTile(candidate: d),
        if (state.duplicatesAcknowledged)
          Row(children: [
            Icon(Icons.check, size: 16, color: context.civic.muted),
            const SizedBox(width: 6),
            Text('You chose to report anyway.',
                style: TextStyle(color: context.civic.muted)),
          ])
        else
          CivicButton(
            key: const Key('reportAnyway'),
            variant: CivicButtonVariant.outlined,
            expand: true,
            onPressed: cubit.acknowledgeDuplicates,
            label: 'This is different — report anyway',
          ),
      ]),
    );
  }
}

class _DuplicateTile extends StatelessWidget {
  const _DuplicateTile({required this.candidate});
  final DuplicateCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final c = candidate.complaint;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: Radii.brMd,
          border: Border.all(color: context.civic.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text('${c.id} · ${c.title}',
                  style: context.textStyles.titleSmall)),
          Space.gapSm,
          Pill(
              label: '${(candidate.score * 100).round()}% match',
              color: AppColors.orange),
        ]),
        Space.gapSm,
        Wrap(spacing: 6, runSpacing: 6, children: [
          CivicStatusBadge(c.status),
          Pill(
              label: '${c.supportCount} supporters',
              color: AppColors.teal,
              icon: Icons.thumb_up_alt_outlined),
        ]),
        Space.gapSm,
        for (final r in candidate.reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.subdirectory_arrow_right,
                  size: 14, color: context.civic.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(r,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.civic.muted)),
              ),
            ]),
          ),
        Space.gapSm,
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          FilledButton.tonalIcon(
            onPressed: () =>
                context.read<CreateComplaintCubit>().supportExisting(c.id),
            icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
            label: const Text('Support this instead'),
          ),
          TextButton(
            onPressed: () => context.push(Routes.complaint(c.id)),
            child: const Text('View'),
          ),
        ]),
      ]),
    );
  }
}
