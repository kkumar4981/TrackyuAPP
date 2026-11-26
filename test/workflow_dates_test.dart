import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/workflow_dates.dart';

void main() {
  test('arrival is restricted to a future time on the same day', () {
    final now = DateTime(2026, 11, 7, 10, 12);
    expect(arrivalAllowed(DateTime(2026, 11, 7, 10, 10), now), isFalse);
    expect(arrivalAllowed(now, now), isFalse);
    expect(arrivalAllowed(DateTime(2026, 11, 7, 10, 15), now), isTrue);
    expect(arrivalAllowed(DateTime(2026, 11, 8, 10), now), isFalse);
  });
  testWidgets('styled date fields open the calendar and fit a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateTime(2026, 11, 7);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.all(16),
              child: WorkflowDateFields(
                from: today,
                to: today,
                onFrom: () => showDatePicker(
                  context: context,
                  initialDate: today,
                  firstDate: today,
                  lastDate: today.add(const Duration(days: 30)),
                ),
                onTo: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('From date'), findsOneWidget);
    expect(find.text('To date'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('7 Nov 2026').first);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
