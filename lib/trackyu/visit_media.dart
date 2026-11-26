import 'dart:convert';
import 'dart:typed_data';
import 'api.dart';
import 'controller.dart';
import 'timeline_reconciliation.dart';

Uint8List? visitPhotoBytes(Json row, String phase) {
  final value = phase == 'out'
      ? row['departureSelfieBase64'] ?? row['outPhoto'] ?? row['departurePhoto']
      : row['photoBase64'] ?? row['photo'] ?? row['selfie'] ?? row['inPhoto'];
  if (value is! String || value.trim().isEmpty) return null;
  try {
    final bytes = base64Decode(
      value.replaceFirst(RegExp(r'^data:image/[^;]+;base64,'), '').trim(),
    );
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

bool hasDeparturePhoto(Json row) =>
    row['hasDepartureSelfie'] == true ||
    row['HasDepartureSelfie'] == true ||
    ['departureSelfieBase64', 'outPhoto', 'departurePhoto', 'checkOutPhoto'].any(
      (key) => row[key] is String && (row[key] as String).trim().isNotEmpty,
    );

Future<Json> localVisitMedia(TrackyuController controller, Json row) async {
  final scope = controller.visitCacheScope;
  final workspace = controller.local;
  final at = instant(row['checkInUtc']);
  final date = at == null ? controller.localDay : businessDay(at);
  final declared = '${row['workDate'] ?? ''}';
  final day = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(declared)
      ? declared
      : date;
  bool matches(Json candidate) {
    final ids = [
      'id',
      'localId',
      'serverId',
    ].map((k) => row[k]?.toString()).whereType<String>().toSet();
    return [
          'id',
          'localId',
          'serverId',
        ].any((k) => candidate[k] != null && ids.contains('${candidate[k]}')) ||
        (row['requestId'] != null &&
            candidate['requestId'] == row['requestId']);
  }

  try {
    final record = workspace == null
        ? <String, dynamic>{}
        : await workspace.read('day:$day') ?? <String, dynamic>{};
    if (controller.visitCacheScope != scope ||
        !identical(workspace, controller.local)) {
      throw const ApiFailure(
        'SESSION_CHANGED',
        'Sign in again to view this photo.',
      );
    }
    for (final candidate in rowsOf(record['visits'])) {
      if (matches(candidate)) return mergeRich(row, candidate);
    }
  } on ApiFailure {
    rethrow;
  } catch (_) {
    // Local media lookup fallback
  }
  return row;
}

Future<Uint8List> loadVisitPhoto(
  TrackyuController controller,
  Json row,
  String phase,
) async {
  final scope = controller.visitCacheScope;
  final inline = visitPhotoBytes(row, phase);
  if (inline != null) return inline;
  final local = await localVisitMedia(controller, row);
  final saved = visitPhotoBytes(local, phase);
  if (saved != null) return saved;
  if (controller.visitCacheScope != scope) {
    throw const ApiFailure(
      'SESSION_CHANGED',
      'Sign in again to view this photo.',
    );
  }
  if (controller.offline ||
      (local['isOffline'] == true && local['serverId'] == null)) {
    throw const ApiFailure(
      'SELFIE_UNAVAILABLE_OFFLINE',
      'This photo is not available on this phone. Connect to download a server-saved photo.',
    );
  }
  final id = int.tryParse('${local['serverId'] ?? local['id']}') ?? 0;
  if (id <= 0) {
    throw const ApiFailure(
      'SELFIE_NOT_FOUND',
      'No saved photo exists for this visit.',
    );
  }
  final bytes = await controller.api.visitPhoto(id, phase: phase);
  if (controller.visitCacheScope != scope) {
    throw const ApiFailure(
      'SESSION_CHANGED',
      'Sign in again to view this photo.',
    );
  }
  return bytes;
}
