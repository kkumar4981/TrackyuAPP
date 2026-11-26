import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'trackyu/app.dart';
import 'trackyu/error_logger.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
      );
      ErrorLogger.installHandlers();
      unawaited(resolveAppVersion());
      // Render immediately. Diagnostics must never hold the Android launch screen.
      runApp(const TrackyuApp());
      unawaited(ErrorLogger.initialize());
    },
    (error, stack) {
      unawaited(ErrorLogger.record(error, stack, context: 'rootZone'));
    },
  );
}
