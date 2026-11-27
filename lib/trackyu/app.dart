import 'work_departure_sheet.dart';
import 'gps_radar_loader.dart';
import 'manager_team_map_page.dart';

import 'gps_alert_service.dart';

import 'office_location_request.dart';

import 'profile_avatar.dart';

import 'theme_selector.dart';

import 'env_config.dart';

import 'monthly_goals_card.dart';

import 'dart:async';

import 'tracking_status.dart';

import 'visits.dart';

import 'network_speed.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'api.dart';

import 'user_feedback.dart';

import 'controller.dart';

import 'readiness.dart';

import 'workspace.dart';

import 'visuals.dart';

import 'attendance_summary.dart';

import 'field_location_card.dart';

import 'error_logger.dart';

import 'profile_page.dart';

import 'tracking_health_page.dart';

import 'apk_update_page.dart';

import 'apk_installer.dart';

import 'package:package_info_plus/package_info_plus.dart';



String formatToDdMmYyyy(dynamic dateOrStr) {

  if (dateOrStr == null) return '';

  final s = dateOrStr.toString().trim();

  if (s.isEmpty) return '';

  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);

  if (match != null) {

    final d = match.group(3)!.padLeft(2, '0');

    final m = match.group(2)!.padLeft(2, '0');

    final y = match.group(1)!;

    return '$d/$m/$y';

  }

  try {

    final dt = DateTime.parse(s);

    final d = dt.day.toString().padLeft(2, '0');

    final m = dt.month.toString().padLeft(2, '0');

    final y = dt.year.toString();

    return '$d/$m/$y';

  } catch (_) {

    return s;

  }

}



const trackyuBlue = Color(0xff2563eb);

String appVersion = 'v1.0.101-beta.10';

bool get isBetaVersion => appVersion.toLowerCase().contains('beta');



Future<String> resolveAppVersion() async {

  try {

    final info = await PackageInfo.fromPlatform();

    if (info.version.isNotEmpty) {

      appVersion = 'v${info.version}';

    }

  } catch (_) {}

  return appVersion;

}

String get apiBaseUrl => TrackyuEnv.apiBaseUrl;



class TrackyuApp extends StatefulWidget {

  final TrackyuController? controller;

  final DeviceReadiness? readiness;

  const TrackyuApp({super.key, this.controller, this.readiness});

  @override

  State<TrackyuApp> createState() => _TrackyuAppState();

}



class _TrackyuAppState extends State<TrackyuApp> {

  TrackyuController? controller;

  late Future<void> boot;

  DeviceReadiness? readiness;

  Timer? _versionCheckTimer;

  @override

  void initState() {

    super.initState();

    controller = widget.controller ?? TrackyuController(TrackyuApi(apiBaseUrl));

    controller!.addListener(_onControllerThemeChanged);

    boot = initialize();

    final phoneReadiness = widget.controller == null

        ? PhoneReadiness(

            controller!.api,

            offlineAllowed: () => controller!.loggedIn,

            cameraRequired: () =>

                !controller!.onDuty && !controller!.completed,

            getAppVersion: () => appVersion,

            getUserId: () => controller?.employeeId,

          )

        : null;

    // Inject into controller so it can update OEM profile after login

    if (phoneReadiness != null) {

      controller!.phoneReadiness = phoneReadiness;

    }

    readiness =

        widget.readiness ??

        (phoneReadiness != null ? DeviceReadiness(phoneReadiness) : null);

    readiness?.addListener(() {

      if (controller != null && readiness != null) {

        final isDown = readiness!.checks.any(

          (c) =>

              (c.item == SetupItem.network || c.item == SetupItem.server) &&

              !c.ready,

        );

        if (isDown) {

          controller!.setOffline(true);

        } else if (readiness!.ready && controller!.offline) {

          controller!.setOffline(false);

          controller!.syncData();

        }

      }

    });

    readiness?.start();

    _versionCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {

      if (mounted && controller != null && !controller!.offline && !isBetaVersion) {

        controller!.checkVersionPolicy(appVersion);

      }

    });

  }



  Future<void> initialize() async {

    await resolveAppVersion();

    await TrackyuEnv.initialize();

    if (controller != null) {

      try {

        controller!.api.baseUrl = TrackyuEnv.apiBaseUrl;

      } catch (_) {}

    } else {

      controller = widget.controller ?? TrackyuController(TrackyuApi(TrackyuEnv.apiBaseUrl));

    }

    await controller!.initialize().timeout(const Duration(seconds: 15));

    ErrorLogger.currentUserId = controller!.employeeId;

    if (!isBetaVersion) unawaited(controller!.checkVersionPolicy(appVersion));

  }



  void _onControllerThemeChanged() {

    if (mounted) setState(() {});

  }



  @override

  void dispose() {

    controller?.removeListener(_onControllerThemeChanged);

    if (widget.controller == null) controller?.dispose();

    readiness?.dispose();

    _versionCheckTimer?.cancel();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    final c = controller;

    final themeListenable = c?.themeModeNotifier ?? ValueNotifier<String>('beta');

    return ValueListenableBuilder<String>(

      valueListenable: themeListenable,

      builder: (context, activeTheme, _) {

        final isDark = activeTheme == 'dark' || activeTheme == 'amoled' || (c?.isDarkMode ?? false);

        return MaterialApp(

          title: 'Trackyu',

          navigatorKey: ErrorLogger.navigatorKey,

          scaffoldMessengerKey: ErrorLogger.messengerKey,

          builder: (context, child) {
            final bgDark = isDark || (c != null && c.themeBackgroundColor.computeLuminance() < 0.45);
            final content = readiness == null
                ? child!
                : AnimatedBuilder(
                    animation: readiness!,
                    builder: (_, _) => Stack(
                      children: [
                        child!,
                        if (readiness!.blocking)
                          Positioned.fill(
                            child: PopScope(
                              canPop: false,
                              child: SetupChecklist(
                                monitor: readiness!,
                                isDark: isDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: bgDark ? Brightness.light : Brightness.dark,
                statusBarBrightness: bgDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: isDark ? const Color(0xff0b0f19) : (c?.themeBackgroundColor ?? Colors.white),
                systemNavigationBarIconBrightness: bgDark ? Brightness.light : Brightness.dark,
              ),
              child: content,
            );
          },

          debugShowCheckedModeBanner: false,

          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,

          theme: ThemeData(

            useMaterial3: true,

            brightness: Brightness.light,

            colorScheme: ColorScheme.fromSeed(

              seedColor: c?.themePrimaryColor ?? const Color(0xff6366f1),

              primary: c?.themePrimaryColor ?? const Color(0xff6366f1),

              surface: Colors.white,

              brightness: Brightness.light,

            ),

            scaffoldBackgroundColor: c?.themeBackgroundColor ?? const Color(0xfff3f6fc),

            appBarTheme: AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: (isDark || (c?.themeBackgroundColor != null && c!.themeBackgroundColor.computeLuminance() < 0.45))
                    ? Brightness.light
                    : Brightness.dark,
                statusBarBrightness: (isDark || (c?.themeBackgroundColor != null && c!.themeBackgroundColor.computeLuminance() < 0.45))
                    ? Brightness.dark
                    : Brightness.light,
                systemNavigationBarColor: c?.themeBackgroundColor ?? const Color(0xfff3f6fc),
                systemNavigationBarIconBrightness: (isDark || (c?.themeBackgroundColor != null && c!.themeBackgroundColor.computeLuminance() < 0.45))
                    ? Brightness.light
                    : Brightness.dark,
              ),
              backgroundColor: c?.themeBackgroundColor ?? const Color(0xfff3f6fc),

              foregroundColor: (isDark || (c?.themeBackgroundColor != null && c!.themeBackgroundColor.computeLuminance() < 0.45)) ? Colors.white : const Color(0xff0f172a),

              iconTheme: IconThemeData(

                color: (isDark || (c?.themeBackgroundColor != null && c!.themeBackgroundColor.computeLuminance() < 0.45)) ? Colors.white : const Color(0xff0f172a),

              ),

              actionsIconTheme: IconThemeData(

                color: (isDark || (c?.themeBackgroundColor != null && c!.themeBackgroundColor.computeLuminance() < 0.45)) ? Colors.white : const Color(0xff0f172a),

              ),

              titleTextStyle: TextStyle(

                color: (isDark || (c?.themeBackgroundColor != null && c!.themeBackgroundColor.computeLuminance() < 0.45)) ? Colors.white : const Color(0xff0f172a),

                fontSize: 18,

                fontWeight: FontWeight.bold,

              ),

              elevation: 0,

              scrolledUnderElevation: 0,

            ),

            cardTheme: CardThemeData(

              color: Colors.white,

              elevation: 0,

              shape: RoundedRectangleBorder(

                borderRadius: BorderRadius.circular(22),

                side: BorderSide(

                  color: (c?.themePrimaryColor ?? const Color(0xff6366f1)).withValues(alpha: 0.18),

                  width: 1.2,

                ),

              ),

            ),

            filledButtonTheme: FilledButtonThemeData(

              style: FilledButton.styleFrom(

                backgroundColor: c?.themePrimaryColor ?? const Color(0xff6366f1),

                foregroundColor: Colors.white,

                shape: RoundedRectangleBorder(

                  borderRadius: BorderRadius.circular(9999),

                ),

              ),

            ),

            inputDecorationTheme: InputDecorationTheme(

              filled: true,

              fillColor: Colors.white,

              contentPadding: const EdgeInsets.symmetric(

                horizontal: 18,

                vertical: 19,

              ),

              labelStyle: const TextStyle(color: Color(0xff64748b)),

              prefixIconColor: c?.themePrimaryColor ?? const Color(0xff6366f1),

              enabledBorder: OutlineInputBorder(

                borderRadius: BorderRadius.circular(18),

                borderSide: BorderSide(

                  color: (c?.themePrimaryColor ?? const Color(0xff6366f1)).withValues(alpha: 0.2),

                ),

              ),

              focusedBorder: OutlineInputBorder(

                borderRadius: BorderRadius.circular(18),

                borderSide: BorderSide(

                  color: c?.themePrimaryColor ?? const Color(0xff6366f1),

                  width: 1.5,

                ),

              ),

              border: OutlineInputBorder(

                borderRadius: BorderRadius.circular(18),

              ),

            ),

          ),

          darkTheme: ThemeData(

            useMaterial3: true,

            brightness: Brightness.dark,

            colorScheme: ColorScheme.fromSeed(

              seedColor: trackyuBlue,

              primary: const Color(0xff26c6da),

              brightness: Brightness.dark,

            ),

            scaffoldBackgroundColor: c?.themeBackgroundColor ?? const Color(0xff0b0f19),

            appBarTheme: AppBarTheme(
              systemOverlayStyle: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
                systemNavigationBarColor: Color(0xff0b0f19),
                systemNavigationBarIconBrightness: Brightness.light,
              ),
              backgroundColor: c?.themeBackgroundColor ?? const Color(0xff0b0f19),

              foregroundColor: Colors.white,

              iconTheme: const IconThemeData(color: Colors.white),

              actionsIconTheme: const IconThemeData(color: Colors.white),

              titleTextStyle: const TextStyle(

                color: Colors.white,

                fontSize: 18,

                fontWeight: FontWeight.bold,

              ),

              elevation: 0,

              scrolledUnderElevation: 0,

            ),

            cardTheme: const CardThemeData(color: Color(0xff1e1e1e)),

            inputDecorationTheme: InputDecorationTheme(

              filled: true,

              fillColor: const Color(0xff1e1e1e),

              contentPadding: const EdgeInsets.symmetric(

                horizontal: 18,

                vertical: 19,

              ),

              labelStyle: const TextStyle(color: Color(0xff94a3b8)),

              prefixIconColor: Color(0xff26c6da),

              enabledBorder: OutlineInputBorder(

                borderRadius: BorderRadius.circular(16),

                borderSide: const BorderSide(color: Color(0xff2d3135)),

              ),

              focusedBorder: OutlineInputBorder(

                borderRadius: BorderRadius.circular(16),

                borderSide: const BorderSide(

                  color: Color(0xff26c6da),

                  width: 1.5,

                ),

              ),

              border: OutlineInputBorder(

                borderRadius: BorderRadius.circular(16),

              ),

            ),

          ),

          home: FutureBuilder<void>(

            future: boot,

            builder: (context, snapshot) {

              if (snapshot.hasError) {

                return Scaffold(

                  body: Center(

                    child: Padding(

                      padding: const EdgeInsets.all(24),

                      child: Column(

                        mainAxisSize: MainAxisSize.min,

                        children: [

                          const Icon(

                            Icons.refresh_rounded,

                            color: trackyuBlue,

                            size: 36,

                          ),

                          const SizedBox(height: 16),

                          const Text(

                            'Unable to open your workspace. Please try again.',

                            textAlign: TextAlign.center,

                          ),

                          const SizedBox(height: 20),

                          FilledButton(

                            onPressed: () {

                              setState(() {

                                boot = initialize();

                              });

                            },

                            child: const Text('Try again'),

                          ),

                        ],

                      ),

                    ),

                  ),

                );

              }

              if (snapshot.connectionState != ConnectionState.done) {

                return const Scaffold(

                  body: Center(child: CircularProgressIndicator()),

                );

              }

              return AnimatedBuilder(

                animation: controller!,

                builder: (_, _) {

                  if (controller!.versionBlocked) {

                    return ApkUpdateRequiredPage(

                      controller: controller!,

                      isDark: isDark,

                    );

                  }

                  return controller!.loggedIn

                      ? AttendancePage(

                          controller: controller!,

                          openSetup: readiness?.showChecklist,

                        )

                      : LegacyLogin(controller: controller!);

                },

              );

            },

          ),

        );

      },

    );

  }

}



