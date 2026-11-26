import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/app.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'trackyu_integration_test.dart' show MemoryVault;

class SlowController extends TrackyuController {
  SlowController()
    : super(TrackyuApi('https://example.invalid/api'), vault: MemoryVault());
  final completion = Completer<void>();
  @override
  Future<void> initialize() => completion.future;
}

void main() {
  testWidgets('fresh install renders before secure storage finishes', (
    tester,
  ) async {
    final storage = Completer<String?>();
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) => storage.future,
    );
    await tester.pumpWidget(const TrackyuApp());
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    storage.complete(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(LegacyLogin), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });
  testWidgets(
    'stalled initialization offers retry instead of endless spinner',
    (tester) async {
      final controller = SlowController();
      await tester.pumpWidget(TrackyuApp(controller: controller));
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.completion.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
