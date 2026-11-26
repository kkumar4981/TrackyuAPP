import 'package:flutter/material.dart';
import 'package:fieldforce_hrms/trackyu/visits.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/visit_media.dart';
import 'local_workspace_test.dart' show MemoryWorkspace;
import 'trackyu_integration_test.dart' show Adapter, MemoryVault, testSelfie;

void main() {
  testWidgets(
    'completed offline open visit shows both photo actions on a narrow screen',
    (tester) async {
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) { debugPrint(details.toString()); oldHandler?.call(details); };
      addTearDown(() => FlutterError.onError = oldHandler);
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = TrackyuController(
        TrackyuApi('https://test.example/api'),
        vault: MemoryVault(),
      )..user = {'SM_USER_ID': 'QA'};
      c.offline = true;
      final db = MemoryWorkspace();
      db.records[c.dayKey] = {
        'visits': [
          {
            'id': 1,
            'kind': 'Open',
            'shopName': 'Test visit',
            'workDate': c.localDay,
            'checkInUtc': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
            'checkOutUtc': DateTime.now().toUtc().toIso8601String(),
            'photoBase64': testSelfie,
            'departureSelfieBase64': testSelfie,
          },
        ],
      };
      c.local = db;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: VisitsPage(controller: c),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed').first);
      await tester.pump();
      expect(find.text('Arrival selfie'), findsOneWidget);
      expect(find.text('Departure selfie'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  test(
    'local checkout selfie is available before a server photo flag exists',
    () async {
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = Adapter((_) {
          requests++;
          throw StateError('Unexpected server request');
        });
      final c = TrackyuController(
        TrackyuApi('https://test.example/api', client: dio),
        vault: MemoryVault(),
      )..user = {'SM_USER_ID': 'QA'};
      c.offline = true;
      final row = <String, dynamic>{
        'id': 1,
        'kind': 'Open',
        'checkOutUtc': DateTime.now().toUtc().toIso8601String(),
        'departureSelfieBase64': testSelfie,
      };
      expect(hasDeparturePhoto(row), true);
      expect(await loadVisitPhoto(c, row, 'out'), base64Decode(testSelfie));
      expect(requests, 0);
      c.dispose();
    },
  );
  test(
    'metadata resolves past-day original photos across local/server ID remapping',
    () async {
      final c = TrackyuController(
        TrackyuApi('https://test.example/api'),
        vault: MemoryVault(),
      )..user = {'SM_USER_ID': 'QA'};
      c.offline = true;
      final db = MemoryWorkspace();
      db.records['day:2026-11-09'] = {
        'visits': [
          {'id': 88, 'localId': 1, 'departureSelfieBase64': testSelfie},
        ],
      };
      c.local = db;
      final row = <String, dynamic>{
        'id': 88,
        'localId': 1,
        'kind': 'Open',
        'checkInUtc': '2026-11-09T04:30:00Z',
        'checkOutUtc': '2026-11-09T05:00:00Z',
      };
      expect(hasDeparturePhoto(row), false);
      expect(hasDeparturePhoto(await localVisitMedia(c, row)), true);
      expect(await loadVisitPhoto(c, row, 'out'), base64Decode(testSelfie));
      c.dispose();
    },
  );
  test(
    'missing offline photo reports unavailable without calling the API',
    () async {
      final c = TrackyuController(
        TrackyuApi('https://test.example/api'),
        vault: MemoryVault(),
      );
      c.offline = true;
      await expectLater(
        loadVisitPhoto(c, {'id': 1}, 'out'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.code,
            'code',
            'SELFIE_UNAVAILABLE_OFFLINE',
          ),
        ),
      );
      expect(
        visitPhotoBytes({'departureSelfieBase64': 'invalid!'}, 'out'),
        null,
      );
      expect(hasDeparturePhoto({'kind': 'Regular', 'checkOutUtc': 'x'}), false);
      c.dispose();
    },
  );
}