Future<void> showFailure(BuildContext context, Object error) {

  final errStr = error.toString().toLowerCase();

  final isUserTypoOrAuth = errStr.contains('invalid_credentials') ||

      errStr.contains('password') ||

      errStr.contains('credential') ||

      errStr.contains('username') ||

      errStr.contains('unauthorized') ||

      errStr.contains('login') ||

      errStr.contains('user not found') ||

      errStr.contains('wrong password');



  if (!isUserTypoOrAuth) {

    ErrorLogger.record(error, StackTrace.current, context: 'showFailure', notifyUser: false);

  }

  final displayMessage = userFriendlyErrorMessage(error);

  final isDark = Theme.of(context).brightness == Brightness.dark;



  return showDialog<void>(

    context: context,

    builder: (context) => AlertDialog(

      backgroundColor: isDark ? const Color(0xff0f172a) : Colors.white,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),

      title: Row(

        children: [

          Container(

            padding: const EdgeInsets.all(7),

            decoration: BoxDecoration(

              color: isDark ? const Color(0xff3b240f) : const Color(0xfffef3c7),

              borderRadius: BorderRadius.circular(10),

            ),

            child: const Icon(

              Icons.info_outline_rounded,

              color: Color(0xffd97706),

              size: 22,

            ),

          ),

          const SizedBox(width: 10),

          Text(

            'Notice',

            style: TextStyle(

              fontSize: 16,

              fontWeight: FontWeight.bold,

              color: isDark ? Colors.white : const Color(0xff0f172a),

            ),

          ),

        ],

      ),

      content: Text(

        displayMessage,

        style: TextStyle(

          fontSize: 14,

          height: 1.45,

          color: isDark ? const Color(0xffcbd5e1) : const Color(0xff334155),

        ),

      ),

      actions: [

        FilledButton(

          style: FilledButton.styleFrom(

            backgroundColor: const Color(0xff0284c7),

            foregroundColor: Colors.white,

            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),

            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),

          ),

          onPressed: () => Navigator.pop(context),

          child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w600)),

        ),

      ],

    ),

  );

}



class LegacyLogin extends StatefulWidget {

  final TrackyuController controller;

  const LegacyLogin({super.key, required this.controller});

  @override

  State<LegacyLogin> createState() => _LegacyLoginState();

}



class _LegacyLoginState extends State<LegacyLogin> {

  final form = GlobalKey<FormState>();

  final username = TextEditingController(), password = TextEditingController();

  bool busy = false, obscure = true;

  bool deviceBlocked = false;

  String? deviceMessage;

  Future<void> deviceAction({bool status = false}) async {

    if (busy || !form.currentState!.validate()) return;

    setState(() => busy = true);

    try {

      String? reason;

      if (!status) {

        var text = '';

        final reasonForm = GlobalKey<FormState>();

        reason = await showDialog<String>(

          context: context,

          builder: (context) => AlertDialog(

            title: const Text('Request a phone change'),

            content: Form(

              key: reasonForm,

              child: TextFormField(

                autofocus: true,

                maxLines: 3,

                maxLength: 1000,

                onChanged: (v) => text = v,

                decoration: const InputDecoration(labelText: 'Reason'),

                validator: (v) => (v?.trim().length ?? 0) < 3

                    ? 'Enter a reason (at least 3 characters)'

                    : null,

              ),

            ),

            actions: [

              TextButton(

                onPressed: () => Navigator.pop(context),

                child: const Text('Cancel'),

              ),

              FilledButton(

                onPressed: () {

                  if (reasonForm.currentState!.validate()) {

                    Navigator.pop(context, text.trim());

                  }

                },

                child: const Text('Send request'),

              ),

            ],

          ),

        );

        if (reason == null) return;

      }

      final response = await widget.controller.api.deviceChange(

        username.text,

        password.text,

        reason: reason,

      );

      if (!mounted) return;

      setState(

        () => deviceMessage = response['status'] == 'Approved'

            ? 'Device change approved! Please sign in to link this device.'

            : response['status'] == 'Rejected'

            ? 'Request rejected: ${response['reviewNote'] ?? 'Please contact your administrator.'}'

            : response['status'] == 'None'

            ? 'No device change request has been submitted from this phone.'

            : 'Request #${response['id']} is pending administrator review and approval.',

      );

    } catch (e) {

      if (mounted) await showFailure(context, e);

    } finally {

      if (mounted) setState(() => busy = false);

    }

  }



  @override

  void dispose() {

    username.dispose();

    password.dispose();

    super.dispose();

  }



  Future<void> login() async {

    if (busy || !form.currentState!.validate()) return;

    setState(() {

      busy = true;

      deviceBlocked = false;

      deviceMessage = null;

    });

    try {

      await widget.controller.login(username.text, password.text);

    } catch (e) {

      if (mounted) {

        if (e is ApiFailure && e.code == 'DEVICE_CHANGE_REQUIRED') {

          setState(() {

            deviceBlocked = true;

            deviceMessage = 'Your account is linked to another device. Please tap "Request device change" below to link this phone.';

          });

        } else {

          await showFailure(context, e);

        }

      }

    } finally {

      if (mounted) setState(() => busy = false);

    }

  }



  @override

