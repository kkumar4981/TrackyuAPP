import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'working_hours.dart';
import 'selfie_view.dart';

class AttendanceSummary extends StatefulWidget {
  final TrackyuController controller;
  final String status;
  const AttendanceSummary({
    super.key,
    required this.controller,
    required this.status,
  });
  @override
  State<AttendanceSummary> createState() => _AttendanceSummaryState();
}

class _AttendanceSummaryState extends State<AttendanceSummary> {
  Future<Uint8List>? inPhoto;
  String? inPhotoKey;

  @override
  void initState() {
    super.initState();
    sync();
  }

  @override
  void didUpdateWidget(AttendanceSummary old) {
    super.didUpdateWidget(old);
    sync();
  }

  void sync() {
    final c = widget.controller;
    // If employee is neither on duty nor completed for today, never load previous selfies
    if (!c.onDuty && !c.completed) {
      inPhoto = null;
      inPhotoKey = null;
      return;
    }
    final id = c.attendance?['serverId'] ?? c.attendance?['id'];
    final key = c.attendance?['hasSelfie'] == true
        ? '::'
        : null;
    if (key == inPhotoKey) return;
    inPhotoKey = key;
    final localBytes = _getInSelfieBytes(c);
    if (localBytes != null) {
      inPhoto = Future.value(localBytes);
    } else {
      final numId = id is num ? id.toInt() : int.tryParse('') ?? 0;
      inPhoto = key == null || numId < 1 || numId > 1000000000
          ? null
          : c.api.attendanceSelfie(c.isField ? 'Field' : 'Office', numId);
    }
  }

  String _formatTime(dynamic utc) {
    if (utc == null) return '--:--';
    final time = DateTime.tryParse(utc.toString())?.toLocal();
    if (time == null) return '--:--';
    final hour = time.hour;
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final m = time.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'pm' : 'am';
    return '$h:$m $ampm';
  }

