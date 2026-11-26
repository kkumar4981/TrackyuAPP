import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldforce_hrms/trackyu/api.dart';
import 'package:fieldforce_hrms/trackyu/controller.dart';
import 'trackyu_integration_test.dart' show Adapter, reply, MemoryVault;

void main() {
  test('portal changes replace menu visibility on the next refresh', () async {
    var visitsEnabled = true;
    final client = Dio()
      ..httpClientAdapter = Adapter(
        (r) => reply([
          {'key': 'visits', 'enabled': visitsEnabled},
          {'key': 'leave', 'enabled': false},
          {'key': 'history', 'enabled': true},
        ]),
      );
    final controller = TrackyuController(
      TrackyuApi('https://test.example/api', client: client),
      vault: MemoryVault(),
    );
    expect(controller.menuEnabled('visits'), isFalse);
    await controller.refreshMenus();
    expect(controller.menuEnabled('visits'), isTrue);
    expect(controller.menuEnabled('leave'), isFalse);
    visitsEnabled = false;
    await controller.refreshMenus();
    expect(controller.menuEnabled('visits'), isFalse);
    expect(controller.menuEnabled('history'), isTrue);
    await controller.signOut();
    expect(controller.menuEnabled('history'), isFalse);
    controller.dispose();
  });
}
