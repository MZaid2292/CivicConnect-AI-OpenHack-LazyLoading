import 'package:civicconnect_ai/core/utils/greeting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int h, int m) => DateTime(2026, 10, 14, h, m);

void main() {
  test('greeting boundaries follow local time', () {
    final cases = {
      at(4, 59): 'Good night',
      at(5, 0): 'Good morning',
      at(11, 59): 'Good morning',
      at(12, 0): 'Good afternoon',
      at(16, 59): 'Good afternoon',
      at(17, 0): 'Good evening',
      at(18, 59): 'Good evening',
      at(19, 0): 'Good night',
      at(0, 0): 'Good night',
      at(23, 59): 'Good night',
    };
    cases.forEach((time, expected) {
      expect(greetingFor(time), expected, reason: '$time');
    });
  });

  test('next change is the next boundary, wrapping past midnight', () {
    expect(nextGreetingChange(at(4, 59)), at(5, 0));
    expect(nextGreetingChange(at(5, 0)), at(12, 0));
    expect(nextGreetingChange(at(16, 59)), at(17, 0));
    expect(nextGreetingChange(at(18, 59)), at(19, 0));
    expect(nextGreetingChange(at(19, 0)), DateTime(2026, 10, 15, 5));
  });

  testWidgets('updates across a boundary and on resume, keeping the name',
      (tester) async {
    var now = at(16, 59);
    await tester.pumpWidget(
        MaterialApp(home: TimeGreeting(name: 'Zaid', clock: () => now)));
    expect(find.text('Good afternoon, Zaid'), findsOneWidget);

    // Stays open across 17:00: one timer to the boundary, no polling.
    now = at(17, 0);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(find.text('Good evening, Zaid'), findsOneWidget);

    // Reopened / resumed later.
    now = at(19, 30);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Good night, Zaid'), findsOneWidget);
  });
}
