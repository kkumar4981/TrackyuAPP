import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/models.dart';

class DeviceHealth {
  Json device={};
  bool gps=false, precise=false, location=false, background=false;
  bool camera=false, notifications=false;
  bool? batteryExempt;
  String? error;
  Future<void> inspect() async {
    error=null;
    try {
      gps=await Geolocator.isLocationServiceEnabled();
      final auth=await Geolocator.checkPermission();
      location=auth==LocationPermission.always || auth==LocationPermission.whileInUse;
      background=auth==LocationPermission.always;
      precise=location && await Geolocator.getLocationAccuracy()==LocationAccuracyStatus.precise;
      camera=await Permission.camera.isGranted;
      notifications=await Permission.notification.isGranted;
      if(Platform.isAndroid) {
        final d=await DeviceInfoPlugin().androidInfo;
        device={'platform':'android','brand':d.manufacturer,'model':d.model,'os':d.version.release,'sdk':d.version.sdkInt};
        batteryExempt=await Permission.ignoreBatteryOptimizations.isGranted;
      } else if(Platform.isIOS) {
        final d=await DeviceInfoPlugin().iosInfo;
        device={'platform':'ios','brand':'Apple','model':d.utsname.machine,'os':d.systemVersion};
      }
    } catch(e) { error='Device check failed: $e'; }
  }
  Future<void> requestLocation() async {
    final status=await Geolocator.checkPermission();
    if(status==LocationPermission.deniedForever) { await Geolocator.openAppSettings(); }
    else if(status==LocationPermission.denied) { await Geolocator.requestPermission(); }
    else if(!precise) { await Geolocator.openAppSettings(); }
    else if(!gps) { await Geolocator.openLocationSettings(); }
    await inspect();
  }
  Future<void> requestBackground() async {
    if(!location) { await requestLocation(); return; }
    final p=await Permission.locationAlways.status;
    if(p.isPermanentlyDenied || p.isDenied) {
      // System may require granting Always through Settings. No popup loops.
      await Permission.locationAlways.request();
      if(!await Permission.locationAlways.isGranted) { await openAppSettings(); }
    }
    await inspect();
  }
  List<String> blockers(Policy p)=>[
    if(error!=null) error!, if(!gps) 'Turn on device location services.',
    if(!location) 'Location permission is required.',
    if(location && !precise) 'Enable Precise location.',
    if(p.backgroundRequired && !background) 'This policy requires background/Always location access.',
  ];
  Json toJson()=>{...device,'gps':gps,'locationGranted':location,'precise':precise,
    'backgroundGranted':background,'notificationsGranted':notifications,'cameraGranted':camera,
    'batteryExempt':batteryExempt};
  String get vendorAdvice {
    final brand='${device['brand']}'.toLowerCase();
    if(brand.contains('xiaomi')||brand.contains('redmi')||brand.contains('poco')) {
      return 'Xiaomi / Redmi / POCO: review background autostart and app battery restrictions. Menu paths vary by MIUI/HyperOS. App cannot universally verify these switches.';
    }
    if(['oppo','realme','oneplus','vivo','iqoo'].any(brand.contains)) {
      return 'Review this app’s battery/background activity and autostart settings. Available controls vary by model and OS. Return here and run the locked-screen test.';
    }
    if(Platform.isIOS) { return 'Enable the required location access and Precise Location. Force quitting or OS termination can interrupt tracking; Always access does not guarantee continuous execution.'; }
    return 'Review battery restrictions and allow duty tracking where supported. No setting guarantees continuous execution after force-stop or shutdown.';
  }
}
