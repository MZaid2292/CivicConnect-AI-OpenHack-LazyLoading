import 'dart:async';

import 'package:flutter/widgets.dart';

String greetingFor(DateTime time) {
  final h = time.hour;
  if (h >= 5 && h < 12) return 'Good morning';
  if (h >= 12 && h < 17) return 'Good afternoon';
  if (h >= 17 && h < 19) return 'Good evening';
  return 'Good night';
}

DateTime nextGreetingChange(DateTime time) {
  for (final hour in const [5, 12, 17, 19]) {
    final boundary = DateTime(time.year, time.month, time.day, hour);
    if (boundary.isAfter(time)) return boundary;
  }
  return DateTime(time.year, time.month, time.day + 1, 5);
}

class TimeGreeting extends StatefulWidget {
  const TimeGreeting({
    super.key,
    required this.name,
    this.style,
    this.clock = DateTime.now,
  });

  final String name;
  final TextStyle? style;
  final DateTime Function() clock;

  @override
  State<TimeGreeting> createState() => _TimeGreetingState();
}

class _TimeGreetingState extends State<TimeGreeting> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final now = widget.clock();
    _timer = Timer(
        nextGreetingChange(now).difference(now) + const Duration(seconds: 1),
        _refresh);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text('${greetingFor(widget.clock())}, ${widget.name}',
          style: widget.style);
}