  Widget build(BuildContext context) {

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(

      backgroundColor: isDark ? const Color(0xff121212) : const Color(0xfff3f6fb),

      appBar: AppBar(

        backgroundColor: Colors.transparent,

        elevation: 0,

        actions: [

          Container(

            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),

            margin: const EdgeInsets.symmetric(vertical: 10),

            decoration: BoxDecoration(

              color: (TrackyuEnv.activeKey == 'prod' ? const Color(0xff16a34a) : const Color(0xff6366f1)).withValues(alpha: 0.15),

              border: Border.all(

                color: (TrackyuEnv.activeKey == 'prod' ? const Color(0xff16a34a) : const Color(0xff6366f1)).withValues(alpha: 0.4),

              ),

              borderRadius: BorderRadius.circular(16),

            ),

            child: Row(

              mainAxisSize: MainAxisSize.min,

              children: [

                Icon(

                  Icons.dns_rounded,

                  size: 14,

                  color: TrackyuEnv.activeKey == 'prod' ? const Color(0xff16a34a) : const Color(0xff6366f1),

                ),

                const SizedBox(width: 4),

                Text(

                  TrackyuEnv.current.displayName,

                  style: TextStyle(

                    fontSize: 12,

                    fontWeight: FontWeight.w700,

                    color: TrackyuEnv.activeKey == 'prod' ? const Color(0xff16a34a) : const Color(0xff6366f1),

                  ),

                ),

              ],

            ),

          ),

          IconButton(

            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',

            icon: Icon(

              isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,

              color: isDark ? const Color(0xffe2e8f0) : const Color(0xff475569),

            ),

            onPressed: () => widget.controller.toggleDarkMode(),

          ),

          const SizedBox(width: 8),

        ],

      ),

      body: SafeArea(

        child: LayoutBuilder(

          builder: (context, constraints) => Center(

            child: ConstrainedBox(

              constraints: const BoxConstraints(maxWidth: 460),

              child: AutofillGroup(

                child: Form(

                  key: form,

                  child: ListView(

                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),

                    children: [

                      const LoginMasthead(),

                      const SizedBox(height: 30),

                      Text(

                        'Welcome back',

                        style: TextStyle(

                          fontSize: 27,

                          color: isDark ? Colors.white : const Color(0xff102c4a),

                          fontWeight: FontWeight.w700,

                          letterSpacing: -.7,

                        ),

                      ),

                      const SizedBox(height: 7),

                      Text(

                        'Your day starts here. Sign in to your workspace.',

                        style: TextStyle(

                          color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),

                          height: 1.5,

                        ),

                      ),

                      const SizedBox(height: 24),

                    TextFormField(

                      controller: username,

                      enabled: !busy,

                      autofillHints: const [AutofillHints.username],

                      textInputAction: TextInputAction.next,

                      autocorrect: false,

                      enableSuggestions: false,

                      decoration: const InputDecoration(

                        labelText: 'User name',

                        prefixIcon: Icon(Icons.person_outline, size: 21),

                      ),

                      validator: (v) => v == null || v.trim().isEmpty

                          ? 'Enter your user name'

                          : null,

                    ),

                    const SizedBox(height: 18),

                    TextFormField(

                      controller: password,

                      enabled: !busy,

                      obscureText: obscure,

                      autofillHints: const [AutofillHints.password],

                      textInputAction: TextInputAction.done,

                      onFieldSubmitted: (_) => login(),

                      decoration: InputDecoration(

                        labelText: 'Password',

                        prefixIcon: const Icon(Icons.lock_outline, size: 21),

                        suffixIcon: IconButton(

                          onPressed: busy

                              ? null

                              : () => setState(() => obscure = !obscure),

                          tooltip: obscure ? 'Show password' : 'Hide password',

                          icon: Icon(

                            obscure

                                ? Icons.visibility_outlined

                                : Icons.visibility_off_outlined,

                            size: 21,

                          ),

                        ),

                      ),

                      validator: (v) =>

                          v == null || v.isEmpty ? 'Enter your password' : null,

                    ),

                    const SizedBox(height: 24),

                    FilledButton(

                      onPressed: busy ? null : login,

                      style: FilledButton.styleFrom(

                        minimumSize: const Size.fromHeight(56),

                        backgroundColor: trackyuBlue,

                        foregroundColor: Colors.white,

                        shape: RoundedRectangleBorder(

                          borderRadius: BorderRadius.circular(16),

                        ),

                      ),

                      child: busy

                          ? const SizedBox(

                              width: 22,

                              height: 22,

                              child: CircularProgressIndicator(

                                color: Colors.white,

                                strokeWidth: 2,

                              ),

                            )

                          : const Row(

                              mainAxisAlignment: MainAxisAlignment.center,

                              children: [

                                Text(

                                  'Login',

                                  style: TextStyle(

                                    fontSize: 16,

                                    fontWeight: FontWeight.w600,

                                  ),

                                ),

                                SizedBox(width: 12),

                                Icon(Icons.arrow_forward_rounded, size: 20),

                              ],

                            ),

                    ),

                    if (deviceBlocked) ...[

                      const SizedBox(height: 18),

                      Text(

                        deviceMessage ??

                            'Administrator approval is required for this phone.',

                        style: const TextStyle(color: Color(0xff9a5a12)),

                      ),

                      Wrap(

                        spacing: 8,

                        runSpacing: 8,

                        children: [

                          TextButton(

                            onPressed: busy ? null : () => deviceAction(),

                            child: const Text('Request device change'),

                          ),

                          TextButton(

                            onPressed: busy

                                ? null

                                : () => deviceAction(status: true),

                            child: const Text('Check request status'),

                          ),

                        ],

                      ),

                    ],

                    const SizedBox(height: 26),

                    Row(

                      mainAxisAlignment: MainAxisAlignment.center,

                      children: [

                        const Icon(

                          Icons.lock_outline_rounded,

                          size: 14,

                          color: Color(0xff8292a6),

                        ),

                        const SizedBox(width: 7),

                        Flexible(

                          child: Text(

                            isBetaVersion ? 'Trackyu $appVersion • BETA TESTING' : 'Trackyu $appVersion • ${TrackyuEnv.current.displayName}',

                            textAlign: TextAlign.center,

                            style: const TextStyle(

                              fontSize: 12,

                              fontWeight: FontWeight.w600,

                              color: Color(0xff8292a6),

                            ),

                          ),

                        ),

                      ],

                    ),

                  ],

                ),

              ),

            ),

          ),

        ),

      ),

    ),

  );

  }

}



class AttendancePage extends StatefulWidget {

  final TrackyuController controller;

  final VoidCallback? openSetup;

  const AttendancePage({super.key, required this.controller, this.openSetup});

  @override

  State<AttendancePage> createState() => _AttendancePageState();

}



