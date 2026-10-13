import 'package:civicconnect_ai/core/data/demo_seed.dart';
import 'package:civicconnect_ai/core/utils/geo.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final seed =
      DemoSeed(now: DateTime(2026, 10, 1), center: const GeoPoint(24.86, 67.0));

  test('Seed covers the three mandatory categories with full timelines', () {
    final complaints = seed.complaints();
    final categories = complaints.map((c) => c.category).toSet();
    expect(
        categories,
        containsAll([
          ComplaintCategory.roadDamage,
          ComplaintCategory.streetlight,
          ComplaintCategory.garbage,
        ]));
    final fullTimelines =
        complaints.where((c) => c.timeline.length >= 5).toList();
    expect(fullTimelines.length, greaterThanOrEqualTo(3));
  });

  test('Every seeded job links to an existing complaint', () {
    final ids = seed.complaints().map((c) => c.id).toSet();
    for (final job in seed.jobs()) {
      expect(ids, contains(job.complaintId));
    }
  });
}
