import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../core/models.dart';
import '../trackyu/api.dart';
import '../trackyu/duty_tracking.dart';

/// Compatibility adapter for the earlier prototype. Production uses DutyTracker.
class Tracking {
  bool ready = false;
  final void Function(Fix) onFix;
  final void Function(String, String) onIssue;
  Tracking(this.onFix, this.onIssue);
  Future<void> configure({
    required Policy policy,
    required String baseUrl,
    required String token,
    required String sessionId,
  }) async {
    final api = TrackyuApi(baseUrl)..authorize(token);
    final state = policy.office
        ? await api.state(int.parse(sessionId))
        : await api.fieldState();
    final row = state['attendance'];
    if (row is! Map) throw StateError('An attendance session is required.');
    await DutyTracker.reconcile(
      api,
      policy.office ? 'Office' : 'Field',
      Map<String, dynamic>.from(row),
    );
    ready = true;
  }

  Future<void> start() => DutyTracker.resume();
  Future<void> stop() => DutyTracker.stop();
  Future<void> sync() => DutyTracker.sync();
  Future<int?> queued() async =>
      (await DutyTracker.status())['pendingCount'] as int?;
  Future<Fix> current() async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
    return Fix(
      const Uuid().v4(),
      p.latitude,
      p.longitude,
      p.accuracy,
      p.timestamp,
    );
  }
}
