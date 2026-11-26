import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/app.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'trackyu_integration_test.dart' show Adapter, reply, MemoryVault;
import 'local_workspace_test.dart' show MemoryWorkspace;

void main() {
  testWidgets('Clicking Restore on previous data dialog does not crash', (
    tester,
  ) async {
    final dio = Dio()
      ..httpClientAdapter = Adapter((r) {
        if (r.path.contains('DutyTracking/day')) {
          return reply({
            'userId': 'IN015',
            'date': (r.data as Map)['date'],
            'events': [],
            'visits': [],
          });
        }
        if (r.path.contains('MobileVisits/mine')) {
          return reply([]);
        }
        if (r.path.contains('Portal/profile')) {
          return reply({
            'isField': false,
            'offices': [
              {'id': 42, 'name': 'HQ', 'isMember': true, 'isEnabled': true},
            ],
          });
        }
        if (r.path.contains('OfficeAttendance/state')) {
          return reply({'attendance': null});
        }
        return reply([]);
      });

    final controller = TrackyuController(
      TrackyuApi('https://test.example/api', client: dio),
      vault: MemoryVault(),
    );
    controller.user = {'userId': 'IN015'};
    controller.local = MemoryWorkspace();
    controller.restoreOffered = true;
    controller.isField = false;
    controller.officeId = null;

    await tester.pumpWidget(
      MaterialApp(home: AttendancePage(controller: controller)),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The dialog should be visible
    expect(find.text('Restore previous phone data?'), findsOneWidget);

    // Tap Restore button
    await tester.tap(find.text('Restore'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.notice, contains('7 daily timelines restored'));
  });
}
