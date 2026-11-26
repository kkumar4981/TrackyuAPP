import 'dart:convert';
import 'visit_media.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'api.dart';
import 'controller.dart';

class AttendanceSelfiePage extends StatefulWidget {
  final TrackyuController controller;
  final String mode;
  final int attendanceId;
  final bool visit;
  final String phase;
  final Uint8List? rawBytes;
  final String? title;
  final Json? visitRecord;
  const AttendanceSelfiePage({
    super.key,
    required this.controller,
    required this.mode,
    required this.attendanceId,
    this.rawBytes,
    this.title,
    this.phase = 'in',
  }) : visitRecord = null,
       visit = false;

  const AttendanceSelfiePage.visit({
    super.key,
    required this.controller,
    int? visitId,
    int? attendanceId,
    this.mode = 'Field',
    this.phase = 'in',
    this.visitRecord,
    this.title,
  }) : attendanceId = visitId ?? attendanceId ?? 0,
       visit = true,
       rawBytes = null;

  @override
  State<AttendanceSelfiePage> createState() => _AttendanceSelfiePageState();
}

class _AttendanceSelfiePageState extends State<AttendanceSelfiePage> {
  late Future<Uint8List> image;
  @override
  void initState() {
    super.initState();
    image = load();
  }

  Future<Uint8List> load() async {
    if (widget.rawBytes != null) return widget.rawBytes!;
    try {
      if (widget.visit) {
        return await loadVisitPhoto(
          widget.controller,
          widget.visitRecord ?? {'id': widget.attendanceId},
          widget.phase,
        );
      }

      // Check in-memory punch-in selfie base64 first
      final att = widget.controller.attendance;
      final localB64 = att?['punchInPhotoBase64'] ??
          att?['selfieBase64'] ??
          att?['photoBase64'];
      if (localB64 is String && localB64.trim().isNotEmpty) {
        final clean = localB64
            .replaceFirst(RegExp(r'^data:image/[^;]+;base64,'), '')
            .trim();
        try {
          return base64Decode(clean);
        } catch (_) {}
      }

      // Check local workspace day data
      try {
        final dayData = await widget.controller.localDayData();
        final dayAtt = dayData['attendance'];
        if (dayAtt is Map) {
          final b64 = dayAtt['punchInPhotoBase64'] ??
              dayAtt['selfieBase64'] ??
              dayAtt['photoBase64'];
          if (b64 is String && b64.trim().isNotEmpty) {
            final clean = b64
                .replaceFirst(RegExp(r'^data:image/[^;]+;base64,'), '')
                .trim();
            return base64Decode(clean);
          }
        }
      } catch (_) {}

      var targetId = widget.attendanceId;
      if (targetId <= 0) {
        final rawId = att?['serverId'] ?? att?['id'];
        if (rawId is num && rawId.toInt() > 0) {
          targetId = rawId.toInt();
        }
      }

      return await widget.controller.api.attendanceSelfie(
        widget.mode,
        targetId,
        type: widget.phase,
      );
    } on ApiFailure catch (e) {
      if (e.status == 401) {
        await widget.controller.signOut();
        if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.title ??
            (widget.visit
                ? (widget.phase == 'out'
                    ? 'Departure selfie'
                    : 'Arrival selfie')
                : 'Punch-in selfie'),
      ),
    ),
    body: FutureBuilder<Uint8List>(
      future: image,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.error is ApiFailure
                        ? (snapshot.error as ApiFailure).message
                        : 'Unable to load this photo.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        image = load();
                      });
                    },
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: InteractiveViewer(
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Text('Unable to display this image.'),
              ),
            ),
          ),
        );
      },
    ),
  );
}
