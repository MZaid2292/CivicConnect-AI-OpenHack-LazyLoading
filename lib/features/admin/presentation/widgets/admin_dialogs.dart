import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/civic_widgets.dart';
import '../../../complaints/domain/complaint.dart';
import '../../../complaints/domain/services/duplicate_detector.dart';
import '../../../jobs/domain/contractor.dart';

const departments = [
  'Roads & Infrastructure',
  'Electrical Services',
  'Sanitation',
  'Water & Sewerage',
  'General Services',
];

Future<(String, String)?> showVerifyDialog(
    BuildContext context, Complaint complaint) {
  var department = complaint.category.department;
  final note = TextEditingController();
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Verify ${complaint.id}'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: department,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Route to department'),
              items: [
                for (final d in departments)
                  DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) => setState(() => department = v ?? department),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Note for the citizen (optional)'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, (department, note.text)),
              child: const Text('Verify')),
        ],
      ),
    ),
  );
}

Future<String?> showDuplicatePicker(
    BuildContext context, List<DuplicateCandidate> candidates) {
  final manual = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Merge as duplicate'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (candidates.isEmpty)
            const Text('The detector found no likely originals. Enter an ID '
                'if you know the original report.'),
          for (final c in candidates)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${c.complaint.id} · ${c.complaint.title}'),
              subtitle: Text(
                  '${(c.score * 100).round()}% match · ${c.reasons.join(' · ')}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, c.complaint.id),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: manual,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Or enter original ID (CMP-…)'),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () {
              final id = manual.text.trim().toUpperCase();
              if (id.isNotEmpty) Navigator.pop(context, id);
            },
            child: const Text('Merge')),
      ],
    ),
  );
}

Future<(String, int)?> showTenderDialog(
    BuildContext context, Complaint complaint) {
  final title = TextEditingController(text: complaint.title);
  final budget = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<(String, int)>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Open tender for bids'),
      content: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Work order title'),
            validator: (v) =>
                (v ?? '').trim().length < 5 ? 'Enter a clear title' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: budget,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
                labelText: 'Budget estimate (simulated Rs)'),
            validator: (v) =>
                (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter a budget' : null,
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, (title.text, int.parse(budget.text)));
              }
            },
            child: const Text('Open tender')),
      ],
    ),
  );
}

Future<(String, int)?> showAssignDialog(
    BuildContext context, Complaint complaint, List<Contractor> contractors) {
  final eligible = contractors.where((c) => c.canReceiveWork).toList()
    ..sort((a, b) {
      final aMatch = a.specialties.contains(complaint.category) ? 0 : 1;
      final bMatch = b.specialties.contains(complaint.category) ? 0 : 1;
      return aMatch.compareTo(bMatch);
    });
  String? selected = eligible.isEmpty ? null : eligible.first.id;
  final amount = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<(String, int)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Assign contractor directly'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (eligible.isEmpty)
                const InfoBanner(
                    message: 'No approved contractors. Approve one first.',
                    color: AppColors.amber),
              for (final c in eligible)
                RadioListTile<String>(
                  value: c.id,
                  // ignore: deprecated_member_use
                  groupValue: selected,
                  // ignore: deprecated_member_use
                  onChanged: (v) => setState(() => selected = v),
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name),
                  subtitle: Text([
                    if (c.specialties.contains(complaint.category))
                      'Specialist',
                    c.averageRating == null
                        ? 'No ratings'
                        : '★ ${c.averageRating!.toStringAsFixed(1)}',
                    '${c.completedJobs} jobs',
                  ].join(' · ')),
                ),
              const SizedBox(height: 8),
              TextFormField(
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Agreed amount (simulated Rs)'),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                    ? 'Enter an amount'
                    : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: selected == null
                  ? null
                  : () {
                      if (formKey.currentState!.validate()) {
                        Navigator.pop(
                            context, (selected!, int.parse(amount.text)));
                      }
                    },
              child: const Text('Assign')),
        ],
      ),
    ),
  );
}

String bidSummary(int amount, int days) =>
    '${formatAmount(amount)} · $days days';
