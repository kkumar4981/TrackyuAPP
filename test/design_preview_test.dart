import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'package:fieldforce_hrms/trackyu/app.dart';
import 'trackyu_integration_test.dart' show MemoryVault;

void main() {
  testWidgets('slider waits for confirmation and prevents repeat submissions', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlidePunch(
            enabled: true,
            label: 'Slide to punch in',
            onSubmit: () {
              calls++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    expect(find.text('Confirming...'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
  });
  testWidgets('design previews and short/tap slider do not submit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final font = FontLoader('Roboto')
        ..addFont(
          File(
            '../.tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await icons.load();
    });
    final controller = TrackyuController(
      TrackyuApi('https://test.example/api'),
      vault: MemoryVault(),
    );
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/legacy/logo.png'),
          tester.element(find.byType(Scaffold).first),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (!const bool.fromEnvironment('DESIGN_PREVIEWS')) return;
      await tester.runAsync(() async {
        final rendered =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final picture = await rendered.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File('../.tools/qa/design-$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TrackyuApp(controller: controller),
      ),
    );
    await capture('login');
    controller.user = {'NAME': 'Sanjay Singh', 'SM_USER_ID': 'TEST1'};
    controller.isField = true;
    controller.stateKnown = true;
    controller.workDate = '2026-11-07';
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TrackyuApp(key: UniqueKey(), controller: controller),
      ),
    );
    await capture('home');
    var submissions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SlidePunch(
              enabled: true,
              label: 'Slide to punch in',
              onSubmit: () async {
                submissions++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(
      tester.getTopRight(find.byType(Slider)) - const Offset(12, -20),
    );
    await tester.pumpAndSettle();
    expect(submissions, 0);
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(submissions, 0);
    await tester.drag(find.byType(Slider), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(submissions, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
