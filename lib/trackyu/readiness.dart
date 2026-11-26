import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'duty_tracking.dart';

/// OEM device profile fetched from the server DB (WorkforceDeviceOemProfiles).
/// Stored in PhoneReadiness after login; replaces all hardcoded brand checks.
/// Updated server-side without needing an app release.
class OemDeviceProfile {
  final String brand;
  final String displayName;
  final String oemUiName;
  final String backgroundKillRisk; // 'none','low','medium','high','critical'
  final String verificationStatus; // 'verified', 'community_verified', 'untested'
  final bool requiresAutostartSetting;
  final String? autostartPackage;
  final String? autostartActivity;
  final String? autostartInstructions;
  final bool requiresBatteryUnrestricted;
  final String? batteryPackage;
  final String? batteryActivity;
  final String? batteryInstructions;

  const OemDeviceProfile({
    required this.brand,
    required this.displayName,
    required this.oemUiName,
    required this.backgroundKillRisk,
    this.verificationStatus = 'untested',
    required this.requiresAutostartSetting,
    this.autostartPackage,
    this.autostartActivity,
    this.autostartInstructions,
    required this.requiresBatteryUnrestricted,
    this.batteryPackage,
    this.batteryActivity,
    this.batteryInstructions,
  });

  factory OemDeviceProfile.fromJson(Map<String, dynamic> j) => OemDeviceProfile(
    brand: (j['brand'] ?? '').toString(),
    displayName: (j['displayName'] ?? 'Android Phone').toString(),
    oemUiName: (j['oemUiName'] ?? 'Android').toString(),
    backgroundKillRisk: (j['backgroundKillRisk'] ?? 'medium').toString(),
    verificationStatus: (j['verificationStatus'] ?? 'untested').toString(),
    requiresAutostartSetting: j['requiresAutostartSetting'] == true,
    autostartPackage: j['autostartPackage']?.toString(),
    autostartActivity: j['autostartActivity']?.toString(),
    autostartInstructions: j['autostartInstructions']?.toString(),
    requiresBatteryUnrestricted: j['requiresBatteryUnrestricted'] != false,
    batteryPackage: j['batteryPackage']?.toString(),
    batteryActivity: j['batteryActivity']?.toString(),
    batteryInstructions: j['batteryInstructions']?.toString(),
  );

  static const OemDeviceProfile fallback = OemDeviceProfile(
    brand: '',
    displayName: 'Android Phone',
    oemUiName: 'Android',
    backgroundKillRisk: 'medium',
    verificationStatus: 'untested',
    requiresAutostartSetting: false,
    requiresBatteryUnrestricted: true,
    batteryInstructions: "Settings \u2192 Apps \u2192 Trackyu \u2192 Battery \u2192 Unrestricted",
  );
}



enum SetupItem {
  network,
  server,
  appVersion,
  speed,
  gps,
  location,
  precise,
  background,
  battery,
  autostart,
  storage,
  cloneApp,
  notifications,
  camera,
}

class SetupCheck {
  final SetupItem item;
  final String title, detail;
  final bool ready, required;
  const SetupCheck(
    this.item,
    this.title,
    this.detail,
    this.ready, {
    this.required = true,
  });
}

abstract class ReadinessPlatform {
  Stream<bool> get changes;
  Future<List<SetupCheck>> inspect();
  Future<void> fix(SetupItem item);
}

class PhoneReadiness implements ReadinessPlatform {
  final TrackyuApi api;
  final bool Function() cameraRequired;
  final bool Function() offlineAllowed;
  final String Function()? getAppVersion;
  final String? Function()? getUserId;

  PhoneReadiness(
    this.api, {
    bool Function()? cameraRequired,
    bool Function()? offlineAllowed,
    this.getAppVersion,
    this.getUserId,
  }) : cameraRequired = cameraRequired ?? (() => true),
       offlineAllowed = offlineAllowed ?? (() => false);

  DateTime? _storageCheckedAt;
  bool _storageReady = false;
  DateTime? _lastProbe;
  bool _reachable = false;
  bool _slow = false;
  Map<String, dynamic>? _lastVersionPolicy;
  DateTime? _lastVersionCheckAt;
  String _downloadUrl = 'https://trackyuweb.runasp.net/download';
  /// OEM profile loaded from server DB at login time.
  /// App calls [updateOemProfile] after login; fallback used if not yet loaded.
  OemDeviceProfile _oemProfile = OemDeviceProfile.fallback;