class _AttendancePageState extends State<AttendancePage>

    with WidgetsBindingObserver {

  bool busy = false;

  Timer? _cutoffCheck;

  late final NetworkQualityMonitor network;

  TrackyuController get c => widget.controller;

  DateTime? _lastAutoSync;



  void _onNetworkQualityChanged() {

    if (network.status.isOnline && !busy && !c.isSyncing) {

      _autoSyncIfOnline();

    }

  }



  void _autoSyncIfOnline() {

    if (!mounted || busy || c.isSyncing) return;

    final now = DateTime.now();

    if (_lastAutoSync != null && now.difference(_lastAutoSync!).inSeconds < 8) {

      return;

    }

    if (!network.status.isOnline) return;

    _lastAutoSync = now;

    c.syncData().then((_) {

      if (mounted) setState(() {});

    }).catchError((_) {});

  }



  @override

  void initState() {

    super.initState();

    network = NetworkQualityMonitor.instance(c.api)..start();

    network.addListener(_onNetworkQualityChanged);

    WidgetsBinding.instance.addObserver(this);

    _cutoffCheck = Timer.periodic(const Duration(seconds: 15), (_) {

      if (c.dutyCutoffReached && !busy) run(c.checkDutyCutoff);

      if (c.workDate != c.localDay || (c.attendance != null && !c.isAttendanceToday && !c.onDuty)) {

        c.checkDayChangeAndCutoff();

      }

    });

    c.addListener(_checkAndPromptUpdate);

    c.addListener(_checkAndPromptPunchIn);

    GpsAlertService.instance.start(

      controller: widget.controller,

      contextProvider: () => mounted ? context : null,

    );

    WidgetsBinding.instance.addPostFrameCallback((_) {

      _checkAndPromptUpdate();

      _autoSyncIfOnline();

      _checkAndPromptPunchIn();

    });

  }



  static bool _promptedThisSession = false;

  static bool _promptedPunchInThisSession = false;



  void _checkAndPromptPunchIn() {

    if (!mounted || busy || _promptedPunchInThisSession) return;

    if (ModalRoute.of(context)?.isCurrent != true) return;

    if (c.onDuty || c.completed || c.attendance != null) {

      _promptedPunchInThisSession = true;

      return;

    }

    if (c.stateKnown && !c.onDuty && !c.completed && c.attendance == null) {

      _promptedPunchInThisSession = true;

      Future<void>.delayed(const Duration(milliseconds: 600), () {

        if (!mounted || busy || c.onDuty || c.completed || c.attendance != null) return;

        if (ModalRoute.of(context)?.isCurrent != true) return;

        _showPunchInPromptSheet();

      });

    }

  }



  void _showPunchInPromptSheet() {

    if (!mounted || busy || c.onDuty || c.completed || c.attendance != null) return;

    if (ModalRoute.of(context)?.isCurrent != true) return;

    final isDark = c.isDarkMode;

    final isBeta = c.isBetaMode;

    final empName = c.name.trim();

    showModalBottomSheet<void>(

      context: context,

      isScrollControlled: true,

      backgroundColor: Colors.transparent,

      builder: (ctx) {

        return Container(

          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),

          decoration: BoxDecoration(

            color: isDark ? const Color(0xff161b22) : Colors.white,

            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),

            border: isBeta

                ? const Border(top: BorderSide(color: Color(0xffede9fe), width: 1.5))

                : null,

            boxShadow: [

              BoxShadow(

                color: isBeta

                    ? const Color(0xff6366f1).withValues(alpha: 0.12)

                    : Colors.black.withValues(alpha: 0.35),

                blurRadius: 24,

                offset: const Offset(0, -6),

              ),

            ],

          ),

          child: Column(

            mainAxisSize: MainAxisSize.min,

            children: [

              Container(

                width: 44,

                height: 4,

                decoration: BoxDecoration(

                  color: isDark ? const Color(0xff30363d) : (isBeta ? const Color(0xffcbd5e1) : const Color(0xffe2e8f0)),

                  borderRadius: BorderRadius.circular(4),

                ),

              ),

              const SizedBox(height: 20),

              Container(

                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(

                  gradient: LinearGradient(

                    colors: isBeta

                        ? const [Color(0xff818cf8), Color(0xff6366f1)]

                        : const [Color(0xfff97316), Color(0xffea580c)],

                    begin: Alignment.topLeft,

                    end: Alignment.bottomRight,

                  ),

                  shape: BoxShape.circle,

                  boxShadow: [

                    BoxShadow(

                      color: (isBeta ? const Color(0xff6366f1) : const Color(0xfff97316)).withValues(alpha: 0.35),

                      blurRadius: 16,

                      offset: const Offset(0, 6),

                    ),

                  ],

                ),

                child: const Icon(

                  Icons.alarm_on_rounded,

                  size: 34,

                  color: Colors.white,

                ),

              ),

              const SizedBox(height: 16),

              Text(

                'Good Day! Start Your Work',

                style: TextStyle(

                  fontSize: 19,

                  fontWeight: FontWeight.w800,

                  color: isDark ? Colors.white : (isBeta ? const Color(0xff1e1b4b) : const Color(0xff0f172a)),

                  letterSpacing: -0.3,

                ),

              ),

              const SizedBox(height: 8),

              Text(

                empName.isNotEmpty

                    ? 'Welcome $empName! Your shift attendance is not recorded yet. Please punch in to start live location tracking, route recording, and client visits.'

                    : 'Your shift attendance is not recorded yet. Please punch in to start live location tracking, route recording, and client visits.',

                textAlign: TextAlign.center,

                style: TextStyle(

                  fontSize: 13.5,

                  height: 1.45,

                  color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),

                ),

              ),

              const SizedBox(height: 24),

              SizedBox(

                width: double.infinity,

                height: 48,

                child: FilledButton.icon(

                  onPressed: () {

                    Navigator.pop(ctx);

                    punch();

                  },

                  icon: const Icon(Icons.camera_alt_rounded, size: 20),

                  label: const Text(

                    'Punch In Now (Selfie & GPS)',

                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),

                  ),

                  style: FilledButton.styleFrom(

                    backgroundColor: c.isLuxuryMode ? c.themePrimaryColor : (isBeta ? const Color(0xff6366f1) : const Color(0xfff97316)),

                    foregroundColor: Colors.white,

                    shape: RoundedRectangleBorder(

                      borderRadius: BorderRadius.circular(isBeta ? 9999 : 14),

                    ),

                  ),

                ),

              ),

              const SizedBox(height: 10),

              SizedBox(

                width: double.infinity,

                child: TextButton(

                  onPressed: () => Navigator.pop(ctx),

                  child: Text(

                    'Later (View Dashboard)',

                    style: TextStyle(

                      fontSize: 13.5,

                      color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),

                    ),

                  ),

                ),

              ),

            ],

          ),

        );

      },

    );

  }



  void _checkAndPromptUpdate() {

    if (isBetaVersion) return; // Beta testing track: completely bypass update dialogs

    if (!mounted || c.versionPolicy == null) return;

    final currentClean = appVersion.replaceAll(RegExp(r'^[vV]'), '').trim();

    final defaultClean = (c.versionPolicy!['defaultVersion']?.toString() ?? '').replaceAll(RegExp(r'^[vV]'), '').trim();

    if (currentClean.isNotEmpty && defaultClean.isNotEmpty && compareVersions(currentClean, defaultClean) >= 0) {

      // User is running the latest default version; never show update prompt

      return;

    }

    final isForce = c.versionBlocked || c.versionPolicy!['forceUpdate'] == true || c.versionPolicy!['isAllowed'] == false;

    final isDefault = c.versionPolicy!['isDefault'] == true;

    if (!isDefault || isForce) {

      if (isForce || !_promptedThisSession) {

        _promptedThisSession = true;

        ApkInstaller.showUpdatePopup(context, controller: c, force: isForce);

      }

    }

  }



  @override

  void dispose() {

    network.removeListener(_onNetworkQualityChanged);

    c.removeListener(_checkAndPromptUpdate);

    c.removeListener(_checkAndPromptPunchIn);

    _cutoffCheck?.cancel();

    GpsAlertService.instance.stop();

    network.stop();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();

  }



  @override

  void didChangeAppLifecycleState(AppLifecycleState state) {

    if (state == AppLifecycleState.resumed && !busy) {

      if ((c.workDate.isEmpty || c.workDate != c.localDay || (c.attendance != null && !c.isAttendanceToday)) && !c.onDuty) {

        c.attendance = null;

        c.activeVisit = null;

        c.workDate = c.localDay;

        c.notifyListeners();

      }

      c.refresh().catchError((_) {});

      _autoSyncIfOnline();

    }

  }



  Future<void> run(Future<void> Function() action) async {

    if (busy) return;

    setState(() => busy = true);

    try {

      await action().timeout(

        const Duration(seconds: 35),

        onTimeout: () {

          throw const ApiFailure(

            'OPERATION_TIMEOUT',

            'Attendance request timed out. Please retry.',

          );

        },

      );

    } catch (e) {

      if (mounted) await showFailure(context, e);

    } finally {

      if (mounted) setState(() => busy = false);

    }

  }



  Future<String?> reason(bool early) async {

    var text = '';

    final form = GlobalKey<FormState>();

    final value = await showDialog<String>(

      context: context,

      builder: (context) => AlertDialog(

        title: Text(

          early ? 'Early punch-out reason' : 'Late attendance reason',

        ),

        content: Form(

          key: form,

          child: TextFormField(

            onChanged: (value) => text = value,

            autofocus: true,

            minLines: 2,

            maxLines: 5,

            maxLength: 1000,

            decoration: const InputDecoration(labelText: 'Reason'),

            validator: (v) =>

                v == null || v.trim().isEmpty ? 'Please enter a reason' : null,

          ),

        ),

        actions: [

          TextButton(

            onPressed: () => Navigator.pop(context),

            child: const Text('Cancel'),

          ),

          FilledButton(

            onPressed: () {

              if (form.currentState!.validate()) {

                Navigator.pop(context, text.trim());

              }

            },

            child: const Text('Submit'),

          ),

        ],

      ),

    );

    return value;

  }



  Future<void> syncNow() async {

    if (busy) return;

    setState(() => busy = true);

    try {

      final success = await c.syncData();

      if (mounted) {

        final message = success

            ? 'Data synced successfully with workspace!'

            : (c.notice.isNotEmpty ? c.notice : 'Data saved locally on phone.');

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(

            content: Row(

              children: [

                Icon(

                  success ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,

                  color: Colors.white,

                  size: 20,

                ),

                const SizedBox(width: 10),

                Expanded(

                  child: Text(

                    message,

                    style: const TextStyle(

                      fontSize: 13,

                      fontWeight: FontWeight.w500,

                    ),

                  ),

                ),

              ],

            ),

            backgroundColor: success

                ? const Color(0xff059669)

                : const Color(0xff1e40af),

            behavior: SnackBarBehavior.floating,

            shape: RoundedRectangleBorder(

              borderRadius: BorderRadius.circular(10),

            ),

            duration: const Duration(seconds: 3),

          ),

        );

      }

    } finally {

      if (mounted) setState(() => busy = false);

    }

  }



  Future<void> punch() async {

    if (busy) return;

    setState(() => busy = true);

    try {

      if (c.onDuty) {
        final duration = c.workingDuration;
        if (duration != null && duration < const Duration(minutes: 5)) {
          final secs = duration.inSeconds % 60;
          final mins = duration.inMinutes;
          final timeStr = mins > 0 ? '$mins min $secs sec' : '$secs seconds';
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text('Work Cooldown Active'),
              content: Text(
                'You started work just $timeStr ago.\n\nTo prevent accidental check-outs and protect your shift data, a minimum 5-minute work duration is required before working out.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Understood'),
                ),
              ],
            ),
          );
          return;
        }

        // Show comprehensive Workday Departure Sheet
        final choice = await showWorkOutDepartureSheet(context: context, controller: c);
        if (choice == 'checkout_visit') {
          final data = VisitsData(c);
          await data.load();
          if (mounted && c.activeVisit != null) {
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => VisitForm(data: data, visit: c.activeVisit!),
              ),
            );
          }
          return;
        }
        if (choice != 'confirm_work_out') {
          return;
        }
      }
      final photo = await c.takeSelfie();

      if (photo == null) return;

      if (c.onDuty) {

        await c.saveOutSelfie(photo);

      }

      try {

        await c.punch(selfieBase64: photo);

      } on ApiFailure catch (e) {

        if (e.code != 'LATE_REASON_REQUIRED' &&

            e.code != 'EARLY_REASON_REQUIRED') {

          final isAuthFailure = e.status == 401 ||
              e.status == 403 ||
              e.code == 'UNAUTHORIZED' ||
              e.code == 'SESSION_ACCESS_REQUIRED' ||
              e.code == 'DEVICE_SESSION_INVALID' ||
              e.code == 'DEVICE_SESSION_REVOKED' ||
              c.api.sessionRejected;
          rethrow;

        }

        if (!mounted) return;

        final answer = await reason(e.code == 'EARLY_REASON_REQUIRED');

        if (answer != null) {

          await c.punch(reason: answer, selfieBase64: c.onDuty ? null : photo);

        }

      }

    } catch (e) {

      if (mounted) await showFailure(context, e);

    } finally {

      if (mounted) setState(() => busy = false);

    }

  }

  String clock(dynamic value) {

    final time = DateTime.tryParse(value?.toString() ?? '')?.toLocal();

    return time == null

        ? (c.stateKnown ? 'Not yet' : '--:--')

        : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  }



  Widget timeCard(String label, dynamic value, IconData icon, Color tone) {

    final hasValue = value != null;

    return Expanded(

      child: Container(

        padding: const EdgeInsets.all(16),

        decoration: BoxDecoration(

          color: Colors.white,

          borderRadius: BorderRadius.circular(20),

          border: Border.all(

            color: hasValue

                ? tone.withValues(alpha: 0.25)

                : const Color(0xffe2e8f0),

            width: hasValue ? 1.2 : 1.0,

          ),

          boxShadow: [

            BoxShadow(

              color: const Color(0xff102c4a).withValues(alpha: 0.03),

              blurRadius: 10,

              offset: const Offset(0, 3),

            ),

          ],

        ),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Row(

              mainAxisAlignment: MainAxisAlignment.spaceBetween,

              children: [

                Container(

                  padding: const EdgeInsets.all(7),

                  decoration: BoxDecoration(

                    color: tone.withValues(alpha: 0.1),

                    borderRadius: BorderRadius.circular(10),

                  ),

                  child: Icon(icon, size: 18, color: tone),

                ),

                if (hasValue)

                  Container(

                    width: 7,

                    height: 7,

                    decoration: BoxDecoration(

                      color: tone,

                      shape: BoxShape.circle,

                    ),

                  ),

              ],

            ),

            const SizedBox(height: 12),

            Text(

              label.toUpperCase(),

              style: const TextStyle(

                color: Color(0xff64748b),

                fontSize: 11,

                fontWeight: FontWeight.w600,

                letterSpacing: 0.8,

              ),

            ),

            const SizedBox(height: 4),

            Text(

              hasValue ? clock(value) : '— : —',

              style: TextStyle(

                color: hasValue

                    ? const Color(0xff0f172a)

                    : const Color(0xff94a3b8),

                fontSize: 22,

                fontWeight: FontWeight.w700,

                letterSpacing: -0.8,

              ),

            ),

          ],

        ),

      ),

    );

  }



  
  Widget _buildActiveWorkSessionBar(
    BuildContext context,
    TrackyuController c,
    bool canPunch,
    bool busy,
  ) {
    final isDark = c.isDarkMode;
    final duration = c.workingDuration ?? Duration.zero;
    final hours = duration.inHours;
    final mins = duration.inMinutes % 60;
    final timeStr = '${hours}h ${mins.toString().padLeft(2, '0')}m';
    final isUnder9h = hours < 9;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff161b22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? const Color(0xff30363d)
              : const Color(0xffe2e8f0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xff10b981).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.work_history_rounded,
              color: Color(0xff10b981),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xff10b981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Daily Duty Active',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xff0f172a),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$timeStr logged ${isUnder9h ? '• Target: 9h' : '• Goal reached'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canPunch && !busy ? punch : null,
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text(
              'Punch Out',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffef4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarmGreeting(TrackyuController c, bool isDark) {

    final now = DateTime.now();

    final hour = now.hour;

    String greeting;

    String emoji;

    if (hour >= 5 && hour < 12) {

      greeting = 'Good morning';

      emoji = '☀️';

    } else if (hour >= 12 && hour < 17) {

      greeting = 'Good afternoon';

      emoji = '🌤️';

    } else if (hour >= 17 && hour < 22) {

      greeting = 'Good evening';

      emoji = '🌆';

    } else {

      greeting = 'Good night';

      emoji = '🌙';

    }



    final rawName = c.name.trim();

    final firstName = rawName.isNotEmpty ? rawName.split(' ').first : 'Employee';

    final dateStr = formatToDdMmYyyy(c.workDate.isNotEmpty ? c.workDate : DateTime.now());



    return InkWell(

      borderRadius: BorderRadius.circular(16),

      onTap: () => Navigator.push(

        context,

        MaterialPageRoute<void>(

          builder: (_) => ProfilePage(controller: c),

        ),

      ),

      child: Padding(

        padding: const EdgeInsets.symmetric(vertical: 4),

        child: Row(

          children: [

            Container(

              padding: const EdgeInsets.all(2.5),

              decoration: BoxDecoration(

                shape: BoxShape.circle,

                gradient: LinearGradient(

                  colors: isDark

                      ? [const Color(0xff06b6d4), const Color(0xff3b82f6)]

                      : [const Color(0xff0284c7), const Color(0xff0ea5e9)],

                  begin: Alignment.topLeft,

                  end: Alignment.bottomRight,

                ),

                boxShadow: [

                  BoxShadow(

                    color: (isDark ? const Color(0xff06b6d4) : const Color(0xff0284c7)).withValues(alpha: 0.25),

                    blurRadius: 10,

                    offset: const Offset(0, 3),

                  ),

                ],

              ),

              child: TrackyuAvatarWidget(

                controller: c,

                size: 46,

                isDark: isDark,

              ),

            ),

            const SizedBox(width: 14),

            Expanded(

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Row(

                    children: [

                      Expanded(

                        child: Text(

                          '$emoji $greeting, $firstName',

                          maxLines: 1,

                          overflow: TextOverflow.ellipsis,

                          style: TextStyle(

                            color: isDark ? Colors.white : const Color(0xff0f172a),

                            fontWeight: FontWeight.w800,

                            fontSize: 18,

                            letterSpacing: -0.3,

                          ),

                        ),

                      ),

                      Container(

                        width: 28,

                        height: 28,

                        decoration: BoxDecoration(

                          color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),

                          shape: BoxShape.circle,

                        ),

                        child: Icon(

                          Icons.chevron_right_rounded,

                          size: 18,

                          color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),

                        ),

                      ),

                    ],

                  ),

                  const SizedBox(height: 5),

                  Row(

                    children: [

                      if (c.employeeId.isNotEmpty) ...[

                        Container(

                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),

                          decoration: BoxDecoration(

                            color: isDark ? const Color(0xff1e293b) : const Color(0xffe0f2fe),

                            borderRadius: BorderRadius.circular(6),

                            border: Border.all(

                              color: isDark ? const Color(0xff334155) : const Color(0xffbae6fd),

                              width: 0.8,

                            ),

                          ),

                          child: Text(

                            'ID: ${c.employeeId}',

                            style: TextStyle(

                              color: isDark ? const Color(0xff93c5fd) : const Color(0xff0369a1),

                              fontWeight: FontWeight.w700,

                              fontSize: 11,

                              letterSpacing: 0.2,

                            ),

                          ),

                        ),

                        const SizedBox(width: 8),

                      ],

                      Icon(

                        Icons.calendar_today_rounded,

                        size: 11.5,

                        color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),

                      ),

                      const SizedBox(width: 4),

                      Flexible(

                        child: Text(

                          dateStr,

                          maxLines: 1,

                          overflow: TextOverflow.ellipsis,

                          style: TextStyle(

                            color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),

                            fontSize: 12,

                            fontWeight: FontWeight.w500,

                          ),

                        ),

                      ),

                    ],

                  ),

                ],

              ),

            ),

          ],

        ),

      ),

    );

  }



  Widget build(BuildContext context) {

    final canPunch =

        !busy &&

        c.stateKnown &&

        !c.completed &&

        (c.isField ||

            (c.office != null && (c.onDuty || c.office!['isEnabled'] == true)));

    final status = !c.stateKnown

        ? 'Attendance not loaded'

        : c.completed

        ? 'Work is completed'

        : c.onDuty

        ? 'Punched in'

        : 'Ready to punch in';

    final isDark = c.isDarkMode;

    final isBeta = c.isBetaMode;

    final isLux = c.isLuxuryMode;

    final pageScaffold = Scaffold(

      backgroundColor: isDark

          ? const Color(0xff0b0f19)

          : (isLux ? c.themeBackgroundColor : const Color(0xfff8fafc)),

      drawer: WorkspaceDrawer(controller: c, openSetup: widget.openSetup),
      onDrawerChanged: (isOpened) {
        if (isOpened) unawaited(c.refreshMenus().catchError((Object _) {}));
      },

      appBar: AppBar(

        titleSpacing: 0,

        backgroundColor: isDark

            ? const Color(0xff0b0f19)

            : (isLux ? c.themeBackgroundColor : const Color(0xfff8fafc)),

        title: FittedBox(

          fit: BoxFit.scaleDown,

          alignment: Alignment.centerLeft,

          child: Row(

            mainAxisSize: MainAxisSize.min,

            children: [

              Container(

                width: 30,

                height: 30,

                padding: const EdgeInsets.all(4),

                decoration: BoxDecoration(

                  color: const Color(0xff102c4a),

                  borderRadius: BorderRadius.circular(8),

                ),

                child: Image.asset('assets/legacy/logo.png'),

              ),

              const SizedBox(width: 8),

              const Text(

                'Trackyu',

                style: TextStyle(

                  fontWeight: FontWeight.w800,

                  fontSize: 17,

                  letterSpacing: -0.4,

                ),

              ),

            ],

          ),

        ),

        actions: [

          ListenableBuilder(

            listenable: Listenable.merge([c, network]),

            builder: (context, _) => Padding(

              padding: const EdgeInsets.only(right: 6),

              child: Center(

                child: SyncNetworkAppBarPill(

                  controller: c,

                  network: network,

                  busy: busy,

                  onSync: () => syncNow(),

                ),

              ),

            ),

          ),



          Center(

            child: Material(

              color: Colors.transparent,

              child: InkWell(

                borderRadius: BorderRadius.circular(10),

                onTap: () {

                  Navigator.push(

                    context,

                    MaterialPageRoute<void>(

                      builder: (_) => WorkspacePage(controller: c, feature: WorkFeature.inbox),

                    ),

                  );

                },

                child: Container(

                  width: 36,

                  height: 36,

                  decoration: BoxDecoration(

                    color: isDark

                        ? Colors.white.withValues(alpha: 0.08)

                        : const Color(0xff0284c7).withValues(alpha: 0.12),

                    borderRadius: BorderRadius.circular(10),

                    border: Border.all(

                      color: isDark

                          ? Colors.white.withValues(alpha: 0.15)

                          : const Color(0xff0284c7).withValues(alpha: 0.28),

                      width: 1.2,

                    ),

                  ),

                  alignment: Alignment.center,

                  child: Icon(

                    Icons.notifications_active_outlined,

                    size: 20,

                    color: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),

                  ),

                ),

              ),

            ),

          ),

          const SizedBox(width: 6),

          Center(

            child: Material(

              color: Colors.transparent,

              child: InkWell(

                borderRadius: BorderRadius.circular(10),

                onTap: () => showThemeSelectorModal(context, c),

                child: Container(

                  width: 36,

                  height: 36,

                  decoration: BoxDecoration(

                    color: isDark

                        ? Colors.white.withValues(alpha: 0.08)

                        : c.themePrimaryColor.withValues(alpha: 0.12),

                    borderRadius: BorderRadius.circular(10),

                    border: Border.all(

                      color: isDark

                          ? Colors.white.withValues(alpha: 0.15)

                          : c.themePrimaryColor.withValues(alpha: 0.28),

                      width: 1.2,

                    ),

                  ),

                  alignment: Alignment.center,

                  child: Icon(

                    Icons.palette_rounded,

                    size: 20,

                    color: isDark ? const Color(0xffa78bfa) : c.themePrimaryColor,

                  ),

                ),

              ),

            ),

          ),

          const SizedBox(width: 12),
],

      ),

      body: SafeArea(

        child: Center(

          child: ConstrainedBox(

            constraints: const BoxConstraints(maxWidth: 560),

            child: Stack(
              children: [
                Column(

              children: [

                if (busy) const LinearProgressIndicator(minHeight: 2),

                Expanded(

                  child: RefreshIndicator(

                    onRefresh: () => syncNow(),

                    child: ListView(

                      physics: const AlwaysScrollableScrollPhysics(),

                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),

                      children: [

                        _buildWarmGreeting(c, isDark),

                        const SizedBox(height: 24),

                        if (!c.isField && c.offices.length > 1) ...[

                          DropdownButtonFormField<int>(

                            key: ValueKey(c.officeId),

                            initialValue: c.officeId,

                            isExpanded: true,

                            decoration: const InputDecoration(

                              labelText: 'Office',

                              prefixIcon: Icon(Icons.business_outlined),

                            ),

                            items: c.offices

                                .map(

                                  (o) => DropdownMenuItem<int>(

                                    value: o['id'] as int,

                                    child: Text(

                                      o['name'].toString(),

                                      overflow: TextOverflow.ellipsis,

                                    ),

                                  ),

                                )

                                .toList(),

                            onChanged: busy || c.onDuty

                                ? null

                                : (id) {

                                    if (id != null) {

                                      run(() => c.refresh(selectedOffice: id));

                                    }

                                  },

                          ),

                          const SizedBox(height: 20),

                        ],

                        if (!c.onDuty && !c.completed && c.stateKnown) ...[

                          Container(

                            margin: const EdgeInsets.only(bottom: 16),

                            padding: const EdgeInsets.symmetric(

                              horizontal: 18,

                              vertical: 16,

                            ),

                            decoration: BoxDecoration(

                              gradient: isBeta

                                  ? const LinearGradient(

                                      colors: [

                                        Color(0xffede9fe),

                                        Color(0xfffae8ff),

                                        Color(0xffe0f2fe),

                                      ],

                                      begin: Alignment.topLeft,

                                      end: Alignment.bottomRight,

                                    )

                                  : LinearGradient(

                                      colors: isDark

                                          ? [

                                              const Color(0xff311e11),

                                              const Color(0xff22170f),

                                            ]

                                          : [

                                              const Color(0xfffff7ed),

                                              const Color(0xfffed7aa).withValues(alpha: 0.3),

                                            ],

                                    ),

                              borderRadius: BorderRadius.circular(isBeta ? 22 : 16),

                              border: Border.all(

                                color: isBeta

                                    ? Colors.white.withValues(alpha: 0.95)

                                    : (isDark

                                        ? const Color(0xfff97316).withValues(alpha: 0.5)

                                        : const Color(0xfffdba74)),

                                width: isBeta ? 1.5 : 1.2,

                              ),

                              boxShadow: isBeta

                                  ? [

                                      BoxShadow(

                                        color: const Color(0xff6366f1).withValues(alpha: 0.08),

                                        blurRadius: 18,

                                        offset: const Offset(0, 6),

                                      ),

                                    ]

                                  : null,

                            ),

                            child: Row(

                              children: [

                                Container(

                                  padding: const EdgeInsets.all(9),

                                  decoration: BoxDecoration(

                                    color: isBeta

                                        ? const Color(0xff818cf8).withValues(alpha: 0.2)

                                        : const Color(0xfff97316).withValues(alpha: 0.15),

                                    shape: isBeta ? BoxShape.circle : BoxShape.rectangle,

                                    borderRadius: isBeta ? null : BorderRadius.circular(10),

                                  ),

                                  child: Icon(

                                    isBeta ? Icons.alarm_on_rounded : Icons.notification_important_rounded,

                                    color: isBeta ? const Color(0xff6366f1) : const Color(0xfff97316),

                                    size: 22,

                                  ),

                                ),

                                const SizedBox(width: 12),

                                Expanded(

                                  child: Column(

                                    crossAxisAlignment: CrossAxisAlignment.start,

                                    children: [

                                      Text(

                                        'Work Not Started',

                                        style: TextStyle(

                                          fontWeight: FontWeight.w800,

                                          fontSize: 14,

                                          color: isDark

                                              ? const Color(0xffffedd5)

                                              : (isBeta ? const Color(0xff1e1b4b) : const Color(0xff9a3412)),

                                        ),

                                      ),

                                      const SizedBox(height: 2),

                                      Text(

                                        'Slide below or tap Punch In to start live tracking.',

                                        style: TextStyle(

                                          fontSize: 11.5,

                                          color: isDark

                                              ? const Color(0xfffdba74)

                                              : (isBeta ? const Color(0xff64748b) : const Color(0xffc2410c)),

                                        ),

                                      ),

                                    ],

                                  ),

                                ),

                                const SizedBox(width: 8),

                                FilledButton(

                                  onPressed: busy ? null : punch,

                                  style: FilledButton.styleFrom(

                                    backgroundColor: isBeta ? const Color(0xff6366f1) : const Color(0xfff97316),

                                    foregroundColor: Colors.white,

                                    visualDensity: VisualDensity.compact,

                                    padding: const EdgeInsets.symmetric(

                                      horizontal: 14,

                                      vertical: 7,

                                    ),

                                    shape: RoundedRectangleBorder(

                                      borderRadius: BorderRadius.circular(isBeta ? 9999 : 10),

                                    ),

                                    elevation: isBeta ? 2 : 0,

                                  ),

                                  child: const Text(

                                    'Punch In',

                                    style: TextStyle(

                                      fontSize: 12.5,

                                      fontWeight: FontWeight.bold,

                                    ),

                                  ),

                                ),

                              ],

                            ),

                          ),

                        ],



                        AttendanceSummary(controller: c, status: status),

                        const SizedBox(height: 16),

                        if (c.menuEnabled('visits')) ...[

                          SalesmanVisitShortcut(

                            controller: c,

                            enabled: !busy,

                          ),

                          const SizedBox(height: 16),

                        ],

                        MonthlyGoalsCard(controller: c),

                        const SizedBox(height: 16),

                        TrackingStatusCard(controller: c),

                        const SizedBox(height: 16),

                        ListenableBuilder(

                          listenable: Listenable.merge([c, network]),

                          builder: (context, _) {

                            // Only show sync banner if there are pending items to upload or offline!

                            // Prevents redundant duplicate WiFi status on home screen.

                            if (c.pendingCount == 0 && network.status.isOnline) {

                              return const SizedBox.shrink();

                            }

                            return Column(

                              mainAxisSize: MainAxisSize.min,

                              children: [

                                NetworkSyncStatusCard(

                                  controller: c,

                                  network: network,

                                  onSync: () => syncNow(),

                                ),

                                const SizedBox(height: 16),

                              ],

                            );

                          },

                        ),

                        // Manager Live Team Map Card

                        if (c.menuEnabled('manager_team_map'))

                        Container(

                          margin: const EdgeInsets.only(bottom: 12),

                          child: InkWell(

                            borderRadius: BorderRadius.circular(16),

                            onTap: () {

                              Navigator.push(

                                context,

                                MaterialPageRoute<void>(

                                  builder: (_) => ManagerTeamMapPage(controller: c),

                                ),

                              );

                            },

                            child: Container(

                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),

                              decoration: BoxDecoration(

                                gradient: LinearGradient(

                                  colors: isDark

                                      ? [const Color(0xff064e3b), const Color(0xff065f46)]

                                      : [const Color(0xffecfdf5), const Color(0xffd1fae5)],

                                  begin: Alignment.topLeft,

                                  end: Alignment.bottomRight,

                                ),

                                borderRadius: BorderRadius.circular(16),

                                border: Border.all(

                                  color: isDark ? const Color(0xff059669).withValues(alpha: 0.4) : const Color(0xffa7f3d0),

                                  width: 1.2,

                                ),

                                boxShadow: [

                                  BoxShadow(

                                    color: const Color(0xff10b981).withValues(alpha: 0.12),

                                    blurRadius: 10,

                                    offset: const Offset(0, 3),

                                  ),

                                ],

                              ),

                              child: Row(

                                children: [

                                  Container(

                                    width: 44,

                                    height: 44,

                                    decoration: BoxDecoration(

                                      color: const Color(0xff10b981),

                                      borderRadius: BorderRadius.circular(12),

                                      boxShadow: [

                                        BoxShadow(

                                          color: const Color(0xff10b981).withValues(alpha: 0.35),

                                          blurRadius: 8,

                                          offset: const Offset(0, 2),

                                        ),

                                      ],

                                    ),

                                    alignment: Alignment.center,

                                    child: const Icon(Icons.radar_rounded, size: 24, color: Colors.white),

                                  ),

                                  const SizedBox(width: 14),

                                  Expanded(

                                    child: Column(

                                      crossAxisAlignment: CrossAxisAlignment.start,

                                      children: [

                                        Row(

                                          children: [

                                            Text(

                                              'Live Team Map',

                                              style: TextStyle(

                                                fontWeight: FontWeight.w800,

                                                fontSize: 14.5,

                                                color: isDark ? Colors.white : const Color(0xff065f46),

                                              ),

                                            ),

                                            const SizedBox(width: 8),

                                            Container(

                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),

                                              decoration: BoxDecoration(

                                                color: const Color(0xff10b981),

                                                borderRadius: BorderRadius.circular(6),

                                              ),

                                              child: const Text(

                                                'LIVE',

                                                style: TextStyle(

                                                  color: Colors.white,

                                                  fontSize: 9,

                                                  fontWeight: FontWeight.w900,

                                                ),

                                              ),

                                            ),

                                          ],

                                        ),

                                        const SizedBox(height: 2),

                                        Text(

                                          'Track field employees on live map with day route timeline',

                                          style: TextStyle(

                                            fontSize: 11.5,

                                            color: isDark ? const Color(0xffa7f3d0) : const Color(0xff047857),

                                          ),

                                        ),

                                      ],

                                    ),

                                  ),

                                  Icon(

                                    Icons.arrow_forward_ios_rounded,

                                    size: 16,

                                    color: isDark ? const Color(0xffa7f3d0) : const Color(0xff059669),

                                  ),

                                ],

                              ),

                            ),

                          ),

                        ),

                        // Quick Action Tiles: Geo Tagging & Notifications

                        Container(

                          margin: const EdgeInsets.only(bottom: 16),

                          child: IntrinsicHeight(

                            child: Row(

                              crossAxisAlignment: CrossAxisAlignment.stretch,

                              children: [

                                Expanded(

                                  child: InkWell(

                                    borderRadius: BorderRadius.circular(16),

                                    onTap: () {

                                      Navigator.push(

                                        context,

                                        MaterialPageRoute<void>(

                                          builder: (_) => OfficeLocationRequestPage(controller: c),

                                        ),

                                      );

                                    },

                                    child: Container(

                                      height: 64,

                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

                                      decoration: BoxDecoration(

                                        color: isDark ? const Color(0xff161e2e) : Colors.white,

                                        borderRadius: BorderRadius.circular(16),

                                        border: Border.all(

                                          color: isDark ? const Color(0xff2563eb).withValues(alpha: 0.3) : const Color(0xffbae6fd),

                                          width: 1.2,

                                        ),

                                        boxShadow: [

                                          BoxShadow(

                                            color: const Color(0xff0284c7).withValues(alpha: 0.06),

                                            blurRadius: 10,

                                            offset: const Offset(0, 3),

                                          ),

                                        ],

                                      ),

                                      child: Row(

                                        children: [

                                          Container(

                                            width: 36,

                                            height: 36,

                                            decoration: BoxDecoration(

                                              color: const Color(0xff0284c7).withValues(alpha: 0.12),

                                              borderRadius: BorderRadius.circular(10),

                                            ),

                                            alignment: Alignment.center,

                                            child: const Icon(Icons.add_location_alt_rounded, size: 20, color: Color(0xff0284c7)),

                                          ),

                                          const SizedBox(width: 10),

                                          Expanded(

                                            child: Column(

                                              crossAxisAlignment: CrossAxisAlignment.start,

                                              mainAxisAlignment: MainAxisAlignment.center,

                                              children: [

                                                Text(

                                                  'Geo Tag',

                                                  maxLines: 1,

                                                  overflow: TextOverflow.ellipsis,

                                                  style: TextStyle(

                                                    fontWeight: FontWeight.w700,

                                                    fontSize: 13,

                                                    color: isDark ? Colors.white : const Color(0xff0f172a),

                                                  ),

                                                ),

                                                Text(

                                                  'Save GPS',

                                                  maxLines: 1,

                                                  overflow: TextOverflow.ellipsis,

                                                  style: TextStyle(

                                                    fontSize: 10.5,

                                                    color: isDark ? Colors.white54 : const Color(0xff64748b),

                                                  ),

                                                ),

                                              ],

                                            ),

                                          ),

                                        ],

                                      ),

                                    ),

                                  ),

                                ),

                                const SizedBox(width: 12),

                                Expanded(

                                  child: InkWell(

                                    borderRadius: BorderRadius.circular(16),

                                    onTap: () {

                                      Navigator.push(

                                        context,

                                        MaterialPageRoute<void>(

                                          builder: (_) => WorkspacePage(controller: c, feature: WorkFeature.inbox),

                                        ),

                                      );

                                    },

                                    child: Container(

                                      height: 64,

                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

                                      decoration: BoxDecoration(

                                        color: isDark ? const Color(0xff161e2e) : Colors.white,

                                        borderRadius: BorderRadius.circular(16),

                                        border: Border.all(

                                          color: isDark ? const Color(0xfff59e0b).withValues(alpha: 0.3) : const Color(0xfffde68a),

                                          width: 1.2,

                                        ),

                                        boxShadow: [

                                          BoxShadow(

                                            color: const Color(0xfff59e0b).withValues(alpha: 0.06),

                                            blurRadius: 10,

                                            offset: const Offset(0, 3),

                                          ),

                                        ],

                                      ),

                                      child: Row(

                                        children: [

                                          Container(

                                            width: 36,

                                            height: 36,

                                            decoration: BoxDecoration(

                                              color: const Color(0xfff59e0b).withValues(alpha: 0.12),

                                              borderRadius: BorderRadius.circular(10),

                                            ),

                                            alignment: Alignment.center,

                                            child: const Icon(Icons.notifications_active_rounded, size: 20, color: Color(0xffd97706)),

                                          ),

                                          const SizedBox(width: 10),

                                          Expanded(

                                            child: Column(

                                              crossAxisAlignment: CrossAxisAlignment.start,

                                              mainAxisAlignment: MainAxisAlignment.center,

                                              children: [

                                                Text(

                                                  'Alerts',

                                                  maxLines: 1,

                                                  overflow: TextOverflow.ellipsis,

                                                  style: TextStyle(

                                                    fontWeight: FontWeight.w700,

                                                    fontSize: 13,

                                                    color: isDark ? Colors.white : const Color(0xff0f172a),

                                                  ),

                                                ),

                                                Text(

                                                  'Notices & Inbox',

                                                  maxLines: 1,

                                                  overflow: TextOverflow.ellipsis,

                                                  style: TextStyle(

                                                    fontSize: 10.5,

                                                    color: isDark ? Colors.white54 : const Color(0xff64748b),

                                                  ),

                                                ),

                                              ],

                                            ),

                                          ),

                                        ],

                                      ),

                                    ),

                                  ),

                                ),

                              ],

                            ),

                          ),

                        ),

                        if (c.isField)

                          FieldAttendanceLocationCard(controller: c),

                        if (c.office != null)

                          Container(

                            padding: const EdgeInsets.all(18),

                            decoration: BoxDecoration(

                              gradient: c.isLuxuryMode

                                  ? LinearGradient(

                                      colors: c.themeCardGradient,

                                      begin: Alignment.topLeft,

                                      end: Alignment.bottomRight,

                                    )

                                  : null,

                              color: c.isLuxuryMode

                                  ? null

                                  : (isDark

                                      ? const Color(0xff1e1e1e)

                                      : const Color(0xffe9eff7)),

                              borderRadius: BorderRadius.circular(18),

                              border: Border.all(

                                color: c.isLuxuryMode

                                    ? Colors.white.withValues(alpha: 0.9)

                                    : (isDark

                                        ? const Color(0xff2d3135)

                                        : const Color(0xffdce4ee)),

                                width: c.isLuxuryMode ? 1.4 : 1.0,

                              ),

                              boxShadow: c.isLuxuryMode

                                  ? [

                                      BoxShadow(

                                        color: c.themePrimaryColor.withValues(alpha: 0.08),

                                        blurRadius: 16,

                                        offset: const Offset(0, 4),

                                      ),

                                    ]

                                  : null,

                            ),

                            child: Row(

                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [

                                Icon(

                                  Icons.business_outlined,

                                  color: isDark

                                      ? const Color(0xff38bdf8)

                                      : trackyuBlue,

                                  size: 20,

                                ),

                                const SizedBox(width: 12),

                                Expanded(

                                  child: Text(

                                    '${c.office!['shiftStart'].toString().split(':').take(2).join(':')} – ${c.office!['shiftEnd'].toString().split(':').take(2).join(':')} • ${c.office!['timeZoneId']}\n${c.office!['radiusMeters']} m office radius • ${c.office!['lateGraceMinutes']} min late grace',

                                    style: TextStyle(

                                      color: isDark

                                          ? const Color(0xffcbd5e1)

                                          : const Color(0xff475b75),

                                      fontSize: 12,

                                      height: 1.8,

                                    ),

                                  ),

                                ),

                              ],

                            ),

                          ),

                        if (c.notice.isNotEmpty &&

                            !c.notice.toLowerCase().contains('connection') &&

                            !c.notice.toLowerCase().contains('cannot reach') &&

                            !c.notice.toLowerCase().contains('unavailable') &&

                            !c.notice.toLowerCase().contains('network') &&

                            !c.notice.toLowerCase().contains(

                              'sync will retry',

                            ) &&

                            !c.notice.toLowerCase().contains(

                              'sync requested',

                            ) &&

                            !c.notice.toLowerCase().contains(

                              'phone data remains available',

                            ) &&

                            !c.notice.toLowerCase().contains('retained') && !c.notice.toLowerCase().contains('synced') && !c.notice.toLowerCase().contains('workspace') && !c.notice.toLowerCase().contains('phone data') && !c.notice.toLowerCase().contains('saved') && !c.notice.toLowerCase().contains('sync'))

                          Padding(

                            padding: const EdgeInsets.only(top: 14),

                            child: Container(

                              padding: const EdgeInsets.symmetric(

                                horizontal: 14,

                                vertical: 12,

                              ),

                              decoration: BoxDecoration(

                                color: c.notice.contains('confirmed')

                                    ? const Color(0xffecfdf5)

                                    : const Color(0xfffffbeb),

                                borderRadius: BorderRadius.circular(14),

                                border: Border.all(

                                  color: c.notice.contains('confirmed')

                                      ? const Color(0xffa7f3d0)

                                      : const Color(0xfffde68a),

                                ),

                              ),

                              child: Row(

                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [

                                  Icon(

                                    c.notice.contains('confirmed')

                                        ? Icons.check_circle_outline_rounded

                                        : Icons.info_outline_rounded,

                                    size: 18,

                                    color: c.notice.contains('confirmed')

                                        ? const Color(0xff059669)

                                        : const Color(0xffd97706),

                                  ),

                                  const SizedBox(width: 10),

                                  Expanded(

                                    child: SelectableText(

                                      c.notice,

                                      style: TextStyle(

                                        color: c.notice.contains('confirmed')

                                            ? const Color(0xff065f46)

                                            : const Color(0xff92400e),

                                        fontSize: 12,

                                        fontWeight: FontWeight.w500,

                                        height: 1.4,

                                      ),

                                    ),

                                  ),

                                  if (!c.notice.contains('confirmed'))

                                    InkWell(

                                      onTap: busy ? null : () => syncNow(),

                                      borderRadius: BorderRadius.circular(8),

                                      child: const Padding(

                                        padding: EdgeInsets.symmetric(

                                          horizontal: 4,

                                        ),

                                        child: Icon(

                                          Icons.refresh_rounded,

                                          size: 18,

                                          color: Color(0xffd97706),

                                        ),

                                      ),

                                    ),

                                ],

                              ),

                            ),

                          ),

                        if (!c.stateKnown)

                          Padding(

                            padding: const EdgeInsets.only(top: 14),

                            child: OutlinedButton.icon(

                              onPressed: busy

                                  ? null

                                  : () => run(() => c.refresh()),

                              icon: const Icon(Icons.refresh),

                              label: const Text('Reload attendance'),

                            ),

                          ),



                      ],

                    ),

                  ),

                ),

                if (!c.completed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: c.onDuty
                        ? _buildActiveWorkSessionBar(context, c, canPunch, busy)
                        : SlidePunch(
                            controller: c,
                            enabled: canPunch,
                            hint: 'Selfie & GPS required to Punch In',
                            label: busy
                                ? 'Confirming attendance...'
                                : 'Slide to Punch In',
                            onSubmit: punch,
                          ),
                  ),

              ],

            ),



              ],

            ),

          ),

        ),

      ),

    );
    return Stack(
      children: [
        pageScaffold,
        if (busy)
          Positioned.fill(
            child: Container(
              color: isDark
                  ? const Color(0xff0b0f19).withValues(alpha: 0.78)
                  : const Color(0xfff8fafc).withValues(alpha: 0.82),
              alignment: Alignment.center,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GpsRadarLoader(
                      label: c.onDuty
                          ? 'Verifying Punch Out...'
                          : 'Verifying Punch In...',
                      sublabel: 'Validating live GPS & attendance rules',
                      size: 96,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      c.onDuty
                          ? 'Verifying Punch Out...'
                          : 'Verifying Punch In...',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xff0f172a),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Validating live GPS & attendance rules',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xff94a3b8)
                            : const Color(0xff475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}


class SlidePunch extends StatefulWidget {

  final TrackyuController? controller;

  final bool enabled;

  final String label;

  final String? hint;

  final Future<void> Function() onSubmit;

  const SlidePunch({

    super.key,

    this.controller,

    required this.enabled,

    required this.label,

    this.hint,

    required this.onSubmit,

  });

  @override

  State<SlidePunch> createState() => _SlidePunchState();

}



class _SlidePunchState extends State<SlidePunch> {

  double progress = 0;

  bool submitting = false;

  Future<void> submit() async {

    if (!widget.enabled || submitting) return;

    setState(() {

      progress = 0;

      submitting = true;

    });

    try {

      await widget.onSubmit();

    } finally {

      if (mounted) setState(() => submitting = false);

    }

  }



  @override

  Widget build(BuildContext context) {

    final active = widget.enabled && !submitting;

    final large = MediaQuery.textScalerOf(context).scale(16) > 22;

    return Semantics(

      label: widget.label,

      button: true,

      enabled: active,

      onTap: active ? submit : null,

      child: Column(

        mainAxisSize: MainAxisSize.min,

        children: [

          AnimatedContainer(

            duration: const Duration(milliseconds: 180),

            height: large ? 92 : 76,

            decoration: BoxDecoration(

              gradient: LinearGradient(

                colors: active

                    ? (widget.label.toLowerCase().contains('punch out')

                        ? (widget.controller?.isLuxuryMode == true

                            ? [

                                widget.controller!.themePrimaryColor,

                                widget.controller!.themeSecondaryColor,

                              ]

                            : [const Color(0xffea580c), const Color(0xffc2410c)])

                        : (widget.controller?.isLuxuryMode == true

                            ? [

                                widget.controller!.themePrimaryColor,

                                widget.controller!.themeSecondaryColor,

                              ]

                            : [const Color(0xff0284c7), const Color(0xff0d9488)]))

                    : [const Color(0xff97aab7), const Color(0xff8298a9)],

              ),

              borderRadius: BorderRadius.circular(40),

              border: Border.all(color: Colors.white.withValues(alpha: .3)),

              boxShadow: active

                  ? [

                      BoxShadow(

                        color: (widget.label.toLowerCase().contains('punch out')

                                ? const Color(0xffea580c)

                                : const Color(0xff0284c7))

                            .withValues(alpha: .32),

                        blurRadius: 24,

                        offset: const Offset(0, 8),

                      ),

                    ]

                  : [],

            ),

            child: ClipRRect(

              borderRadius: BorderRadius.circular(40),

              child: Stack(

                alignment: Alignment.center,

                children: [

                  Positioned.fill(

                    child: Align(

                      alignment: Alignment.centerLeft,

                      child: FractionallySizedBox(

                        widthFactor: progress,

                        child: Container(

                          color: const Color(0xff75d5b3).withValues(alpha: .3),

                        ),

                      ),

                    ),

                  ),

                  if (!submitting)

                    Padding(

                      padding: const EdgeInsets.symmetric(horizontal: 66),

                      child: AnimatedOpacity(

                        duration: const Duration(milliseconds: 120),

                        opacity: (1 - progress * 1.4).clamp(0, 1),

                        child: Text(

                          widget.label,

                          textAlign: TextAlign.center,

                          style: const TextStyle(

                            color: Colors.white,

                            fontWeight: FontWeight.w600,

                            fontSize: 15,

                            letterSpacing: .1,

                          ),

                        ),

                      ),

                    ),

                  if (!submitting)

                    const Positioned(

                      right: 22,

                      child: Icon(

                        Icons.keyboard_double_arrow_right_rounded,

                        color: Colors.white38,

                        size: 26,

                      ),

                    ),

                  if (submitting)

                    const Padding(

                      padding: EdgeInsets.only(left: 76, right: 20),

                      child: Row(

                        mainAxisAlignment: MainAxisAlignment.center,

                        children: [

                          SizedBox(

                            width: 18,

                            height: 18,

                            child: CircularProgressIndicator(

                              color: Colors.white,

                              strokeWidth: 2,

                            ),

                          ),

                          SizedBox(width: 10),

                          Flexible(

                            child: Text(

                              'Confirming...',

                              style: TextStyle(

                                color: Colors.white,

                                fontWeight: FontWeight.w600,

                                fontSize: 15,

                              ),

                            ),

                          ),

                        ],

                      ),

                    ),

                  SliderTheme(

                    data: SliderTheme.of(context).copyWith(

                      trackHeight: 0,

                      inactiveTrackColor: Colors.transparent,

                      activeTrackColor: Colors.transparent,

                      overlayColor: Colors.transparent,

                      thumbColor: Colors.white,

                      disabledThumbColor: const Color(0xffe5edf1),

                      thumbShape: const _PunchThumb(),

                      trackShape: const _PunchTrack(),

                    ),

                    child: Slider(

                      value: progress,

                      padding: EdgeInsets.zero,

                      allowedInteraction: SliderInteraction.slideOnly,

                      onChanged: active

                          ? (v) => setState(() => progress = v)

                          : null,

                      onChangeEnd: active

                          ? (v) {

                              if (v >= .9) {

                                submit();

                              } else {

                                setState(() => progress = 0);

                              }

                            }

                          : null,

                    ),

                  ),

                ],

              ),

            ),

          ),

          const SizedBox(height: 10),

          Row(

            mainAxisAlignment: MainAxisAlignment.center,

            children: [

              const Icon(

                Icons.lock_outline_rounded,

                size: 12,

                color: Color(0xff8393a5),

              ),

              const SizedBox(width: 6),

              Flexible(

                child: Text(

                  submitting

                      ? 'Waiting for server confirmation'

                      : widget.hint ?? 'Swipe all the way to confirm',

                  textAlign: TextAlign.center,

                  style: const TextStyle(

                    fontSize: 11,

                    color: Color(0xff8393a5),

                  ),

                ),

              ),

            ],

          ),

        ],

      ),

    );

  }

}



class _PunchTrack extends RoundedRectSliderTrackShape {

  const _PunchTrack();

  @override

  Rect getPreferredRect({

    required RenderBox parentBox,

    Offset offset = Offset.zero,

    required SliderThemeData sliderTheme,

    bool isEnabled = false,

    bool isDiscrete = false,

  }) => Rect.fromLTWH(

    offset.dx + 36,

    offset.dy + parentBox.size.height / 2,

    (parentBox.size.width - 72).clamp(0, double.infinity),

    0,

  );

}



class _PunchThumb extends RoundSliderThumbShape {

  const _PunchThumb()

    : super(enabledThumbRadius: 27, elevation: 0, pressedElevation: 0);

  @override

  void paint(

    PaintingContext context,

    Offset center, {

    required Animation<double> activationAnimation,

    required Animation<double> enableAnimation,

    required bool isDiscrete,

    required TextPainter labelPainter,

    required RenderBox parentBox,

    required SliderThemeData sliderTheme,

    required TextDirection textDirection,

    required double value,

    required double textScaleFactor,

    required Size sizeWithOverflow,

  }) {

    super.paint(

      context,

      center,

      activationAnimation: activationAnimation,

      enableAnimation: enableAnimation,

      isDiscrete: isDiscrete,

      labelPainter: labelPainter,

      parentBox: parentBox,

      sliderTheme: sliderTheme,

      textDirection: textDirection,

      value: value,

      textScaleFactor: textScaleFactor,

      sizeWithOverflow: sizeWithOverflow,

    );

    final direction = textDirection == TextDirection.ltr ? 1.0 : -1.0;

    final arrow = Path()

      ..moveTo(center.dx - 3 * direction, center.dy - 6)

      ..lineTo(center.dx + 3 * direction, center.dy)

      ..lineTo(center.dx - 3 * direction, center.dy + 6);

    context.canvas.drawPath(
      arrow,
      Paint()
        ..color = trackyuBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
}
