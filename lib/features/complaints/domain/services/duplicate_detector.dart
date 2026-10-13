import 'package:equatable/equatable.dart';

import '../../../../core/utils/geo.dart';
import '../../../../core/utils/text_similarity.dart';
import '../complaint.dart';

class DuplicateCandidate extends Equatable {
  const DuplicateCandidate({
    required this.complaint,
    required this.score,
    required this.textSimilarity,
    required this.sameCategory,
    required this.reasons,
    this.distanceMeters,
  });
  final Complaint complaint;

  final double score;
  final double textSimilarity;
  final bool sameCategory;
  final double? distanceMeters;
  final List<String> reasons;

  @override
  List<Object?> get props =>
      [complaint.id, score, textSimilarity, sameCategory, distanceMeters];
}

class DuplicateDetector {
  const DuplicateDetector({
    this.radiusMeters = 300,
    this.threshold = 0.5,
    this.textOnlyMinSimilarity = 0.3,
  });

  final double radiusMeters;
  final double threshold;
  final double textOnlyMinSimilarity;

  List<DuplicateCandidate> findPotentialDuplicates({
    required String title,
    required String description,
    required ComplaintCategory category,
    required GeoPoint? location,
    required Iterable<Complaint> existing,
    String? excludeId,
    int limit = 3,
  }) {
    final text = '$title $description';
    final results = <DuplicateCandidate>[];

    for (final other in existing) {
      if (other.id == excludeId || !other.status.isOpen) continue;
      final similarity =
          jaccardSimilarity(text, '${other.title} ${other.description}');
      final sameCategory = other.category == category;
      final reasons = <String>[];
      double score;
      double? distance;

      if (location != null && other.location != null) {
        distance = haversineMeters(location, other.location!);
        if (distance > radiusMeters) continue;
        final proximity = 1 - distance / radiusMeters;
        score =
            0.45 * proximity + (sameCategory ? 0.25 : 0) + 0.30 * similarity;
        reasons.add('${formatDistance(distance)} away');
      } else {
        if (similarity < textOnlyMinSimilarity) continue;
        score = (sameCategory ? 0.35 : 0) + 0.65 * similarity;
        reasons.add('Location unavailable — text-only match');
      }

      if (sameCategory) reasons.add('Same category (${category.shortLabel})');
      final shared = sharedTokens(text, '${other.title} ${other.description}');
      if (shared.isNotEmpty) {
        reasons.add(
            '${(similarity * 100).round()}% wording overlap: ${shared.take(4).join(', ')}');
      }
      if (score >= threshold) {
        results.add(DuplicateCandidate(
          complaint: other,
          score: score,
          textSimilarity: similarity,
          sameCategory: sameCategory,
          distanceMeters: distance,
          reasons: reasons,
        ));
      }
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }
}