  /// Called by TrackyuController.login() after fetching DeviceOemProfile from API.
  void updateOemProfile(Map<String, dynamic> json) {
    _oemProfile = OemDeviceProfile.fromJson(json);
  }

  bool changed(bool lost) {
    _lastProbe = null;
    return lost;
  }

  bool get native =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  @override
  Stream<bool> get changes => native
      ? StreamGroup.merge([
          Connectivity().onConnectivityChanged.map(
            (values) =>
                changed(!values.any((v) => v != ConnectivityResult.none)),
          ),
          Geolocator.getServiceStatusStream().map(
            (value) => changed(value == ServiceStatus.disabled),
          ),
        ])
      : const Stream.empty();

  @override
  Future<List<SetupCheck>> inspect() async {
    bool network = true, reachable = false;
    if (native) {
      final transports = await Connectivity().checkConnectivity();
      network = transports.any((c) => c != ConnectivityResult.none);
    }
    if (network) {
      if (_lastProbe == null ||
          DateTime.now().difference(_lastProbe!) >
              const Duration(seconds: 30)) {
        final cancellation = CancelToken();
        final timeout = Timer(
          const Duration(seconds: 4),
          () => cancellation.cancel(),
        );
        final watch = Stopwatch()..start();
        try {
          final response = await api.dio.get(
            'Health',
            cancelToken: cancellation,
          );
          _reachable = response.data is Map && response.data['success'] == true;
          _slow = _reachable && watch.elapsed >= const Duration(seconds: 2);
        } catch (_) {
          _reachable = false;
          _slow = false;
        } finally {
          timeout.cancel();
          _lastProbe = DateTime.now();
        }
      }
      reachable = _reachable;
    } else {
      _lastProbe = null;
      _reachable = false;
      _slow = false;
    }
    final checks = <SetupCheck>[
      SetupCheck(
        SetupItem.network,
        'Internet / network',
        'Connect mobile data or Wi-Fi.',
        network,
        required: !offlineAllowed(),
      ),
      SetupCheck(
        SetupItem.server,
        'Workspace connection',
        'Your work server must be reachable. Retry after restoring your connection.',
        reachable,
        required: !offlineAllowed(),
      ),
    ];

    if (native && Platform.isAndroid) {
      bool cloneFound = false;
      String cloneReason = '';
      try {
        final cloneRes = await const MethodChannel('trackyu/device_settings')
            .invokeMethod('checkCloneApp');
        if (cloneRes is Map) {
          cloneFound = cloneRes['isCloned'] == true;
          cloneReason = (cloneRes['reason'] ?? '').toString();
        }
      } catch (_) {}
      checks.add(
        SetupCheck(
          SetupItem.cloneApp,
          'Official single app',
          cloneFound
              ? (cloneReason.isNotEmpty
                  ? cloneReason
                  : 'Cloned / Dual App detected. Uninstall Trackyu (Clone) and use only one official Trackyu app.')
              : 'Single official Trackyu installation verified.',
          !cloneFound,
        ),
      );
    }

    // Mandatory App Version Verification on Checklist Screen
    bool versionReady = true;
    final currentVer = getAppVersion?.call() ?? '1.0.0-beta.6';
    final isBeta = currentVer.toLowerCase().contains('beta');
    String versionTitle = isBeta ? 'App version (Beta)' : 'App version';
    String versionDetail = isBeta
        ? 'Trackyu $currentVer • Beta Testing Build (Check Bypassed)'
        : 'Trackyu $currentVer is up to date.';

    // Never check or enforce server version policy on Beta builds
    if (!isBeta && network && reachable) {
      if (_lastVersionCheckAt == null ||
          DateTime.now().difference(_lastVersionCheckAt!) > const Duration(seconds: 30)) {
        try {
          final res = await api.checkAppVersion(
            currentVer,
            userId: getUserId?.call(),
          );
          if (res['success'] == true) {
            _lastVersionPolicy = res;
            _lastVersionCheckAt = DateTime.now();
            if (res['downloadUrl'] != null && res['downloadUrl'].toString().isNotEmpty) {
              _downloadUrl = res['downloadUrl'].toString();
            } else if (res['portalUrl'] != null && res['portalUrl'].toString().isNotEmpty) {
              _downloadUrl = res['portalUrl'].toString();
            }
          }
        } catch (_) {}
      }
    }

    if (!isBeta && _lastVersionPolicy != null) {
      final isAllowed = _lastVersionPolicy!['isAllowed'] != false;
      final isForce = _lastVersionPolicy!['forceUpdate'] == true;
      final defaultVer = _lastVersionPolicy!['defaultVersion']?.toString() ?? '';

      if (!isAllowed || isForce) {
        versionReady = false;
        versionTitle = 'App version (Update Required)';
        versionDetail = 'Trackyu v$defaultVer is required. Please update your app to continue.';
      } else {
        versionReady = true;
        versionTitle = 'App version';
        versionDetail = 'Trackyu $currentVer is up to date.';
      }
    }

    checks.add(
      SetupCheck(
        SetupItem.appVersion,
        versionTitle,
        versionDetail,
        versionReady,
        required: !offlineAllowed(),
      ),
    );

    checks.add(
      SetupCheck(
        SetupItem.speed,
        'Connection quality',
        reachable
            ? (_slow
                  ? 'Slow connection to your workspace. Selfie upload may take longer. Keep the app open and wait for confirmation.'
                  : 'Workspace connection is responding normally.')
            : 'Connection quality will be checked when your workspace is reachable.',
        !_slow,
        required: false,
      ),
    );
    if (!native) return checks;
    final gps = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    final location =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    final precise =
        location &&
        await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.precise;
    if (_storageCheckedAt == null ||
        !_storageReady ||
        DateTime.now().difference(_storageCheckedAt!) >
            const Duration(minutes: 1)) {
      try {
        final directory = await getApplicationSupportDirectory();
        final probe = File('${directory.path}/.trackyu-storage-check');
        await probe.writeAsString('ready', flush: true);
        await probe.delete();
        _storageReady = true;
        _storageCheckedAt = DateTime.now();
      } catch (_) {
        _storageReady = false;
        /* Do not expose device paths in the setup screen. */
      }
    }
    // Use DB-driven OEM profile (fetched from server at login via DeviceOemProfile API).
    // Falls back to device brand detection if profile not yet loaded.
    final devInfo = await DutyTracker.deviceInfo();
    final autostartDone = devInfo['autostartSettingsOpened'] == true;
    final oem = _oemProfile;
    final brandDisplay = oem.displayName.isNotEmpty ? oem.displayName : 'PHONE';

    // Determine if autostart is required:
    // DB profile takes precedence; fallback to native brand detection.
    final requiresAutostart = oem.requiresAutostartSetting ||
        devInfo['requiresAutostart'] == true;

    // Battery instructions: use DB profile if available, else generic
    final batteryDetail = oem.batteryInstructions?.isNotEmpty == true
        ? '${oem.batteryInstructions} — prevents ${oem.oemUiName} from suspending GPS.'
        : 'Set battery to Unrestricted / No restrictions so GPS tracking is never suspended.';

    // Autostart instructions: use DB profile if available
    final autostartDetail = oem.autostartInstructions?.isNotEmpty == true
        ? oem.autostartInstructions!
        : 'Enable Auto-start in $brandDisplay settings so tracking stays active when screen is off.';

    checks.addAll([
      SetupCheck(
        SetupItem.camera,
        'Punch-in selfie camera',
        'Allow the camera to take a fresh selfie when you punch in.',
        await Permission.camera.isGranted,
        required: cameraRequired(),
      ),
      SetupCheck(
        SetupItem.gps,
        'Location services / GPS',
        'Keep device location switched on for attendance.',
        gps,
      ),
      SetupCheck(
        SetupItem.location,
        'Location permission',
        'Allow location while using Trackyu first.',
        location,
      ),
      SetupCheck(
        SetupItem.precise,
        'Precise location',
        'Enable precise location in the app location settings.',
        precise,
      ),
      SetupCheck(
        SetupItem.background,
        'Background location ("Allow all the time")',
        'Select "Allow all the time" in Settings. "Only while using app" freezes tracking when the phone is locked.',
        permission == LocationPermission.always,
        required: true,
      ),
      SetupCheck(
        SetupItem.battery,
        'Battery optimization ($brandDisplay)',
        batteryDetail,
        await Permission.ignoreBatteryOptimizations.isGranted,
        required: true,
      ),
      if (requiresAutostart)
        SetupCheck(
          SetupItem.autostart,
          'Auto-start permission ($brandDisplay)',
          autostartDetail,
          autostartDone,
          required: true,
        ),

      SetupCheck(
        SetupItem.notifications,
        'Notification permission',
        'Mandatory notification access to receive real-time store overstay alerts, work reminders, and team notices.',
        await Permission.notification.isGranted,
        required: true,
      ),
    ]);
    return checks;
  }

