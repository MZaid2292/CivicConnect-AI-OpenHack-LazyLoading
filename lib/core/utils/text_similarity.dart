/// Lightweight text normalisation used by rule-based NLP services.
library;

const _stopWords = {
  'a',
  'an',
  'the',
  'and',
  'or',
  'of',
  'in',
  'on',
  'at',
  'to',
  'for',
  'is',
  'are',
  'was',
  'were',
  'be',
  'been',
  'it',
  'this',
  'that',
  'there',
  'here',
  'near',
  'with',
  'from',
  'by',
  'has',
  'have',
  'had',
  'very',
  'our',
  'my',
  'we',
  'i',
  'they',
  'not',
  'no',
  'please',
  'since',
  'still',
  'also',
  'its',
  'as',
  'so',
  'but',
  'too',
  'some',
  'all',
  'any',
  'can',
  'will',
  'just',
};

/// Lower-cases and strips punctuation, collapsing whitespace.
String normalizeText(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Very small suffix stemmer so "potholes" and "pothole" compare equal.
String stem(String token) {
  if (token.length > 4 && token.endsWith('ies')) {
    return '${token.substring(0, token.length - 3)}y';
  }
  if (token.length > 5 && token.endsWith('ing')) {
    return token.substring(0, token.length - 3);
  }
  if (token.length > 4 && token.endsWith('ed')) {
    return token.substring(0, token.length - 2);
  }
  if (token.length > 3 && token.endsWith('s') && !token.endsWith('ss')) {
    return token.substring(0, token.length - 1);
  }
  return token;
}

/// Normalised, stemmed tokens without stop words.
Set<String> tokenize(String input) => normalizeText(input)
    .split(' ')
    .where((t) => t.length > 1 && !_stopWords.contains(t))
    .map(stem)
    .toSet();

/// Jaccard similarity |A∩B| / |A∪B| of the token sets (0..1).
double jaccardSimilarity(String a, String b) {
  final ta = tokenize(a);
  final tb = tokenize(b);
  if (ta.isEmpty || tb.isEmpty) return 0;
  final intersection = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return intersection / union;
}

/// Shared tokens, useful for explaining a similarity score to users.
Set<String> sharedTokens(String a, String b) =>
    tokenize(a).intersection(tokenize(b));
