import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'api.dart';
import 'punch_telemetry.dart';

Future<Json> mobileDeviceIdentity() async {
  String? id;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final value = await const MethodChannel(
      'trackyu/device_settings',
    ).invokeMethod<String>('identity');
    if (value != null && value.isNotEmpty) id = 'android:$value';
  } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final value = (await DeviceInfoPlugin().iosInfo).identifierForVendor;
    if (value != null && value.isNotEmpty) id = 'ios:$value';
  } else {
    throw const ApiFailure(
      'MOBILE_APP_REQUIRED',
      'Use the Android or iOS app for device-bound attendance. Use the portal for browser access.',
    );
  }
  if (id == null) {
    throw const ApiFailure(
      'DEVICE_ID_UNAVAILABLE',
      'Unable to identify this phone. Unlock it and restart Trackyu.',
    );
  }
  final name = await phoneDescription();
  return {
    'deviceId': id,
    'deviceName': name.length <= 100 ? name : name.substring(0, 100),
  };
}