  @override
  Future<void> fix(SetupItem item) async {
    switch (item) {
      case SetupItem.gps:
        await Geolocator.openLocationSettings();
      case SetupItem.location:
        final status = await Permission.locationWhenInUse.status;
        if (status.isPermanentlyDenied || status.isRestricted) {
          await openAppSettings();
        } else {
          await Permission.locationWhenInUse.request();
        }
      case SetupItem.precise:
        await openAppSettings();
      case SetupItem.background:
        if (!await Permission.locationWhenInUse.isGranted) {
          await Permission.locationWhenInUse.request();
          return;
        }
        final status = await Permission.locationAlways.status;
        if (status.isPermanentlyDenied || status.isRestricted) {
          await openAppSettings();
        } else {
          await Permission.locationAlways.request();
          if (!await Permission.locationAlways.isGranted) {
            await openAppSettings();
          }
        }
      case SetupItem.battery:
        await DutyTracker.batterySettings(
          package: _oemProfile.batteryPackage,
          activity: _oemProfile.batteryActivity,
        );
      case SetupItem.autostart:
        await DutyTracker.autostartSettings(
          package: _oemProfile.autostartPackage,
          activity: _oemProfile.autostartActivity,
        );
      case SetupItem.notifications:
        final status = await Permission.notification.status;
        if (status.isPermanentlyDenied || status.isRestricted) {
          await openAppSettings();
        } else {
          final res = await Permission.notification.request();
          if (!res.isGranted) {
            await openAppSettings();
          }
        }
      case SetupItem.camera:
        final status = await Permission.camera.status;
        if (status.isPermanentlyDenied || status.isRestricted) {
          await openAppSettings();
        } else {
          await Permission.camera.request();
        }
      case SetupItem.network:
        if (native && defaultTargetPlatform == TargetPlatform.android) {
          await const MethodChannel(
            'trackyu/device_settings',
          ).invokeMethod<void>('network');
        } else if (native) {
          await openAppSettings();
        }
      case SetupItem.appVersion:
        _lastVersionCheckAt = null;
        try {
          final target = _downloadUrl.isNotEmpty
              ? _downloadUrl
              : 'https://trackyuweb.runasp.net/download';
          final uri = Uri.parse(target);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } catch (_) {
          try {
            await launchUrl(
              Uri.parse('https://trackyuweb.runasp.net/download'),
              mode: LaunchMode.externalApplication,
            );
          } catch (_) {}
        }
        break;
      case SetupItem.cloneApp:
        await openAppSettings();
        break;
      case SetupItem.storage:
      case SetupItem.server:
      case SetupItem.speed:
        _lastProbe = null;
        break;
    }
  }
}

