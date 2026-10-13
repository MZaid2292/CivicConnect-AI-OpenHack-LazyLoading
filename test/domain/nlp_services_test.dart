import 'package:civicconnect_ai/core/utils/geo.dart';
import 'package:civicconnect_ai/core/utils/text_similarity.dart';
import 'package:civicconnect_ai/features/complaints/domain/complaint.dart';
import 'package:civicconnect_ai/features/complaints/domain/services/category_classifier.dart';
import 'package:civicconnect_ai/features/complaints/domain/services/duplicate_detector.dart';
import 'package:civicconnect_ai/features/complaints/domain/services/priority_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Complaint _complaint(
        String id, String title, ComplaintCategory category, GeoPoint? location,
        {ComplaintStatus status = ComplaintStatus.submitted}) =>
    Complaint(
      id: id,
      title: title,
      description: title,
      category: category,
      status: status,
      address: 'x',
      reporterId: 'r',
      reporterName: 'R',
      createdAt: DateTime(2026, 1, 1),
      location: location,
      priority: const PriorityAssessment(
          score: 0, level: PriorityLevel.low, factors: []),
    );

void main() {
  group('KeywordCategoryClassifier', () {
    const classifier = KeywordCategoryClassifier();

    test('classifies the three mandatory categories', () {
      expect(classifier.classify('Huge pothole on main road', '').top!.category,
          ComplaintCategory.roadDamage);
      expect(
          classifier
              .classify('Street light not working', 'Whole lane is dark')
              .top!
              .category,
          ComplaintCategory.streetlight);
      expect(
          classifier
              .classify('Garbage not collected', 'Trash bins overflowing')
              .top!
              .category,
          ComplaintCategory.garbage);
    });

    test('explains matched phrases and handles plurals', () {
      final result = classifier.classify('Two potholes', 'deep potholes');
      expect(result.top!.matchedTerms, contains('pothole'));
      expect(result.explanation, contains('"pothole"'));
    });

    test('returns no suggestion when nothing matches', () {
      final result = classifier.classify('Hello there', 'Nothing relevant');
      expect(result.hasSuggestion, isFalse);
    });
  });

  group('Text similarity', () {
    test('Jaccard of identical text is 1 and disjoint is 0', () {
      expect(jaccardSimilarity('broken streetlight', 'broken streetlight'), 1);
      expect(jaccardSimilarity('garbage pile', 'water leak'), 0);
    });
  });

  group('DuplicateDetector', () {
    const detector = DuplicateDetector();
    const origin = GeoPoint(24.86, 67.0);

    test('flags nearby same-category similar reports', () {
      final existing = [
        _complaint('A', 'Potholes on Canal Road service lane',
            ComplaintCategory.roadDamage, origin),
        _complaint('B', 'Potholes on Canal Road service lane',
            ComplaintCategory.roadDamage, origin.offsetMeters(north: 5000)),
      ];
      final result = detector.findPotentialDuplicates(
        title: 'Big potholes on Canal Road',
        description: 'service lane broken',
        category: ComplaintCategory.roadDamage,
        location: origin.offsetMeters(north: 40),
        existing: existing,
      );
      expect(result.map((r) => r.complaint.id), ['A']);
      expect(result.first.distanceMeters, closeTo(40, 2));
      expect(result.first.reasons.first, contains('m away'));
    });

    test('ignores closed reports', () {
      final result = detector.findPotentialDuplicates(
        title: 'Potholes on Canal Road',
        description: '',
        category: ComplaintCategory.roadDamage,
        location: origin,
        existing: [
          _complaint('A', 'Potholes on Canal Road',
              ComplaintCategory.roadDamage, origin,
              status: ComplaintStatus.resolved)
        ],
      );
      expect(result, isEmpty);
    });

    test('falls back to text-only matching without GPS', () {
      final result = detector.findPotentialDuplicates(
        title: 'Garbage overflowing at Community Park entrance',
        description: '',
        category: ComplaintCategory.garbage,
        location: null,
        existing: [
          _complaint('A', 'Garbage overflowing at Community Park gate',
              ComplaintCategory.garbage, origin),
        ],
      );
      expect(result, hasLength(1));
      expect(result.first.distanceMeters, isNull);
      expect(result.first.reasons.first, contains('text-only'));
    });
  });

  group('PriorityEngine', () {
    const engine = PriorityEngine();
    final now = DateTime(2026, 10, 10);

    test('severity words, supporters and age raise priority', () {
      final low = engine.assess(
          category: ComplaintCategory.streetlight,
          title: 'Bulb fused',
          description: '',
          supportCount: 0,
          createdAt: now,
          now: now,
          rules: PriorityRules.defaults);
      final high = engine.assess(
          category: ComplaintCategory.roadDamage,
          title: 'Pothole caused accident near school',
          description: '',
          supportCount: 10,
          createdAt: now.subtract(const Duration(days: 5)),
          now: now,
          rules: PriorityRules.defaults);
      expect(low.level, PriorityLevel.low);
      expect(high.level, PriorityLevel.critical);
      expect(high.factors.map((f) => f.label),
          containsAll(['Severity word "accident"', '10 supporters']));
      expect(high.explanation, startsWith('Critical'));
    });

    test('rules are configurable', () {
      final rules = PriorityRules.defaults.copyWith(categoryBase: {
        ...PriorityRules.defaults.categoryBase,
        ComplaintCategory.streetlight: 90,
      });
      final result = engine.assess(
          category: ComplaintCategory.streetlight,
          title: 'Bulb fused',
          description: '',
          supportCount: 0,
          createdAt: now,
          now: now,
          rules: rules);
      expect(result.level, PriorityLevel.critical);
    });
  });
}