  Uint8List? _getInSelfieBytes(TrackyuController c) {
    final att = c.attendance;
    final b64 = att?['punchInPhotoBase64'] ?? att?['selfieBase64'] ?? att?['photoBase64'];
    if (b64 is! String || b64.trim().isEmpty) return null;
    try {
      final clean = b64.replaceFirst(RegExp(r'^data:image/[^;]+;base64,'), '').trim();
      final bytes = base64Decode(clean);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Uint8List? _getOutSelfieBytes() {
    final b64 = widget.controller.outSelfieBase64;
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final isDark = c.isDarkMode;
    final outBytes = _getOutOutSelfieBytesSafe();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? (c.onDuty
                  ? [const Color(0xff0a1e36), const Color(0xff133b63), const Color(0xff0f2b48)]
                  : c.themeCardGradient)
              : (c.isLuxuryMode
                  ? c.themeCardGradient
                  : (c.onDuty
                      ? [const Color(0xffffffff), const Color(0xfff0f7ff)]
                      : [const Color(0xffffffff), const Color(0xfff8fafc)])),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? (c.onDuty
                  ? const Color(0xff0284c7).withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.12))
              : (c.isLuxuryMode
                  ? Colors.white.withValues(alpha: 0.95)
                  : (c.onDuty
                      ? const Color(0xff38bdf8).withValues(alpha: 0.5)
                      : const Color(0xffe2e8f0))),
          width: c.isLuxuryMode ? 1.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? (c.onDuty
                    ? const Color(0xff0284c7).withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.35))
                : (c.isLuxuryMode
                    ? c.themePrimaryColor.withValues(alpha: 0.08)
                    : (c.onDuty
                        ? const Color(0xff0284c7).withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.04))),
            blurRadius: isDark ? 24 : 18,
            offset: Offset(0, isDark ? 8 : 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header status & live tag row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: isDark
                        ? (c.onDuty
                                ? const Color(0xff10b981)
                                : (c.completed ? const Color(0xffa855f7) : const Color(0xff38bdf8)))
                            .withValues(alpha: 0.18)
                        : (c.onDuty
                            ? const Color(0xffecfdf5)
                            : (c.completed ? const Color(0xfffaf5ff) : const Color(0xfff0f9ff))),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? (c.onDuty
                                  ? const Color(0xff10b981)
                                  : (c.completed ? const Color(0xffa855f7) : const Color(0xff38bdf8)))
                              .withValues(alpha: 0.45)
                          : (c.onDuty
                              ? const Color(0xffa7f3d0)
                              : (c.completed ? const Color(0xffe9d5ff) : const Color(0xffbae6fd))),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.onDuty
                              ? const Color(0xff10b981)
                              : (c.completed
                                  ? (isDark ? const Color(0xffc084fc) : const Color(0xffa855f7))
                                  : (isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7))),
                          boxShadow: isDark
                              ? [
                                  BoxShadow(
                                    color: c.onDuty ? const Color(0xff10b981) : const Color(0xff38bdf8),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          c.onDuty
                              ? 'ACTIVE AT WORK'
                              : (c.completed ? 'DAY COMPLETED' : 'READY TO PUNCH IN'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark
                                ? (c.onDuty
                                    ? const Color(0xff6ee7b7)
                                    : (c.completed ? const Color(0xffe9d5ff) : const Color(0xffbae6fd)))
                                : (c.onDuty
                                    ? const Color(0xff047857)
                                    : (c.completed ? const Color(0xff7e22ce) : const Color(0xff0369a1))),
                            fontWeight: FontWeight.w800,
                            fontSize: 10.5,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (c.onDuty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: c.isMockGpsDetected
                        ? const Color(0xffef4444)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.10)
                            : (c.isLuxuryMode ? c.themePrimaryColor.withValues(alpha: 0.10) : const Color(0xffe0f2fe))),
                    borderRadius: BorderRadius.circular(12),
                    border: c.isMockGpsDetected
                        ? null
                        : (isDark ? null : Border.all(color: const Color(0xffbae6fd))),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        c.isMockGpsDetected ? Icons.gpp_bad_rounded : Icons.gps_fixed_rounded,
                        size: 11,
                        color: c.isMockGpsDetected
                            ? Colors.white
                            : (isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        c.isMockGpsDetected ? 'Mock GPS Detected' : 'Live GPS Active',
                        style: TextStyle(
                          color: c.isMockGpsDetected
                              ? Colors.white
                              : (isDark ? const Color(0xffe2e8f0) : const Color(0xff0369a1)),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Total working hours in a single row
          WorkingHoursDisplay(controller: c, showSubtitle: false, inRow: true),
          const SizedBox(height: 14),
          // Dual Cards: Punch-In & Punch-Out side by side with both selfies
          Row(
            children: [
              // Punch-In Card with Check-In Selfie
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.07) : (c.isLuxuryMode ? Colors.white.withValues(alpha: 0.88) : const Color(0xfff8fafc)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xffe2e8f0),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Check-in selfie thumbnail
                      _inPhotoThumbnail(c),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.login_rounded,
                                    size: 11,
                                    color: isDark ? const Color(0xff34d399) : const Color(0xff059669),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'PUNCH IN',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 1),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                (!c.onDuty && !c.completed) ? '--:--' : _formatTime((c.attendance?['punchInUtc'] ?? c.attendance?['PunchInUtc'])),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : const Color(0xff0f172a),
                                ),
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                (!c.onDuty && !c.completed) ? 'Not recorded' : 'Check-in selfie',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  color: isDark ? const Color(0xff34d399) : const Color(0xff059669),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Punch-Out Card with Check-Out Selfie
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xfff8fafc),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xffe2e8f0),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Check-out selfie thumbnail
                      _outPhotoThumbnail(c, outBytes),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.logout_rounded,
                                    size: 11,
                                    color: isDark ? const Color(0xff60a5fa) : const Color(0xff0284c7),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'PUNCH OUT',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 1),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                !c.completed ? '--:--' : _formatTime((c.attendance?['punchOutUtc'] ?? c.attendance?['PunchOutUtc'])),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : const Color(0xff0f172a),
                                ),
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                outBytes != null
                                    ? 'Check-out selfie'
                                    : (c.completed
                                          ? 'Tap to capture'
                                          : 'Pending'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  color: outBytes != null
                                      ? (isDark ? const Color(0xff60a5fa) : const Color(0xff0284c7))
                                      : (isDark ? const Color(0xff94a3b8) : const Color(0xff64748b)),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Uint8List? _getOutOutSelfieBytesSafe() {
    return _getOutSelfieBytes();
  }

  Widget _inPhotoThumbnail(TrackyuController c) {
    if (!c.onDuty && !c.completed) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xff10b981).withValues(alpha: 0.35),
            width: 1.0,
          ),
          color: const Color(0xff10b981).withValues(alpha: 0.08),
        ),
        child: const Icon(
          Icons.photo_camera_rounded,
          color: Color(0xff10b981),
          size: 20,
        ),
      );
    }
    return InkWell(
      onTap: () {
        final raw = _getInSelfieBytes(c);
        final rawId = c.attendance?['serverId'] ?? c.attendance?['id'];
        final numId = rawId is num ? rawId.toInt() : int.tryParse('') ?? 0;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AttendanceSelfiePage(
              controller: c,
              mode: c.isField ? 'Field' : 'Office',
              attendanceId: numId,
              rawBytes: raw,
              title: 'Check-in selfie',
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xff10b981).withValues(alpha: 0.6),
            width: 1.2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.8),
          child: inPhoto != null
              ? FutureBuilder<Uint8List>(
                  future: inPhoto,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 18,
                        ),
                      );
                    }
                    return ColoredBox(
                      color: const Color(0xff10b981).withValues(alpha: 0.15),
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        color: Color(0xff34d399),
                        size: 18,
                      ),
                    );
                  },
                )
              : ColoredBox(
                  color: const Color(0xff10b981).withValues(alpha: 0.15),
                  child: const Icon(
                    Icons.photo_camera_rounded,
                    color: Color(0xff34d399),
                    size: 18,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _outPhotoThumbnail(TrackyuController c, Uint8List? outBytes) {
    if (!c.completed || outBytes == null) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xff60a5fa).withValues(alpha: 0.35),
            width: 1.0,
          ),
          color: const Color(0xff60a5fa).withValues(alpha: 0.08),
        ),
        child: const Icon(
          Icons.camera_alt_outlined,
          color: Color(0xff60a5fa),
          size: 20,
        ),
      );
    }
    return InkWell(
      onTap: () async {
        if (outBytes != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AttendanceSelfiePage(
                controller: c,
                mode: c.isField ? 'Field' : 'Office',
                attendanceId: c.attendance?['id'] as int? ?? 0,
                rawBytes: outBytes,
                title: 'Check-out selfie',
              ),
            ),
          );
        } else if (c.completed) {
          // Allow employee to take check-out selfie if not yet taken
          final photo = await c.takeSelfie();
          if (photo != null) {
            await c.saveOutSelfie(photo);
          }
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xff60a5fa).withValues(alpha: 0.6),
            width: 1.2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.8),
          child: outBytes != null
              ? Image.memory(
                  outBytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 18,
                  ),
                )
              : ColoredBox(
                  color: const Color(0xff60a5fa).withValues(alpha: 0.15),
                  child: Icon(
                    c.completed
                        ? Icons.add_a_photo_rounded
                        : Icons.photo_camera_rounded,
                    color: const Color(0xff60a5fa),
                    size: 18,
                  ),
                ),
        ),
      ),
    );
  }
}
