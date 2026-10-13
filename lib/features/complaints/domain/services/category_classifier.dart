import 'package:equatable/equatable.dart';

import '../../../../core/utils/text_similarity.dart';
import '../complaint.dart';

class CategorySuggestion extends Equatable {
  const CategorySuggestion({
    required this.category,
    required this.score,
    required this.confidence,
    required this.matchedTerms,
  });
  final ComplaintCategory category;
  final double score;

  final double confidence;
  final List<String> matchedTerms;

  @override
  List<Object?> get props => [category, score, confidence, matchedTerms];
}

class ClassificationResult extends Equatable {
  const ClassificationResult(this.suggestions);
  const ClassificationResult.empty() : suggestions = const [];

  final List<CategorySuggestion> suggestions;

  CategorySuggestion? get top => suggestions.isEmpty ? null : suggestions.first;
  bool get hasSuggestion => top != null;

  String get explanation {
    final best = top;
    if (best == null) {
      return 'No category keywords found yet. Add more detail or pick a '
          'category manually.';
    }
    return 'Matched ${best.matchedTerms.map((t) => '"$t"').join(', ')} '
        '→ ${best.category.label}.';
  }

  @override
  List<Object?> get props => [suggestions];
}

class KeywordCategoryClassifier {
  const KeywordCategoryClassifier({this.rules = defaultRules});

  final Map<ComplaintCategory, Map<String, double>> rules;

  static const titleWeight = 1.5;

  static const defaultRules = <ComplaintCategory, Map<String, double>>{
    ComplaintCategory.roadDamage: {
      'pothole': 3,
      'road damage': 3,
      'broken road': 3,
      'crater': 2,
      'crack': 1.5,
      'asphalt': 2,
      'road': 1,
      'speed breaker': 1.5,
      'manhole cover': 2,
      'footpath': 1,
      'pavement': 1.5,
      'tyre': 1,
      'bumpy': 1.5,
    },
    ComplaintCategory.streetlight: {
      'streetlight': 3,
      'street light': 3,
      'lamp post': 3,
      'light pole': 3,
      'bulb': 2,
      'lamp': 2,
      'dark': 1.5,
      'flicker': 2,
      'no light': 2,
      'light': 1,
      'wire': 1,
      'electric': 1.5,
    },
    ComplaintCategory.garbage: {
      'garbage': 3,
      'trash': 3,
      'waste': 2.5,
      'rubbish': 3,
      'litter': 2,
      'dump': 2,
      'bin': 2,
      'overflow': 1,
      'collection': 1.5,
      'smell': 1,
      'stench': 1.5,
      'plastic': 1,
      'debris': 1.5,
    },
    ComplaintCategory.drainage: {
      'drain': 3,
      'sewer': 3,
      'sewage': 3,
      'water leak': 3,
      'pipe burst': 3,
      'pipeline': 2,
      'waterlogging': 3,
      'flood': 2,
      'gutter': 2.5,
      'standing water': 2.5,
      'leak': 1.5,
    },
  };

  ClassificationResult classify(String title, String description) {
    final normTitle = normalizeText(title);
    final normBody = normalizeText(description);
    final scores = <ComplaintCategory, double>{};
    final matches = <ComplaintCategory, List<String>>{};

    rules.forEach((category, phrases) {
      phrases.forEach((phrase, weight) {
        final pattern = RegExp(
            '\\b${RegExp.escape(normalizeText(phrase))}(s|es|ed|ing)?\\b');
        var points = 0.0;
        if (pattern.hasMatch(normTitle)) points += weight * titleWeight;
        if (pattern.hasMatch(normBody)) points += weight;
        if (points > 0) {
          scores[category] = (scores[category] ?? 0) + points;
          (matches[category] ??= []).add(phrase);
        }
      });
    });

    final total = scores.values.fold<double>(0, (a, b) => a + b);
    if (total == 0) return const ClassificationResult.empty();

    final suggestions = scores.entries
        .map((e) => CategorySuggestion(
              category: e.key,
              score: e.value,
              confidence: e.value / total,
              matchedTerms: matches[e.key]!,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return ClassificationResult(suggestions);
  }
}