// Merge plugin event streams without an additional dependency.
class StreamGroup {
  static Stream<bool> merge(List<Stream<bool>> streams) {
    late StreamController<bool> controller;
    final subscriptions = <StreamSubscription<bool>>[];
    controller = StreamController<bool>(
      onListen: () {
        for (final stream in streams) {
          subscriptions.add(
            stream.listen(
              (lost) => controller.add(lost),
              onError: (Object _, StackTrace __) => controller.add(false),
            ),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }
}

class DeviceReadiness extends ChangeNotifier with WidgetsBindingObserver {
  final ReadinessPlatform platform;
  DeviceReadiness(this.platform);
  List<SetupCheck> checks = [];
  bool checking = false, fixing = false, inspected = false, accepted = false;
  String? error;
  bool _disposed = false;
  Timer? _timer;
  StreamSubscription<bool>? _subscription;
  bool get ready =>
      inspected &&
      error == null &&
      checks.where((c) => c.required).every((c) => c.ready);
  bool get blocking => !ready || !accepted;
  bool get slowConnection =>
      checks.any((c) => c.item == SetupItem.speed && !c.ready);
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _subscription = platform.changes.listen((lost) {
      if (lost && !ready) accepted = false;
      notifyListeners();
      refresh();
    }, onError: (Object _) => refresh());
    _timer = Timer.periodic(const Duration(seconds: 25), (_) => refresh());
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
    if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
    if (state == AppLifecycleState.resumed) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 25), (_) => refresh());
    }
  }

