import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../../../core/utils/text_similarity.dart';
import '../complaint.dart';

enum PriorityLevel { low, medium, high, critical }

extension PriorityLevelInfo on PriorityLevel {
  String get label => switch (this) {
        PriorityLevel.low => 'Low',
        PriorityLevel.medium => 'Medium',
        PriorityLevel.high => 'High',
        PriorityLevel.critical => 'Critical',
      };
}

class PriorityRules extends Equatable {
  const PriorityRules({
    required this.categoryBase,
    required this.severityKeywords,
    required this.pointsPerSupporter,
    required this.maxSupportPoints,
    required this.pointsPerDayOpen,
    required this.maxAgePoints,
    required this.mediumThreshold,
    required this.highThreshold,
    required this.criticalThreshold,
  });

  static const defaults = PriorityRules(
    categoryBase: {
      ComplaintCategory.roadDamage: 25,
      ComplaintCategory.streetlight: 15,
      ComplaintCategory.garbage: 20,
      ComplaintCategory.drainage: 25,
      ComplaintCategory.other: 10,
    },
    severityKeywords: {
      'accident': 25,
      'injury': 30,
      'injured': 30,
      'dangerous': 20,
      'school': 15,
      'children': 15,
      'hospital': 15,
      'exposed wire': 30,
      'sparking': 30,
      'blocked': 15,
      'flooding': 20,
      'disease': 12,
      'mosquito': 10,
      'dark': 8,
      'deep': 8,
    },
    pointsPerSupporter: 3,
    maxSupportPoints: 30,
    pointsPerDayOpen: 2,
    maxAgePoints: 20,
    mediumThreshold: 30,
    highThreshold: 55,
    criticalThreshold: 80,
  );

  final Map<ComplaintCategory, int> categoryBase;
  final Map<String, int> severityKeywords;
  final int pointsPerSupporter;
  final int maxSupportPoints;
  final int pointsPerDayOpen;
  final int maxAgePoints;
  final int mediumThreshold;
  final int highThreshold;
  final int criticalThreshold;

  bool get thresholdsValid =>
      0 < mediumThreshold &&
      mediumThreshold < highThreshold &&
      highThreshold < criticalThreshold;

  PriorityRules copyWith({
    Map<ComplaintCategory, int>? categoryBase,
    Map<String, int>? severityKeywords,
    int? pointsPerSupporter,
    int? maxSupportPoints,
    int? pointsPerDayOpen,
    int? maxAgePoints,
    int? mediumThreshold,
    int? highThreshold,
    int? criticalThreshold,
  }) =>
      PriorityRules(
        categoryBase: categoryBase ?? this.categoryBase,
        severityKeywords: severityKeywords ?? this.severityKeywords,
        pointsPerSupporter: pointsPerSupporter ?? this.pointsPerSupporter,
        maxSupportPoints: maxSupportPoints ?? this.maxSupportPoints,
        pointsPerDayOpen: pointsPerDayOpen ?? this.pointsPerDayOpen,
        maxAgePoints: maxAgePoints ?? this.maxAgePoints,
        mediumThreshold: mediumThreshold ?? this.mediumThreshold,
        highThreshold: highThreshold ?? this.highThreshold,
        criticalThreshold: criticalThreshold ?? this.criticalThreshold,
      );

  @override
  List<Object?> get props => [
        categoryBase,
        severityKeywords,
        pointsPerSupporter,
        maxSupportPoints,
        pointsPerDayOpen,
        maxAgePoints,
        mediumThreshold,
        highThreshold,
        criticalThreshold,
      ];
}

class PriorityFactor extends Equatable {
  const PriorityFactor(this.label, this.points);
  final String label;
  final int points;

  @override
  List<Object?> get props => [label, points];
}

class PriorityAssessment extends Equatable {
  const PriorityAssessment(
      {required this.score, required this.level, required this.factors});
  final int score;
  final PriorityLevel level;
  final List<PriorityFactor> factors;

  String get explanation =>
      '${level.label} ($score pts): ${factors.map((f) => '${f.label} +${f.points}').join(' · ')}';

  @override
  List<Object?> get props => [score, level, factors];
}

class PriorityEngine {
  const PriorityEngine();

  PriorityAssessment assess({
    required ComplaintCategory category,
    required String title,
    required String description,
    required int supportCount,
    required DateTime createdAt,
    required DateTime now,
    required PriorityRules rules,
  }) {
    final factors = <PriorityFactor>[];
    final base = rules.categoryBase[category] ?? 0;
    factors.add(PriorityFactor('Issue type: ${category.shortLabel}', base));

    final text = normalizeText('$title $description');
    rules.severityKeywords.forEach((word, points) {
      final pattern =
          RegExp('\\b${RegExp.escape(normalizeText(word))}(s|es|ed|ing)?\\b');
      if (points != 0 && pattern.hasMatch(text)) {
        factors.add(PriorityFactor('Severity word "$word"', points));
      }
    });

    final supportPoints = math.min(
        supportCount * rules.pointsPerSupporter, rules.maxSupportPoints);
    if (supportPoints > 0) {
      factors.add(PriorityFactor('$supportCount supporters', supportPoints));
    }

    final days = math.max(0, now.difference(createdAt).inDays);
    final agePoints =
        math.min(days * rules.pointsPerDayOpen, rules.maxAgePoints);
    if (agePoints > 0) {
      factors.add(PriorityFactor('Open $days days', agePoints));
    }

    final score = factors.fold<int>(0, (sum, f) => sum + f.points);
    return PriorityAssessment(
        score: score, level: levelFor(score, rules), factors: factors);
  }

  PriorityLevel levelFor(int score, PriorityRules rules) {
    if (score >= rules.criticalThreshold) return PriorityLevel.critical;
    if (score >= rules.highThreshold) return PriorityLevel.high;
    if (score >= rules.mediumThreshold) return PriorityLevel.medium;
    return PriorityLevel.low;
  }

  PriorityAssessment assessComplaint(
          Complaint c, PriorityRules rules, DateTime now) =>
      assess(
        category: c.category,
        title: c.title,
        description: c.description,
        supportCount: c.supportCount,
        createdAt: c.createdAt,
        now: now,
        rules: rules,
      );
}
