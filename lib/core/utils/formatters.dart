import 'package:intl/intl.dart';

final _dateTime = DateFormat('d MMM yyyy, h:mm a');
final _date = DateFormat('d MMM yyyy');
final _currency = NumberFormat.decimalPattern();

String formatDateTime(DateTime value) => _dateTime.format(value);
String formatDate(DateTime value) => _date.format(value);

/// Simulated currency only — no real money moves in this app.
String formatAmount(num value) => 'Rs ${_currency.format(value)}';

String timeAgo(DateTime value, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(value);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return formatDate(value);
}