  Future<void> refresh() async {
    if (_disposed || checking || fixing) return;
    checking = true;
    notifyListeners();
    try {
      final value = await platform.inspect();
      if (_disposed) return;
      checks = value;
      error = null;
      inspected = true;
      if (!ready) accepted = false;
    } catch (_) {
      if (_disposed) return;
      error = 'Unable to check device readiness. Please retry.';
      accepted = false;
    } finally {
      checking = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> fix(SetupItem item) async {
    if (fixing || _disposed) return;
    fixing = true;
    notifyListeners();
    String? failure;
    try {
      await platform.fix(item);
    } catch (_) {
      failure = 'Unable to open this setting. Check it in your phone settings.';
    } finally {
      fixing = false;
      if (!_disposed) {
        await refresh();
        if (failure != null && !_disposed) {
          error = failure;
          accepted = false;
          notifyListeners();
        }
      }
    }
  }

  void continueToApp() {
    if (!ready || fixing) return;
    accepted = true;
    notifyListeners();
  }

  void showChecklist() {
    accepted = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class SetupChecklist extends StatelessWidget {
  final DeviceReadiness monitor;
  final bool isDark;
  const SetupChecklist({super.key, required this.monitor, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xff0f172a) : const Color(0xfff8fafc);
    final cardBg = isDark ? const Color(0xff1e293b) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xff0f172a);
    final subColor = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);
    final dividerColor = isDark ? const Color(0xff334155) : const Color(0xffe2e8f0);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          'Start your workday',
          style: TextStyle(
            color: titleColor,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: dividerColor, height: 1),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            color: cardBg,
            border: Border(top: BorderSide(color: dividerColor, width: 1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: monitor.ready && !monitor.fixing
                    ? monitor.continueToApp
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff0284c7),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      isDark ? const Color(0xff1e293b) : const Color(0xffe2e8f0),
                  disabledForegroundColor:
                      isDark ? const Color(0xff64748b) : const Color(0xff94a3b8),
                  minimumSize: const Size.fromHeight(50),
                  elevation: monitor.ready ? 2 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue to Trackyu',
                      style: TextStyle(
                        color: monitor.ready
                            ? Colors.white
                            : (isDark ? const Color(0xff64748b) : const Color(0xff94a3b8)),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: monitor.ready
                          ? Colors.white
                          : (isDark ? const Color(0xff64748b) : const Color(0xff94a3b8)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: monitor.checking || monitor.fixing
                    ? null
                    : monitor.refresh,
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 17,
                  color: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),
                ),
                label: Text(
                  'Check again',
                  style: TextStyle(
                    color: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  side: BorderSide(
                    color: isDark ? const Color(0xff334155) : const Color(0xffcbd5e1),
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xff1e293b) : const Color(0xffeff6ff),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? const Color(0xff3b82f6).withValues(alpha: 0.3)
                            : const Color(0xffdbeafe),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.security_rounded,
                      size: 36,
                      color: isDark ? const Color(0xff60a5fa) : const Color(0xff2563eb),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Device setup checklist',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Essential permissions for real-time location & attendance verification.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: subColor,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                if (!monitor.inspected && monitor.error == null)
                  const LinearProgressIndicator(),
                if (monitor.error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      monitor.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                for (final check in monitor.checks.where((c) => c.required))
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: check.ready
                            ? dividerColor
                            : (isDark ? const Color(0xff7c2d12) : const Color(0xfffed7aa)),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xff102c4a).withValues(alpha: isDark ? 0.2 : 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: check.ready
                                    ? (isDark ? const Color(0xff064e3b) : const Color(0xffecfdf5))
                                    : (isDark ? const Color(0xff451a03) : const Color(0xfffff7ed)),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                check.ready
                                    ? Icons.check_rounded
                                    : Icons.priority_high_rounded,
                                size: 16,
                                color: check.ready
                                    ? (isDark ? const Color(0xff34d399) : const Color(0xff059669))
                                    : (isDark ? const Color(0xfffb923c) : const Color(0xffea580c)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                check.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: titleColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 34),
                          child: Text(
                            check.detail,
                            style: TextStyle(
                              color: subColor,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                        if (!check.ready)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: monitor.fixing
                                  ? null
                                  : () async {
                                      await monitor.fix(check.item);
                                    },
                              icon: const Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                              ),
                              label: Text(
                                check.item == SetupItem.appVersion
                                    ? 'Update Trackyu'
                                    : check.item == SetupItem.server ||
                                        check.item == SetupItem.speed ||
                                        check.item == SetupItem.storage
                                    ? 'Check again'
                                    : check.item == SetupItem.autostart
                                    ? 'Enable Auto-start'
                                    : check.item == SetupItem.battery
                                    ? 'Set to Unrestricted'
                                    : check.item == SetupItem.background
                                    ? 'Allow all the time'
                                    : check.item == SetupItem.cloneApp
                                    ? 'Open App Settings'
                                    : check.item == SetupItem.notifications
                                    ? 'Allow notifications'
                                    : 'Resolve',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
