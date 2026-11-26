import 'gps_radar_loader.dart';
import 'dart:math' as math;
import 'visit_reconciliation.dart';
import 'package:flutter/services.dart';

import 'visit_overstay_sheet.dart';







import 'visit_media.dart';







import 'package:geocoding/geocoding.dart';







import 'address_cache.dart';







import 'retailer_geotag_page.dart';







import 'duty_tracking.dart';







import 'dart:convert';







import 'dart:async';







import 'package:flutter/material.dart';







import 'package:uuid/uuid.dart';







import 'api.dart';

import 'trackyu_app_bar.dart';







import 'controller.dart';







import 'selfie.dart';







import 'selfie_view.dart';







import 'workspace.dart'







    show dateOnly, jsonRows, WorkspacePage, WorkFeature;















String cleanAddress(String? raw) {







  if (raw == null) return '';







  var trimmed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();







  trimmed = trimmed.replaceAll(RegExp(r'\b[A-Z0-9]{4,8}\+[A-Z0-9]{2,},?\s*', caseSensitive: false), '').trim();







  if (trimmed.isEmpty || trimmed == '-') return '';















  final parts = trimmed.split(RegExp(r"[,;\n]"));









  final seen = <String>{};







  final cleaned = <String>[];















  for (final part in parts) {







    final segment = part.trim();







    if (segment.isEmpty) continue;







    final lower = segment.toLowerCase();







    if (seen.contains(lower)) continue;







    if (lower.contains('unnamed road')) continue;















    bool isDuplicate = false;







    for (int i = 0; i < cleaned.length; i++) {







      final prevLower = cleaned[i].toLowerCase();







      if (prevLower == lower) {







        isDuplicate = true;







        break;







      }







      if (prevLower.contains(lower) && lower.length >= 4) {







        isDuplicate = true;







        break;







      }







      if (lower.contains(prevLower) && prevLower.length >= 4) {







        cleaned[i] = segment;







        seen.remove(prevLower);







        seen.add(lower);







        isDuplicate = true;







        break;







      }







    }















    if (!isDuplicate) {







      seen.add(lower);







      cleaned.add(segment);







    }







  }







  return cleaned.join(', ');







}















String formatPlacemarkAddress(Placemark p) {







  final candidates = [







    p.name,







    p.street,







    p.subLocality,







    p.locality,







    p.subAdministrativeArea,







    p.administrativeArea,







    p.postalCode,







    p.country,







  ];







  return cleanAddress(candidates.whereType<String>().join(', '));







}















String formatVisitTime(dynamic inUtc, dynamic outUtc) {







  if (inUtc == null) return 'Time not recorded';







  final start = DateTime.tryParse('$inUtc')?.toLocal();







  if (start == null) return '$inUtc';















  final startStr = _format12Hour(start);







  if (outUtc == null) {







    return 'Started at $startStr • In progress';







  }















  final end = DateTime.tryParse('$outUtc')?.toLocal();







  if (end == null) return startStr;















  final endStr = _format12Hour(end);







  final durMin = end.difference(start).inMinutes;







  final durStr = durMin > 0 ? '$durMin min stay' : '< 1 min stay';















  final now = DateTime.now();







  final isToday = start.year == now.year && start.month == now.month && start.day == now.day;







  final datePrefix = isToday ? '' : '${start.day}/${start.month} · ';















  return '$datePrefix$startStr – $endStr • $durStr';







}















String _format12Hour(DateTime dt) {







  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;







  final minute = dt.minute.toString().padLeft(2, '0');







  final ampm = dt.hour < 12 ? 'AM' : 'PM';







  return '$hour:$minute $ampm';







}















int visitIdOf(Json row) {







  final val = row['id'] ?? row['Id'] ?? row['localId'] ?? row['LocalId'];







  if (val is num) return val.toInt();







  if (val != null) return int.tryParse(val.toString()) ?? 0;







  return 0;







}















bool visitCheckoutReady(Json row, DateTime now) => true;















class SalesmanVisitShortcut extends StatefulWidget {







  final TrackyuController controller;







  final bool enabled;







  const SalesmanVisitShortcut({







    super.key,







    required this.controller,







    this.enabled = true,







  });















  @override







  State<SalesmanVisitShortcut> createState() => _SalesmanVisitShortcutState();







}















class _SalesmanVisitShortcutState extends State<SalesmanVisitShortcut> {







  Timer? _ticker;







  Json? _active;















  @override







  void initState() {







    super.initState();







    widget.controller.addListener(_onControllerChanged);







    _checkActiveVisit();







  }















  @override







  void dispose() {







    _ticker?.cancel();







    widget.controller.removeListener(_onControllerChanged);







    super.dispose();







  }















  void _onControllerChanged() {







    if (!mounted) return;







    _checkActiveVisit();







  }















  Future<void> _checkActiveVisit() async {







    final scope=widget.controller.visitCacheScope, workspace=widget.controller.local;
    await widget.controller.scopedVisitCache();
    if(!mounted || scope!=widget.controller.visitCacheScope || !identical(workspace,widget.controller.local))return;
    if (!widget.controller.onDuty) {







      if (mounted && _active != null) {







        setState(() => _active = null);







        _ensureTicker();







      }







      return;







    }







    if (widget.controller.hasPendingVisitClose) {







      if (mounted && _active != null) {







        setState(() => _active = null);







        _ensureTicker();







      }







      return;







    }







    Json? found = widget.controller.activeVisit;







    final todayStr = widget.controller.localDay;







    if (found != null) {







      final vDate = found['workDate']?.toString();







      final isDone = visitClosed(found);







      if ((vDate != null && vDate.isNotEmpty && vDate != todayStr) || isDone) {







        found = null;







        widget.controller.activeVisit = null;







      }







    }







    if (found == null) {







      if (widget.controller.local != null) {







        final day = await widget.controller.localDayData();







        final visits = jsonRows(day['visits'] ?? []);







        found = visits.where((r) => !widget.controller.isVisitClosedOrClosing(r) && !visitClosed(r) && widget.controller.pendingVisits.any((p) => p['finish'] != true && !queuedRegularVisit(p) && p['body'] is Map && sameVisit(r, Map<String, dynamic>.from(p['body'] as Map))) &&







                (r['workDate'] == null ||







                    r['workDate'] == '' ||







                    r['workDate'] == todayStr))







            .firstOrNull;







      }







      if (found == null) {







        final pending = widget.controller.pendingVisits







            .where((p) => p['scope']==scope && p['finish'] != true && !queuedRegularVisit(p) && p['body'] is Map && !widget.controller.isVisitClosedOrClosing(Map<String,dynamic>.from(p['body'] as Map)))







            .firstOrNull;







        if (pending != null && pending['body'] is Map) {







          found = Map<String, dynamic>.from(pending['body'] as Map);







        }







      }







      if (found == null) {







        final cached = await widget.controller.scopedVisitCache();







        found = cached.where((r) => !widget.controller.isVisitClosedOrClosing(r) && !visitClosed(r) && widget.controller.pendingVisits.any((p) => p['finish'] != true && !queuedRegularVisit(p) && p['body'] is Map && sameVisit(r, Map<String, dynamic>.from(p['body'] as Map))) &&







                (r['workDate'] == null ||







                    r['workDate'] == '' ||







                    r['workDate'] == todayStr))







            .firstOrNull;







      }







    }







    if (!mounted || scope!=widget.controller.visitCacheScope || !identical(workspace,widget.controller.local)) return;
    if(found!=null && widget.controller.isVisitClosedOrClosing(found))found=null;







    if (found != _active) {







      setState(() {







        _active = found;







      });







      _ensureTicker();







    }







  }















  void _ensureTicker() {







    if (_active != null) {







      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {







        if (mounted && _active != null) {







          setState(() {});







          final start = DateTime.tryParse('');







          if (start != null) {







            final elapsedMins = DateTime.now().toUtc().difference(start.toUtc()).inMinutes;







            if (elapsedMins >= 120 && !VisitOverstayAlertSheet.isSnoozed) {







              VisitOverstayAlertSheet.show(







                context: context,







                controller: widget.controller,







                visit: _active!,







                elapsedMinutes: elapsedMins,







              );







            }







          }







        }







      });







    } else {







      _ticker?.cancel();







      _ticker = null;







    }







  }















  bool _isNavigating = false;















  Future<void> _punchOutVisit(BuildContext context, Json visit) async {







    if (_isNavigating) return;







    setState(() => _isNavigating = true);







    try {







      final data = VisitsData(widget.controller);







      await data.load();







      if (!context.mounted) return;

      // Auto-heal if visit is already confirmed closed on server
      final isAlreadyClosedOnServer = visitClosed(visit) ||
          widget.controller.isVisitClosedOrClosing(visit) ||
          data.rows.any((r) => sameVisit(r, visit) && visitClosed(r)) ||
          (data.active == null && !data.rows.any((r) => sameVisit(r, visit) && !visitClosed(r)));

      if (isAlreadyClosedOnServer) {
        widget.controller.clearActiveVisit();
        widget.controller.clearClosingVisit();
        if (mounted) setState(() => _active = null);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Visit checkout already confirmed by server."),
              backgroundColor: Color(0xff059669),
            ),
          );
        }
        return;
      }








      final saved = await Navigator.of(context).push<bool>(







        MaterialPageRoute(







          builder: (_) => VisitForm(data: data, visit: visit),







        ),







      );







      if (saved == true) {
        widget.controller.clearActiveVisit();
        if (mounted) setState(() => _active = null);







        widget.controller.setClosingVisit(







          shopName: visit['shopName'] ?? visit['clientName'],







          id: '${visit['id'] ?? visit['localId']}',







        );







        if (mounted) {







          setState(() {







            _active = null;







          });







          _ensureTicker();







        }







        if (context.mounted) {







          ScaffoldMessenger.of(context).showSnackBar(







            const SnackBar(content: Text('Open visit updated.')),







          );







        }







        try {







          await widget.controller.refresh();







        } finally {







          widget.controller.clearClosingVisit();







        }







        if (mounted) _checkActiveVisit();







      }







    } finally {







      if (mounted) setState(() => _isNavigating = false);







    }







  }















  void _openVisitsPage() {







    if (_isNavigating) return;







    setState(() => _isNavigating = true);







    Navigator.push(







      context,







      MaterialPageRoute<void>(







        builder: (_) => VisitsPage(controller: widget.controller),







      ),







    ).then((_) {







      if (mounted) {







        _checkActiveVisit();







        setState(() => _isNavigating = false);







      }







    }).catchError((_) {







      if (mounted) setState(() => _isNavigating = false);







    });







  }















  @override







  Widget build(BuildContext context) {







    if (!widget.controller.onDuty) {







      return const SizedBox.shrink();







    }







    final isDark = widget.controller.isDarkMode;















    final isActivelyClosing = widget.controller.isClosingVisit;

    final hasPendingFinish = widget.controller.pendingVisits.any((p) => p['scope']==widget.controller.visitCacheScope && !queuedRegularVisit(p) && p['finish'] == true && p['durable']!=false);

    final isClosing = isActivelyClosing || hasPendingFinish;







    if (isClosing) {







      final closingShop = widget.controller.closingVisitShopName ??







          (_active != null ? (_active!['shopName'] ?? _active!['clientName']) : null) ??







          'Open Visit';















      return Container(







        decoration: BoxDecoration(







          borderRadius: BorderRadius.circular(20),







          gradient: LinearGradient(







            colors: isDark







                ? [const Color(0xff1e293b), const Color(0xff0f172a)]







                : [const Color(0xffeff6ff), const Color(0xffdbeafe)],







            begin: Alignment.topLeft,







            end: Alignment.bottomRight,







          ),







          border: Border.all(







            color: isDark ? const Color(0xff3b82f6).withValues(alpha: 0.6) : const Color(0xff60a5fa),







            width: 1.5,







          ),







          boxShadow: [







            BoxShadow(







              color: const Color(0xff3b82f6).withValues(alpha: isDark ? 0.2 : 0.12),







              blurRadius: 16,







              offset: const Offset(0, 4),







            ),







          ],







        ),







        padding: const EdgeInsets.all(16),







        child: Column(







          crossAxisAlignment: CrossAxisAlignment.start,







          children: [







            Row(







              children: [







                Container(







                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),







                  decoration: BoxDecoration(







                    color: isDark ? const Color(0xff1e3a5f) : const Color(0xffdbeafe),







                    borderRadius: BorderRadius.circular(12),







                    border: Border.all(







                      color: isDark ? const Color(0xff3b82f6).withValues(alpha: 0.5) : const Color(0xff93c5fd),







                    ),







                  ),







                  child: Row(







                    mainAxisSize: MainAxisSize.min,







                    children: [







                      SizedBox(







                        width: 10,







                        height: 10,







                        child: CircularProgressIndicator(







                          strokeWidth: 2,







                          color: isDark ? const Color(0xff60a5fa) : const Color(0xff2563eb),







                        ),







                      ),







                      const SizedBox(width: 7),







                      Text(







                        isActivelyClosing ? 'CLOSING VISIT...' : 'SAVED LOCALLY',







                        style: TextStyle(







                          fontSize: 11,







                          fontWeight: FontWeight.w800,







                          letterSpacing: 0.4,







                          color: isDark ? const Color(0xff93c5fd) : const Color(0xff1d4ed8),







                        ),







                      ),







                    ],







                  ),







                ),







                const Spacer(),







                Container(







                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),







                  decoration: BoxDecoration(







                    color: isDark ? const Color(0xff1e293b) : Colors.white.withValues(alpha: 0.8),







                    borderRadius: BorderRadius.circular(8),







                    border: Border.all(







                      color: isDark ? const Color(0xff334155) : const Color(0xffbfdbfe),







                    ),







                  ),







                  child: Row(







                    mainAxisSize: MainAxisSize.min,







                    children: [







                      Icon(







                        Icons.sync_rounded,







                        size: 12,







                        color: isDark ? const Color(0xff60a5fa) : const Color(0xff2563eb),







                      ),







                      const SizedBox(width: 4),







                      Text(







                        isActivelyClosing ? 'Updating' : 'Sync Pending',







                        style: TextStyle(







                          fontSize: 11,







                          fontWeight: FontWeight.w600,







                          color: isDark ? const Color(0xffcbd5e1) : const Color(0xff1e40af),







                        ),







                      ),







                    ],







                  ),







                ),







              ],







            ),







            const SizedBox(height: 12),







            Row(







              crossAxisAlignment: CrossAxisAlignment.start,







              children: [







                Container(







                  width: 44,







                  height: 44,







                  decoration: BoxDecoration(







                    color: isDark ? const Color(0xff172554) : const Color(0xffdbeafe),







                    borderRadius: BorderRadius.circular(12),







                    border: Border.all(







                      color: isDark ? const Color(0xff1d4ed8).withValues(alpha: 0.4) : const Color(0xffbfdbfe),







                    ),







                  ),







                  child: const Icon(







                    Icons.storefront_rounded,







                    color: Color(0xff2563eb),







                    size: 24,







                  ),







                ),







                const SizedBox(width: 12),







                Expanded(







                  child: Column(







                    crossAxisAlignment: CrossAxisAlignment.start,







                    children: [







                      Text(







                        '$closingShop',







                        style: TextStyle(







                          fontSize: 17,







                          fontWeight: FontWeight.w800,







                          letterSpacing: -0.3,







                          color: isDark ? Colors.white : const Color(0xff0f172a),







                        ),







                        maxLines: 1,







                        overflow: TextOverflow.ellipsis,







                      ),







                      const SizedBox(height: 3),







                      Text(







                        isActivelyClosing ? 'Saving departure photo & syncing checkout...' : 'Departure photo & checkout saved on phone',







                        style: TextStyle(







                          fontSize: 12,







                          fontWeight: FontWeight.w500,







                          color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),







                        ),







                      ),







                    ],







                  ),







                ),







              ],







            ),







            const SizedBox(height: 12),







            ClipRRect(







              borderRadius: BorderRadius.circular(6),







              child: LinearProgressIndicator(







                minHeight: 5,







                backgroundColor: isDark ? const Color(0xff1e3a5f) : const Color(0xffbfdbfe),







                valueColor: AlwaysStoppedAnimation<Color>(







                  isDark ? const Color(0xff60a5fa) : const Color(0xff2563eb),







                ),







              ),







            ),







            const SizedBox(height: 12),







            InkWell(

              onTap: isActivelyClosing ? null : () => widget.controller.syncPendingVisits(),

              borderRadius: BorderRadius.circular(12),

              child: Container(







              width: double.infinity,







              padding: const EdgeInsets.symmetric(vertical: 10),







              decoration: BoxDecoration(







                color: isDark ? const Color(0xff1e293b) : Colors.white,







                borderRadius: BorderRadius.circular(12),







                border: Border.all(







                  color: isDark ? const Color(0xff334155) : const Color(0xffbfdbfe),







                ),







              ),







              child: Row(







                mainAxisAlignment: MainAxisAlignment.center,







                children: [







                  if (isActivelyClosing)

                    SizedBox(

                      width: 14,

                      height: 14,

                      child: CircularProgressIndicator(

                        strokeWidth: 2,

                        color: isDark ? const Color(0xff60a5fa) : const Color(0xff2563eb),

                      ),

                    )

                  else

                    Icon(

                      Icons.cloud_upload_outlined,

                      size: 16,

                      color: isDark ? const Color(0xff60a5fa) : const Color(0xff2563eb),

                    ),







                  const SizedBox(width: 8),







                  Text(







                    isActivelyClosing ? 'Closing Open Visit • Please wait...' : 'Sync Checkout Now',







                    style: TextStyle(







                      fontSize: 12.5,







                      fontWeight: FontWeight.w700,







                      color: isDark ? const Color(0xff93c5fd) : const Color(0xff1d4ed8),







                    ),







                  ),







                ],







              ),







            ),),







            const SizedBox(height: 10),

            Row(

              children: [

                Expanded(

                  child: TextButton.icon(

                    onPressed: widget.enabled && !_isNavigating

                        ? _openVisitsPage

                        : null,

                    icon: const Icon(Icons.storefront_outlined, size: 16),

                    label: const Text('Client visits', style: TextStyle(fontSize: 12)),

                  ),

                ),

                TextButton.icon(

                  onPressed: () async {

                    await widget.controller.forceClearStuckVisitClose();

                    if (mounted) {

                      setState(() => _active = null);

                      _checkActiveVisit();

                    }

                  },

                  icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.blueAccent),

                  label: const Text('Dismiss banner', style: TextStyle(fontSize: 12, color: Colors.blueAccent)),

                ),

              ],

            ),

            const Text(

              'Pending checkout and photos stay saved until the server confirms them.',

              style: TextStyle(fontSize: 11, color: Color(0xff94a3b8)),

            ),

          ],







        ),







      );







    }















    if (!widget.controller.onDuty) {



      return const SizedBox.shrink();



    }







    final todayStr = widget.controller.localDay;



    bool isVisitToday(Json? v) {
      if (v == null) return false;
      if (visitClosed(v) || widget.controller.isVisitClosedOrClosing(v)) return false;



      final vDate = v['workDate']?.toString();



      if (vDate != null && vDate.isNotEmpty && vDate != todayStr) return false;



      final start = DateTime.tryParse('');



      if (start != null) {



        final startDay = "--";



        if (startDay != todayStr) return false;



      }



      return true;



    }







    final ctrlActive = widget.controller.activeVisit;



    final isCtrlActiveValid = isVisitToday(ctrlActive);







    final localActive = _active;



    final isLocalActiveValid = isVisitToday(localActive);







    final active = isCtrlActiveValid ? ctrlActive : null;
    if (active == null && _active != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _active != null) {
          setState(() => _active = null);
        }
      });
    }















    if (active != null) {







      final start = DateTime.tryParse('${active['checkInUtc']}');







      final checkInStr = start != null ? _format12Hour(start.toLocal()) : '--:--';







      final seconds = start != null







          ? DateTime.now().toUtc().difference(start.toUtc()).inSeconds.clamp(0, 864000)







          : 0;







      final elapsed =







          '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';







      final shopName = active['shopName']?.toString().trim().isNotEmpty == true







          ? active['shopName'].toString()







          : (active['clientName']?.toString().trim().isNotEmpty == true







              ? active['clientName'].toString()







              : 'Open visit');







      final place = cleanAddress(active['placeName']?.toString() ?? active['address']?.toString());







      final isRegular = active['kind'] == 'Regular';







      final canPunchOut = visitCheckoutReady(active, DateTime.now());







      final isOverstay = seconds >= 7200;















      return Container(







        decoration: BoxDecoration(







          borderRadius: BorderRadius.circular(20),







          gradient: LinearGradient(







            colors: isOverstay







                ? (isDark







                    ? [const Color(0xff3f0714), const Color(0xff1f020a)]







                    : [const Color(0xfffff1f2), const Color(0xffffe4e6)])







                : (isDark







                    ? [const Color(0xff291a0a), const Color(0xff1c150c)]







                    : [const Color(0xfffffbeb), const Color(0xfffef3c7)]),







            begin: Alignment.topLeft,







            end: Alignment.bottomRight,







          ),







          border: Border.all(







            color: isOverstay







                ? const Color(0xfff43f5e)







                : (isDark ? const Color(0xfff59e0b).withValues(alpha: 0.6) : const Color(0xfff59e0b)),







            width: isOverstay ? 2.0 : 1.5,







          ),







          boxShadow: [







            BoxShadow(







              color: (isOverstay







                      ? const Color(0xfff43f5e)







                      : (isDark ? const Color(0xfff59e0b) : const Color(0xffd97706)))







                  .withValues(alpha: isOverstay ? 0.25 : 0.14),







              blurRadius: 16,







              offset: const Offset(0, 4),







            ),







          ],







        ),







        child: Material(







          color: Colors.transparent,







          child: InkWell(







            borderRadius: BorderRadius.circular(20),







            onTap: (widget.enabled && !_isNavigating) ? _openVisitsPage : null,







            child: Padding(







              padding: const EdgeInsets.all(16),







              child: Column(







                crossAxisAlignment: CrossAxisAlignment.start,







                children: [







                  // Top Badges Row







                  Row(







                    children: [







                      Container(







                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),







                        decoration: BoxDecoration(







                          color: isOverstay







                              ? (isDark ? const Color(0xff881337) : const Color(0xffffe4e6))







                              : (isDark ? const Color(0xff78350f) : const Color(0xffffedd5)),







                          borderRadius: BorderRadius.circular(12),







                          border: Border.all(







                            color: isOverstay







                                ? const Color(0xfff43f5e)







                                : (isDark







                                    ? const Color(0xfff59e0b).withValues(alpha: 0.5)







                                    : const Color(0xfffdba74)),







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







                                color: isOverstay ? const Color(0xffe11d48) : const Color(0xffea580c),







                              ),







                            ),







                            const SizedBox(width: 5),







                            Text(







                              isOverstay ? '🚨 OVERSTAY ALERT (> 2H)' : 'VISIT IN PROGRESS',







                              style: TextStyle(







                                fontSize: 11,







                                fontWeight: FontWeight.w800,







                                letterSpacing: 0.4,







                                color: isOverstay







                                    ? (isDark ? const Color(0xfffecdd3) : const Color(0xffe11d48))







                                    : (isDark ? const Color(0xfffef08a) : const Color(0xffc2410c)),







                              ),







                            ),







                          ],







                        ),







                      ),







                      const Spacer(),







                      Container(







                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),







                        decoration: BoxDecoration(







                          color: isDark ? const Color(0xff1e293b) : Colors.white.withValues(alpha: 0.8),







                          borderRadius: BorderRadius.circular(8),







                          border: Border.all(







                            color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),







                          ),







                        ),







                        child: Text(







                          isRegular ? 'Retailer' : 'Open visit',







                          style: TextStyle(







                            fontSize: 11,







                            fontWeight: FontWeight.w600,







                            color: isDark ? const Color(0xffcbd5e1) : const Color(0xff475569),







                          ),







                        ),







                      ),







                    



],







                  ),







                  const SizedBox(height: 12),















                  // Store Info Row







                  Row(







                    crossAxisAlignment: CrossAxisAlignment.start,







                    children: [







                      Container(







                        width: 44,







                        height: 44,







                        decoration: BoxDecoration(







                          color: isDark ? const Color(0xff451a03) : const Color(0xffffedd5),







                          borderRadius: BorderRadius.circular(12),







                          border: Border.all(







                            color: isDark







                                ? const Color(0xffb45309).withValues(alpha: 0.4)







                                : const Color(0xfffed7aa),







                          ),







                        ),







                        child: const Icon(







                          Icons.storefront_rounded,







                          color: Color(0xffea580c),







                          size: 24,







                        ),







                      ),







                      const SizedBox(width: 12),







                      Expanded(







                        child: Column(







                          crossAxisAlignment: CrossAxisAlignment.start,







                          children: [







                            Text(







                              shopName,







                              style: TextStyle(







                                fontSize: 17,







                                fontWeight: FontWeight.w800,







                                letterSpacing: -0.3,







                                color: isDark ? Colors.white : const Color(0xff0f172a),







                              ),







                              maxLines: 1,







                              overflow: TextOverflow.ellipsis,







                            ),







                            if (place.isNotEmpty) ...[







                              const SizedBox(height: 2),







                              Row(







                                children: [







                                  const Icon(







                                    Icons.place_rounded,







                                    size: 13,







                                    color: Color(0xffea580c),







                                  ),







                                  const SizedBox(width: 3),







                                  Expanded(







                                    child: Text(







                                      place,







                                      style: TextStyle(







                                        fontSize: 12,







                                        fontWeight: FontWeight.w500,







                                        color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),







                                      ),







                                      maxLines: 1,







                                      overflow: TextOverflow.ellipsis,







                                    ),







                                  ),







                                ],







                              ),







                            ],







                          ],







                        ),







                      ),







                    ],







                  ),







                  const SizedBox(height: 12),















                  // Timer & Check-in Details Bar







                  Container(







                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),







                    decoration: BoxDecoration(







                      color: isDark ? const Color(0xff17120a) : Colors.white,







                      borderRadius: BorderRadius.circular(12),







                      border: Border.all(







                        color: isDark







                            ? const Color(0xff78350f).withValues(alpha: 0.35)







                            : const Color(0xfffed7aa),







                      ),







                    ),







                    child: Row(







                      mainAxisAlignment: MainAxisAlignment.spaceBetween,







                      children: [







                        Row(







                          children: [







                            Icon(







                              Icons.login_rounded,







                              size: 14,







                              color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),







                            ),







                            const SizedBox(width: 5),







                            Text(







                              'In: $checkInStr',







                              style: TextStyle(







                                fontSize: 12,







                                fontWeight: FontWeight.w600,







                                color: isDark ? const Color(0xffcbd5e1) : const Color(0xff475569),







                              ),







                            ),







                          ],







                        ),







                        Row(







                          children: [







                            const Icon(







                              Icons.timer_outlined,







                              size: 14,







                              color: Color(0xffea580c),







                            ),







                            const SizedBox(width: 5),







                            Text(







                              elapsed,







                              style: const TextStyle(







                                fontSize: 13,







                                fontWeight: FontWeight.w800,







                                fontFamily: 'monospace',







                                color: Color(0xffea580c),







                              ),







                            ),







                          ],







                        ),







                      ],







                    ),







                  ),







                  const SizedBox(height: 12),















                  // Action Buttons Row







                  Row(







                    children: [







                      Expanded(







                        child: FilledButton.icon(







                          style: FilledButton.styleFrom(







                            backgroundColor: isOverstay ? const Color(0xfff43f5e) : const Color(0xffea580c),







                            foregroundColor: Colors.white,







                            padding: const EdgeInsets.symmetric(vertical: 11),







                            shape: RoundedRectangleBorder(







                              borderRadius: BorderRadius.circular(12),







                            ),







                            elevation: 0,







                          ),







                          onPressed: widget.enabled







                              ? (canPunchOut ? () => _punchOutVisit(context, active) : null)







                              : null,







                          icon: const Icon(Icons.check_circle_rounded, size: 17),







                          label: Text(







                            isOverstay ? 'Complete Visit & Clear Alert' : 'Check Out Visit',







                            style: const TextStyle(







                              fontSize: 13,







                              fontWeight: FontWeight.w700,







                            ),







                          ),







                        ),







                      ),







                      const SizedBox(width: 8),







                      Material(







                        color: isDark ? const Color(0xff332415) : const Color(0xffffedd5),







                        borderRadius: BorderRadius.circular(12),







                        child: InkWell(







                          borderRadius: BorderRadius.circular(12),







                          onTap: (widget.enabled && !_isNavigating) ? _openVisitsPage : null,







                          child: Container(







                            padding: const EdgeInsets.all(11),







                            decoration: BoxDecoration(







                              borderRadius: BorderRadius.circular(12),







                              border: Border.all(







                                color: isDark ? const Color(0xff78350f) : const Color(0xfffed7aa),







                              ),







                            ),







                            child: const Icon(







                              Icons.arrow_forward_rounded,







                              size: 18,







                              color: Color(0xffea580c),







                            ),







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







      );







    }















    // Default Salesman Visit shortcut when no visit is in progress







    final c = widget.controller;







    final isLux = c.isLuxuryMode;















    return Material(







      color: Colors.transparent,







      borderRadius: BorderRadius.circular(20),







      child: InkWell(







        borderRadius: BorderRadius.circular(20),







        onTap: (widget.enabled && !_isNavigating) ? _openVisitsPage : null,







        child: Container(







          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),







          decoration: BoxDecoration(







            gradient: isDark







                ? const LinearGradient(







                    colors: [Color(0xff131b2e), Color(0xff0d1322)],







                    begin: Alignment.topLeft,







                    end: Alignment.bottomRight,







                  )







                : (isLux







                    ? LinearGradient(







                        colors: c.themeCardGradient,







                        begin: Alignment.topLeft,







                        end: Alignment.bottomRight,







                      )







                    : null),







            color: (isDark || isLux) ? null : Colors.white,







            borderRadius: BorderRadius.circular(20),







            border: Border.all(







              color: isDark







                  ? const Color(0xff1e293b)







                  : (isLux ? Colors.white.withValues(alpha: 0.95) : const Color(0xffe2e8f0)),







              width: isLux ? 1.5 : 1.0,







            ),







            boxShadow: [







              BoxShadow(







                color: isDark







                    ? Colors.black.withValues(alpha: 0.3)







                    : (isLux







                        ? c.themePrimaryColor.withValues(alpha: 0.08)







                        : const Color(0xff10b981).withValues(alpha: 0.06)),







                blurRadius: 18,







                offset: const Offset(0, 5),







              ),







            ],







          ),







          child: Row(







            children: [







              Container(







                padding: const EdgeInsets.all(11),







                decoration: BoxDecoration(







                  gradient: const LinearGradient(







                    colors: [Color(0xff10b981), Color(0xff059669)],







                    begin: Alignment.topLeft,







                    end: Alignment.bottomRight,







                  ),







                  borderRadius: BorderRadius.circular(14),







                  boxShadow: [







                    BoxShadow(







                      color: const Color(0xff10b981).withValues(alpha: 0.28),







                      blurRadius: 10,







                      offset: const Offset(0, 3),







                    ),







                  ],







                ),







                child: const Icon(







                  Icons.storefront_rounded,







                  color: Colors.white,







                  size: 22,







                ),







              ),







              const SizedBox(width: 14),







              Expanded(







                child: Column(







                  crossAxisAlignment: CrossAxisAlignment.start,







                  children: [







                    Text(







                      'Client visits',







                      style: TextStyle(







                        fontSize: 15.5,







                        fontWeight: FontWeight.w700,







                        letterSpacing: -0.2,







                        color: isDark ? Colors.white : const Color(0xff0f172a),







                      ),







                    ),







                    const SizedBox(height: 3),







                    Text(







                      'Client check-in with selfie & GPS location',







                      maxLines: 1,







                      overflow: TextOverflow.ellipsis,







                      style: TextStyle(







                        fontSize: 12,







                        fontWeight: FontWeight.w500,







                        color: isDark







                            ? const Color(0xff94a3b8)







                            : const Color(0xff64748b),







                      ),







                    ),







                  ],







                ),







              ),







              Container(







                width: 32,







                height: 32,







                decoration: BoxDecoration(







                  color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),







                  shape: BoxShape.circle,







                ),







                child: Icon(







                  Icons.chevron_right_rounded,







                  size: 20,







                  color: isDark







                      ? const Color(0xff94a3b8)







                      : const Color(0xff64748b),







                ),







              ),







            ],







          ),







        ),







      ),







    );







  }







}















class VisitsData extends ChangeNotifier {







  final TrackyuController session;







  final Future<String?> Function() capture;







  VisitsData(this.session, {Future<String?> Function()? capture})







    : capture = capture ?? capturePunchSelfie;







  List<Json> rows = [], retailers = [];







  bool loading = false, saving = false, disposed = false;







  String? error;







  String startKey = const Uuid().v4(), finishKey = const Uuid().v4();







  Json? get active {







    final todayStr = session.localDay;







    final rowActive = rows







        .where((r) => !session.isVisitClosedOrClosing(r) &&







            !session.isVisitClosedOrClosing(r) && !visitClosed(r) && !unconfirmedRegularVisit(r) && (r['workDate'] == null || r['workDate'] == '' || r['workDate'] == todayStr || r['WorkDate'] == todayStr))







        .firstOrNull;







    if (rowActive != null) return rowActive;







    if (session.activeVisit != null && !visitClosed(session.activeVisit!) && !session.isVisitClosedOrClosing(session.activeVisit!)) {
      return session.activeVisit;
    }







    final pending = session.pendingVisits







        .where((p) {

          if (p['scope'] != '${session.api.baseUrl}|${session.employeeId}' ||

              p['finish'] == true || p['body'] is! Map || session.isVisitClosedOrClosing(Map<String,dynamic>.from(p['body'] as Map))) return false;

          final requestId = p['body']['requestId'];

          return !rows.any((r) => requestId != null &&

              r['requestId'] == requestId &&

              visitClosed(r));

        })







        .firstOrNull;







    if (pending != null && pending['body'] is Map) {







      return Map<String, dynamic>.from(pending['body'] as Map);







    }







    return null;







  }







  Future<dynamic> request(String route, {Json? body}) async {







    try {







      return await session.api.request(route, body: body);







    } on ApiFailure catch (e) {







      // Netflix permanent login: do not auto-logout on 401







      if (e.status == 401) { session.api.sessionRejected = true; }







      rethrow;







    }







  }















  Future<void> loadCachedVisits({String? date}) async {







    final targetDate = date ?? session.localDay;







    if (session.local != null) {







      final day = await session.localDayData(targetDate);







      var dayVisits = jsonRows(day['visits'] ?? []);







      if (dayVisits.isEmpty) {







        final pending = session.pendingVisits;







        dayVisits = pending.where((r) {







          final wd = (r['workDate'] ?? r['WorkDate'])?.toString();







          if (wd != null && wd.contains(targetDate)) return true;







          final inUtc = (r['checkInUtc'] ?? r['CheckInUtc'] ?? r['createdAtUtc'] ?? r['CreatedAtUtc'])?.toString();







          if (inUtc != null && inUtc.contains(targetDate)) return true;







          return false;







        }).toList();







      }







      rows = dayVisits;







      return;







    }







    try {







      final raw = await session.vault.readCachedVisits();







      if (raw != null && raw.isNotEmpty) {







        final decoded = jsonDecode(raw);







        if (decoded is Map &&







            decoded['scope'] == session.visitCacheScope &&







            decoded['rows'] is List) {







          final allRows = (decoded['rows'] as List)







              .whereType<Map>()







              .map((e) => Map<String, dynamic>.from(e))







              .toList();







          if (targetDate == session.localDay) {







            rows = allRows;







          } else {







            rows = allRows.where((r) {







              final wd = r['workDate']?.toString();







              if (wd != null && wd.contains(targetDate)) return true;







              final inUtc = r['checkInUtc']?.toString();







              if (inUtc != null && inUtc.contains(targetDate)) return true;







              return false;







            }).toList();







          }







        }







      }







    } catch (_) {}







  }















  Future<void> saveCachedVisits() async {
    await session.saveVisitCacheRows(rows);
    rows=await session.scopedVisitCache();
  }
  Future<void> _recordOfflineVisit({







    required bool finish,







    required Json fields,







    required Json point,







    required bool needsSelfie,







    required String? photo,







  }) async {







    final nowUtc =







        point['capturedAtUtc']?.toString() ??







        DateTime.now().toUtc().toIso8601String();







    final operationId = finish ? finishKey : startKey;















    if (finish) {







      final targetId = fields['id'] ?? fields['localId'];







      int idx = checkoutVisitIndex(rows, targetId);



      if (idx < 0 && active != null &&

          checkoutVisitIndex([active!], targetId) == 0) {

        rows = [Map<String, dynamic>.from(active!), ...rows];

        idx = 0;

      }

      if (idx < 0) {

        throw const ApiFailure('VISIT_NOT_FOUND',

            'Selected visit is not available on this phone. Refresh visits before retrying; saved data is retained.');

      }



      if (idx >= 0) {







        final before = rows[idx];







        final localId = before['localId'] ?? before['id'];







        final serverVisitId = before['serverId'] ?? (before['isOffline'] != true ? before['id'] : null);







        final reqBody = {







          ...fields,







          ...point,







          'requestId': finishKey,

          if (before['requestId'] != null) 'startRequestId': before['requestId'],







          if (needsSelfie) 'departureSelfieBase64': photo,







          if (serverVisitId != null) 'id': serverVisitId,







        };







        if (serverVisitId == null) {







          reqBody.remove('id');







        }







        rows[idx] = {







          ...rows[idx],







          'checkOutUtc': nowUtc,







          'outLatitude': point['latitude'],







          'outLongitude': point['longitude'],







          'remark': fields['remark'],







          'ownerName': fields['ownerName'],







          'mobile': fields['mobile'],







          'lead': fields['lead'],







          'orderRemark': fields['orderRemark'],







          'otherRemark': fields['otherRemark'],







          if (needsSelfie) 'departureSelfieBase64': photo,







          if (needsSelfie) 'hasDepartureSelfie': photo != null,







          'isOffline': true,







        };







        finishKey = const Uuid().v4();























        if (session.local != null) {







          final refs = <String, dynamic>{};







          if (before['serverId'] == null &&







              before['requestId'] != null &&







              before['isOffline'] == true) {







            refs['id'] = {'operationId': before['requestId'], 'field': 'id'};







            refs['version'] = {







              'operationId': before['requestId'],







              'field': 'version',







            };







            reqBody['version'] ??= 'pending';







          }







          final day = await session.localDayData();







          await session.commitLocal(







            {...day, 'visits': rows},







            {







              'id': operationId,







              'route': 'MobileVisits/finish',







              'body': reqBody,







              'localId': localId,







              'refs': refs,







            },







          );







        } else {







          await session.queuePendingVisit(finish: true, body: reqBody);
          await saveCachedVisits();







        }
        session.markVisitClosedInMemory(rows[idx]);
        await session.persistVisitClose(rows[idx]);
        session.clearActiveVisit();







      } else {







        session.clearActiveVisit();







        session.clearClosingVisit();







        return;







      }







    } else {







      final localId = DateTime.now().microsecondsSinceEpoch;







      final reqBody = {







        ...fields,







        ...point,







        'requestId': startKey,







        'photoBase64': photo,







      };







      final localVisit = {







        'id': localId,







        'localId': localId,







        'requestId': startKey,







        'retailerId': fields['retailerId'],







        'shopName': fields['shopName'] ?? fields['clientName'] ?? 'Open Visit',







        'placeName': fields['placeName'] ?? '',







        'clientName': fields['clientName'] ?? fields['shopName'] ?? 'Client',







        'address': fields['address'] ?? point['address'] ?? 'Recorded via GPS',







        'checkInUtc': nowUtc,







        'earliestCheckoutUtc': DateTime.parse(nowUtc)







            .add(Duration(minutes: fields['kind'] == 'Regular' ? 10 : 0))







            .toIso8601String(),







        'inLatitude': point['latitude'],







        'inLongitude': point['longitude'],







        'kind': fields['kind'] ?? 'Open',







        'isOffline': true,







        'syncState': 'pending',







        'photoBase64': photo,







        'hasArrivalSelfie': photo != null,







        'workDate': session.localDay,







      };







      rows = [localVisit, ...rows];







      startKey = const Uuid().v4();















      if (session.local != null) {







        final day = await session.localDayData();







        await session.commitLocal(







          {...day, 'visits': rows},







          {







            'id': operationId,







            'route': 'MobileVisits/start',







            'body': reqBody,







            'localId': localId,







          },







        );







      } else {







        await saveCachedVisits();







        await session.queuePendingVisit(finish: false, body: reqBody);







      }







    }







    session.notice =







        'Visit recorded offline on phone. Will sync when server is reachable.';







  }















  Future<void> load({String? date}) async {







    if (loading || disposed) return;







    loading = true;







    error = null;







    notifyListeners();







    final queryDate = date ?? session.localDay;

    final loadScope = session.visitCacheScope;

    final loadWorkspace = session.local;







    try {







      if (!session.offline) {







        try {







          await session.refreshMenus();







        } catch (_) {}







      }







      if (session.offline) {







        await loadCachedVisits(date: queryDate);







      } else {







        try {







          final result = jsonRows(







            await request('MobileVisits/mine?date=$queryDate'),







          );







          if (!disposed && loadScope == session.visitCacheScope && identical(loadWorkspace, session.local)) {

            final day = loadWorkspace == null ? null : await session.localDayData(queryDate);

            if (disposed || loadScope != session.visitCacheScope || !identical(loadWorkspace, session.local)) return;

            final cached = day == null ? rows : jsonRows(day['visits'] ?? []);

            rows = mergePendingVisits(result, cached);

            if (queryDate == session.localDay) {
              await saveCachedVisits();
              if (session.local != null) {
                try {
                  final dayData = await session.localDayData(queryDate);
                  await session.local!.write(session.dayKey, {
                    ...dayData,
                    'visits': rows,
                  });
                } catch (_) {}
              }
            }




            if (rows.any((r) => r['requestId'] == startKey)) {







              startKey = const Uuid().v4();







            }







            if (rows.any((r) => r['closeRequestId'] == finishKey)) {







              finishKey = const Uuid().v4();







            }







          }







        } catch (_) {







          if (loadScope != session.visitCacheScope || !identical(loadWorkspace, session.local)) return;

          await loadCachedVisits(date: queryDate);







        }







      }







    } catch (e) {







      if (!disposed) {







        await loadCachedVisits(date: queryDate);







        session.setOffline(true);







        error = null;







      }







    } finally {

      if (loadScope == session.visitCacheScope && identical(loadWorkspace, session.local)) {

        session.activeVisit = active;

      }

      loading = false;







      if (!disposed) notifyListeners();







    }







  }















  Future<List<Json>> search(String query) async {







    final cache = await session.local?.read('retailers');







    final saved = jsonRows(cache?['rows'] ?? []);







    if (session.offline && session.local != null) {







      final term = query.trim().toLowerCase();







      return saved







          .where(







            (r) => '${r['id']} ${r['name']} ${r['place']}'







                .toLowerCase()







                .contains(term),







          )







          .toList();







    }







    final result = jsonRows(







      await request(







        'MobileVisits/retailers?search=${Uri.encodeQueryComponent(query.trim())}',







      ),







    );







    if (session.local != null) {







      await session.local!.write('retailers', {







        'rows': [







          ...result,







          ...saved.where((r) => !result.any((n) => n['id'] == r['id'])),







        ],







      });







    }







    return result;







  }















  Future<void> discard(Json visit) async {







    final targetId = visit['id'] ?? visit['Id'] ?? visit['localId'];







    final reqId = visit['requestId']?.toString();







    rows.removeWhere((r) =>







        (targetId != null &&







            (r['id']?.toString() == targetId.toString() ||







                r['localId']?.toString() == targetId.toString())) ||







        (reqId != null && reqId.isNotEmpty && r['requestId']?.toString() == reqId));















    if (session.local != null) {







      final day = await session.localDayData();







      final localVisits = jsonRows(day['visits'] ?? []);







      localVisits.removeWhere((r) =>







          (targetId != null &&







              (r['id']?.toString() == targetId.toString() ||







                  r['localId']?.toString() == targetId.toString())) ||







          (reqId != null && reqId.isNotEmpty && r['requestId']?.toString() == reqId));







      await session.local!.write(session.dayKey, {...day, 'visits': localVisits});







    } else {







      await saveCachedVisits();







    }







    session.clearActiveVisit();







    notifyListeners();







  }















  Future<bool> save({required bool finish, required Json fields}) async {







    if (saving || disposed) return false;







    final scope = session.visitCacheScope;
    final sentToken = session.api.dio.options.headers['Authorization'];
    final index = checkoutVisitIndex(rows, fields['id'] ?? fields['localId']);
    final existing = index >= 0 ? rows[index] : session.activeVisit;
    final existingKind = existing?['kind'];
    final normalizedKind = '${(finish ? existingKind : null) ?? fields['kind'] ?? existingKind ?? ''}'.trim().toLowerCase();
    final isRegular = normalizedKind == 'regular' || (existing?['isLegacy'] == true && '${existingKind ?? ''}'.trim().isEmpty) ||
        fields['retailerId'] != null || existing?['retailerId'] != null;
    bool current() => !disposed && scope == session.visitCacheScope && sentToken == session.api.dio.options.headers['Authorization'];
    saving = true;







    final beforeRows = rows.map((r) => Map<String, dynamic>.from(r)).toList();







    final beforeStartKey = startKey, beforeFinishKey = finishKey;







    notifyListeners();







    try {
      if (isRegular) {
        final reachable = await session.api.verifyPunchAccess();
        if (!current()) throw const ApiFailure('SESSION_CHANGED', 'Account changed. Open visits and retry.');
        if (!reachable) throw const ApiFailure('SERVER_REQUIRED', 'Regular visits require a live server connection. No offline visit was created.');
        session.setOffline(false);
      }







      if (!session.offline) {







        try {







          await session.refreshMenus();







        } catch (_) {}







      }







      session.requireVisitDuty();







      if (!finish && !session.menuEnabled('visits')) {







        if (!session.offline) {







          try {







            await session.refreshMenus();







          } catch (_) {}







        }







        if (!session.menuEnabled('visits')) {







          throw const ApiFailure(







            'MENU_DISABLED',







            'Visits have been disabled by your administrator.',







          );







        }







      }







      const needsSelfie = true;







      final photo = needsSelfie ? await capture() : null;







      if (needsSelfie && photo == null) return false;







      session.requireVisitDuty();







      final point = await session.locate();







      final reqBody = {







        ...fields,
        if (isRegular) 'kind': 'Regular',







        ...point,







        'requestId': finish ? finishKey : startKey,







        if (!finish) 'photoBase64': photo,







        if (finish && needsSelfie) 'departureSelfieBase64': photo,







      };







      if (finish) {







        session.setClosingVisit(







          shopName: fields['shopName'] ?? active?['shopName'] ?? active?['clientName'],







          id: '${fields['id'] ?? active?['id']}',







        );







      }









      if (isRegular) {
        if (session.offline) {
          throw const ApiFailure(
            'SERVER_REQUIRED',
            'Regular Visit requires live server validation (geofence & retailer mapping). Please check your internet connection and try again.',
          );
        }

        if (finish) {
          final serverId = int.tryParse('${existing?['serverId'] ?? existing?['id'] ?? fields['serverId'] ?? fields['id']}') ?? 0;
          if (serverId <= 0 || (existing?['isOffline'] == true && existing?['serverId'] == null)) {
            throw const ApiFailure('VISIT_SERVER_CONFIRMATION_REQUIRED', 'Refresh the server-confirmed visit before checkout.');
          }
          reqBody['id'] = serverId;
          final rawReceipt = await request('MobileVisits/finish', body: reqBody);
          if (!current()) throw const ApiFailure('SESSION_CHANGED', 'Account changed. Server receipt remains with the original user.');
          if (rawReceipt is! Map || int.tryParse('${rawReceipt['id']}') != serverId) {
            throw const ApiFailure('INVALID_VISIT_RECEIPT', 'Checkout acknowledgement does not match this visit. Refresh before retrying.');
          }
          final receipt = Map<String, dynamic>.from(rawReceipt);
          Json? confirmed;
          final serverClose = receipt['checkOutUtc'] ?? receipt['CheckOutUtc'];
          if (serverClose != null && DateTime.tryParse('$serverClose') != null) {
            confirmed = {...?existing, ...fields, ...receipt, 'checkOutUtc': serverClose};
          } else {
            final remote = jsonRows(await request('MobileVisits/mine?date=${session.localDay}')).map(normalizeVisit).toList();
            confirmed = remote.where((r) => int.tryParse('${r['id']}') == serverId && visitClosed(r)).firstOrNull;
          }
          if (!current()) throw const ApiFailure('SESSION_CHANGED', 'Account changed. Refresh visits.');
          if (confirmed == null) throw const ApiFailure('INVALID_VISIT_RECEIPT', 'Checkout could not be verified from the server. Refresh before retrying.');
          final closed = normalizeVisit({...?existing, ...confirmed,
            'departureSelfieBase64': photo, 'hasDepartureSelfie': photo != null,
            'isOffline': false, 'syncState': 'synced', 'checkoutAcknowledged': true});
          if (index >= 0) rows[index] = closed; else rows.add(closed);
          await session.persistVisitClose(closed);
          if (!current()) return false;
          await saveCachedVisits();
          session.clearActiveVisit(); session.clearClosingVisit();
          finishKey = const Uuid().v4();
          session.notice = 'Visit check-out confirmed by server.';
          notifyListeners(); return true;
        } else {
          final rawReceipt = await request('MobileVisits/start', body: reqBody);
          if (rawReceipt is! Map || (int.tryParse('${rawReceipt['id']}') ?? 0) <= 0) {
            throw const ApiFailure('INVALID_VISIT_RECEIPT', 'Visit was not confirmed by the server. Refresh before retrying.');
          }
          if (!current()) throw const ApiFailure('SESSION_CHANGED', 'Account changed. Refresh visits.');
          final receipt = Map<String, dynamic>.from(rawReceipt);
          final captured = '${point['capturedAtUtc'] ?? DateTime.now().toUtc().toIso8601String()}';
          final saved = normalizeVisit({
            ...fields,
            ...receipt,
            'requestId': startKey,
            'serverId': receipt['id'],
            'workDate': session.localDay,
            'checkInUtc': captured,
            'checkOutUtc': null,
            'photoBase64': photo,
            'isOffline': false,
            'syncState': 'synced',
          });
          rows = mergePendingVisits([saved, ...rows.where((r) => !sameVisit(r, saved))], []);
          await saveCachedVisits();
          session.activeVisit = saved;
          startKey = const Uuid().v4();
          await load();
          session.notice = 'Visit punch-in confirmed by server.';
          notifyListeners();
          return true;
        }
      }









      if (finish || session.offline) {







        await _recordOfflineVisit(







          finish: finish,







          fields: fields,







          point: point,







          needsSelfie: needsSelfie,







          photo: photo,







        );







        if (!session.offline) {
          if (session.local == null) {
            await session.syncPendingVisits();
          } else {
            await session.syncData();
          }
          await load();
        }
        if (finish) {







          session.clearActiveVisit();







          session.clearClosingVisit();







        }







        return true;







      }







      final rawReceipt = await request('MobileVisits/start', body: reqBody);
      if (rawReceipt is! Map || (int.tryParse('${rawReceipt['id']}') ?? 0) <= 0) {
        throw const ApiFailure('INVALID_VISIT_RECEIPT', 'Visit was not confirmed by the server. Refresh before retrying.');
      }
      final receipt = Map<String, dynamic>.from(rawReceipt);
      final captured = '${point['capturedAtUtc'] ?? DateTime.now().toUtc().toIso8601String()}';
      final saved = normalizeVisit({
        ...fields, ...receipt,
        'requestId': startKey, 'serverId': receipt['id'],
        'workDate': session.localDay, 'checkInUtc': captured,
        'checkOutUtc': null, 'photoBase64': photo,
        'isOffline': false, 'syncState': 'synced',
      });
      rows = mergePendingVisits([saved, ...rows.where((r) => !sameVisit(r, saved))], []);
      await saveCachedVisits();
      session.notice = 'Visit punch-in confirmed by server.';







      if (finish) {







        finishKey = const Uuid().v4();







        session.clearActiveVisit();







      } else {







        startKey = const Uuid().v4();







      }







      await load();







      if (finish) {







        session.clearClosingVisit();







      }







      session.activeVisit = active;







      session.notifyListeners();







      return true;







    } catch (_) {







      {







        rows = beforeRows;







        startKey = beforeStartKey;







        finishKey = beforeFinishKey;







      }







      rethrow;







    } finally {







      saving = false;

      if (finish) session.clearClosingVisit();









      if (!disposed) notifyListeners();







    }







  }















  @override







  void dispose() {







    disposed = true;







    super.dispose();







  }







}















class VisitsPage extends StatefulWidget {







  final TrackyuController controller;







  const VisitsPage({super.key, required this.controller});







  @override







  State<VisitsPage> createState() => _VisitsPageState();







}















class _VisitsPageState extends State<VisitsPage> {
  late final VisitsData data;
  Timer? _ticker;
  bool _isOpening = false;
  int _selectedTab = 0; // 0 = Ongoing, 1 = Completed
  DateTime _selectedDate = DateTime.now();
  String _typeFilter = 'all'; // 'all', 'Regular', 'Open'

  Future<void> _showStartVisitChoiceSheet() async {
    final active = data.active ?? widget.controller.activeVisit;
    final bool hasActive = active != null || widget.controller.pendingVisits.any((p) => p['finish'] != true && !queuedRegularVisit(p));
    if (hasActive) {
      edit(active);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Choose Visit Type',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
const SizedBox(height: 8),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0)),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xff4338ca).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.store_rounded, color: Color(0xff6366f1)),
                  ),
                  title: const Text('Regular Visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(ctx, 'Regular'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0)),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xff059669).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Color(0xff10b981)),
                  ),
                  title: const Text('Open Visit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(ctx, 'Open'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice != null) {
      if (choice == 'Regular') {
        final res = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SelectRegularPartyPage(data: data),
          ),
        );
        if (res == true && mounted) {
          data.load();
        }
      } else {
        edit(null, initialKind: 'Open');
      }
    }
  }

  Widget _buildTypeChip(String type, String label, bool isDark, {Color? color}) {
    final isSelected = _typeFilter == type;
    final activeColor = color ?? const Color(0xff0284c7);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _typeFilter = type),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected
                  ? Colors.white
                  : (isDark ? const Color(0xff94a3b8) : const Color(0xff64748b)),
            ),
          ),
        ),
      ),
    );
  }



  bool get _isPastDate {

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final sel = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

    return sel.isBefore(today);

  }















  @override







  void initState() {







    super.initState();







    data = VisitsData(widget.controller)..addListener(changed);







    data.load();







    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {







      if (mounted) {







        setState(() {});







      }







    });







  }















  void changed() {







    if (!mounted) return;







    if (!widget.controller.loggedIn) {







      Navigator.of(context).popUntil((r) => r.isFirst);







      return;







    }







    setState(() {});







  }















  @override







  void dispose() {







    _ticker?.cancel();







    data.removeListener(changed);







    data.dispose();







    super.dispose();







  }















  String _monthShort(int month) {







    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];







    return (month >= 1 && month <= 12) ? m[month - 1] : '';







  }















  String _formatElapsed(DateTime start) {







    final diff = DateTime.now().difference(start);







    if (diff.isNegative) return '00:00:00';







    final h = diff.inHours.toString().padLeft(2, '0');







    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');







    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');







    return '$h:$m:$s';







  }















  Future<void> edit(Json? visit, {String? initialKind}) async {

    if (_isOpening) return;



    if (visit == null && _isPastDate) {

      ScaffoldMessenger.of(context).showSnackBar(

        const SnackBar(

          content: Text('Cannot start a new visit for a past date.'),

          backgroundColor: Color(0xffef4444),

        ),

      );

      return;

    }







    final bool hasActive = data.active != null ||







        widget.controller.activeVisit != null ||







        widget.controller.pendingVisits.any((p) => p['finish'] != true && !queuedRegularVisit(p));







    if (visit == null && hasActive) {
      final active = data.active ?? widget.controller.activeVisit;
      final shopName = active?['shopName'] ?? active?['clientName'] ?? 'ongoing visit';
      final activeKind = active?['kind']?.toString() ?? 'Visit';
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xffef4444), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Visit Already in Progress',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
            ],
          ),
          content: Text(
            'Cannot start a new visit: You already have an active $activeKind in progress at "$shopName".\n\nOnly one visit can be active at a time. Please complete and punch out from your ongoing visit first.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff0284c7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                edit(active);
              },
              child: const Text('View Ongoing Visit'),
            ),
          ],
        ),
      );
      return;

    }



    if (!mounted) return;



    final canStart = widget.controller.canVisit || widget.controller.attendance != null || widget.controller.offline;







    if (!canStart) {







      ScaffoldMessenger.of(







        context,







      ).showSnackBar(const SnackBar(content: Text('Punch in to use visits.')));







      return;







    }















    if (!widget.controller.offline) {







      unawaited(widget.controller.refresh().catchError((_) {}));







    }















    setState(() => _isOpening = true);







    try {







      final saved = await Navigator.of(context).push<bool>(







        MaterialPageRoute(







          builder: (_) => (visit == null && initialKind == 'Regular')
              ? SelectRegularPartyPage(data: data)
              : VisitForm(data: data, visit: visit, initialKind: initialKind),







        ),







      );







      if (saved == true && mounted) {







        ScaffoldMessenger.of(context).showSnackBar(







          SnackBar(







            content: Text(







              visit == null







                  ? 'Visit punch-in confirmed.'







                  : 'Visit checkout saved.',







            ),







          ),







        );







      }







      await data.load();







    } finally {







      if (mounted) setState(() => _isOpening = false);







    }







  }















  Future<void> _openSelfie(Json row, {bool out = false}) async {







    if (_isOpening) return;







    setState(() => _isOpening = true);







    try {







      await Navigator.of(context).push(







        MaterialPageRoute(







          builder: (_) => AttendanceSelfiePage.visit(







            controller: widget.controller,







            visitId: visitIdOf(row),







            visitRecord: row,







            phase: out ? 'out' : 'in',







          ),







        ),







      );







    } finally {







      if (mounted) setState(() => _isOpening = false);







    }







  }















  Widget _buildSelfieOutlinedButton({required String label, required bool isDark, required VoidCallback? onTap}) {
    return SizedBox(height: 48, child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xff0284c7),
        side: BorderSide(color: isDark ? const Color(0xff0284c7).withValues(alpha: 0.5) : const Color(0xff0284c7), width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.camera_alt_outlined, size: 17), const SizedBox(width: 7),
        Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label,
          maxLines: 1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))),
      ]),
    ));
  }
  @override







  Widget build(BuildContext context) {







    final isDark = widget.controller.isDarkMode;







    final cardBg = isDark ? const Color(0xff1e2023) : Colors.white;







    final borderColor = isDark ? const Color(0xff2d3135) : const Color(0xffe2e8f0);







    final textPrimary = isDark ? Colors.white : const Color(0xff0f172a);







    final textSecondary = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);















    final selectedDateStr = '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';







    final isToday = selectedDateStr == widget.controller.localDay;















    final dateFilteredRows = data.rows.where((r) {
      if (unconfirmedRegularVisit(r)) return false;







      final wd = (r['workDate'] ?? r['WorkDate'])?.toString();







      if (wd != null && wd.trim().isNotEmpty) {







        return wd.contains(selectedDateStr);







      }







      final inUtc = (r['checkInUtc'] ?? r['CheckInUtc'] ?? r['createdAtUtc'] ?? r['CreatedAtUtc'])?.toString();







      if (inUtc != null && inUtc.trim().isNotEmpty) {







        final dt = DateTime.tryParse(inUtc)?.toLocal();







        if (dt != null) {







          final dtStr = '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';







          return dtStr == selectedDateStr;







        }







      }







      return isToday;







    }).toList();















    final regCount = dateFilteredRows.where((r) => r['kind'] == 'Regular' || r['kind'] == 'REGULAR' || (!r.containsKey('kind') && r['isLegacy'] == true)).length;
    final openCount = dateFilteredRows.where((r) => r['kind'] == 'Open' || r['kind'] == 'OPEN' || (!r.containsKey('kind') && r['isLegacy'] != true)).length;

    final typeFilteredRows = dateFilteredRows.where((r) {
      if (_typeFilter == 'all') return true;
      final isReg = r['kind'] == 'Regular' || r['kind'] == 'REGULAR' || (!r.containsKey('kind') && r['isLegacy'] == true);
      return _typeFilter == 'Regular' ? isReg : !isReg;
    }).toList();

    final activeVisitGlobal = isToday ? (data.active ?? widget.controller.activeVisit) : null;
    final bool hasGlobalActive = activeVisitGlobal != null && !visitClosed(activeVisitGlobal) && !widget.controller.isVisitClosedOrClosing(activeVisitGlobal);

    final ongoingVisits = isToday
        ? typeFilteredRows.where((r) => !visitClosed(r) && !widget.controller.isVisitClosedOrClosing(r)).toList()
        : <Json>[];

    if (isToday && hasGlobalActive && !ongoingVisits.any((r) => sameVisit(r, activeVisitGlobal))) {
      final aKind = activeVisitGlobal['kind']?.toString() ?? 'Regular';
      final isReg = aKind == 'Regular' || aKind == 'REGULAR';
      if (_typeFilter == 'all' || (_typeFilter == 'Regular' ? isReg : !isReg)) {
        ongoingVisits.insert(0, activeVisitGlobal);
      }
    }

    final completedVisits = typeFilteredRows.where(visitClosed).toList();

    return Scaffold(
      floatingActionButton: !_isPastDate
          ? (hasGlobalActive
              ? FloatingActionButton.extended(
                  onPressed: () => edit(activeVisitGlobal),
                  backgroundColor: const Color(0xffea580c),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  icon: const Icon(Icons.timer_rounded),
                  label: const Text('Check Out Ongoing Visit', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              : FloatingActionButton.extended(
                  onPressed: _isOpening ? null : _showStartVisitChoiceSheet,
                  backgroundColor: const Color(0xff0284c7),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: const Text('Start Visit', style: TextStyle(fontWeight: FontWeight.bold)),
                ))
          : null,
      appBar: trackyuAppBar(
        context: context,
        controller: widget.controller,
        title: 'Client Visits',
        leadingActions: [
          IconButton(
            tooltip: 'Open visit history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => WorkspacePage(
                  controller: widget.controller,
                  feature: WorkFeature.visits,
                ),
              ),
            ),
          ),
        ],
        onSync: data.loading || data.saving ? null : () => data.load(date: selectedDateStr),
      ),

      body: ListView(







        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),







        children: [







          // 1. Date Selector and Visit Count







          Wrap(







            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,







            children: [







              InkWell(







                onTap: () async {







                  final picked = await showDatePicker(







                    context: context,







                    initialDate: _selectedDate,







                    firstDate: DateTime(2020),







                    lastDate: DateTime.now().add(const Duration(days: 30)),







                  );







                  if (picked != null) {







                    setState(() => _selectedDate = picked);







                    final queryDate = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';







                    await data.load(date: queryDate);







                  }







                },







                borderRadius: BorderRadius.circular(10),







                child: Container(







                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),







                  decoration: BoxDecoration(







                    color: isDark ? const Color(0xff1e293b) : Colors.white,







                    borderRadius: BorderRadius.circular(10),







                    border: Border.all(







                      color: isDark ? const Color(0xff334155) : const Color(0xffcbd5e1),







                      width: 1.0,







                    ),







                  ),







                  child: Row(







                    mainAxisSize: MainAxisSize.min,







                    children: [







                      const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xff0284c7)),







                      const SizedBox(width: 8),







                      Text(







                        '${_selectedDate.day} ${_monthShort(_selectedDate.month)} ${_selectedDate.year}',







                        style: TextStyle(







                          fontSize: 13,







                          fontWeight: FontWeight.w600,







                          color: textPrimary,







                        ),







                      ),







                      const SizedBox(width: 5),







                      const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xff64748b)),







                    ],







                  ),







                ),







              ),







              Text(







                '${dateFilteredRows.length} ${dateFilteredRows.length == 1 ? 'visit' : 'visits'} recorded',







                style: TextStyle(







                  fontSize: 13,







                  fontWeight: FontWeight.w500,







                  color: textSecondary,







                ),







              ),







            ],







          ),















          const SizedBox(height: 14),















          // 1.5 Visit Type Filter Chips (All / Regular / Open)
          Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0)),
            ),
            child: Row(
              children: [
                _buildTypeChip('all', 'All (${dateFilteredRows.length})', isDark),
                _buildTypeChip('Regular', '🏢 Regular ($regCount)', isDark, color: const Color(0xff4338ca)),
                _buildTypeChip('Open', '🏬 Open ($openCount)', isDark, color: const Color(0xff059669)),
              ],
            ),
          ),

          // 2. Segmented Toggle (Ongoing vs Completed)







          Container(







            height: 48,







            padding: const EdgeInsets.all(4),







            decoration: BoxDecoration(







              color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),







              borderRadius: BorderRadius.circular(14),







              border: Border.all(color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0)),







            ),







            child: Row(







              children: [







                Expanded(







                  child: InkWell(







                    onTap: () => setState(() => _selectedTab = 0),







                    borderRadius: BorderRadius.circular(10),







                    child: Container(







                      decoration: BoxDecoration(







                        color: _selectedTab == 0







                            ? (isDark ? const Color(0xff0f172a) : Colors.white)







                            : Colors.transparent,







                        borderRadius: BorderRadius.circular(10),







                        boxShadow: _selectedTab == 0







                            ? [







                                BoxShadow(







                                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),







                                  blurRadius: 4,







                                  offset: const Offset(0, 2),







                                )







                              ]







                            : null,







                      ),







                      child: Center(







                        child: Text(







                          'Ongoing',







                          style: TextStyle(







                            fontSize: 14,







                            fontWeight: FontWeight.bold,







                            color: _selectedTab == 0 ? textPrimary : textSecondary,







                          ),







                        ),







                      ),







                    ),







                  ),







                ),







                Expanded(







                  child: InkWell(







                    onTap: () => setState(() => _selectedTab = 1),







                    borderRadius: BorderRadius.circular(10),







                    child: Container(







                      decoration: BoxDecoration(







                        color: _selectedTab == 1







                            ? (isDark ? const Color(0xff0f172a) : Colors.white)







                            : Colors.transparent,







                        borderRadius: BorderRadius.circular(10),







                        boxShadow: _selectedTab == 1







                            ? [







                                BoxShadow(







                                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),







                                  blurRadius: 4,







                                  offset: const Offset(0, 2),







                                )







                              ]







                            : null,







                      ),







                      child: Center(







                        child: Text(







                          'Completed',







                          style: TextStyle(







                            fontSize: 14,







                            fontWeight: FontWeight.bold,







                            color: _selectedTab == 1 ? textPrimary : textSecondary,







                          ),







                        ),







                      ),







                    ),







                  ),







                ),







              ],







            ),







          ),















          const SizedBox(height: 16),















          if (data.loading) const Padding(







            padding: EdgeInsets.symmetric(vertical: 8),







            child: LinearProgressIndicator(),







          ),















          if (data.error != null)







            Padding(







              padding: const EdgeInsets.all(16),







              child: Column(







                children: [







                  Text(data.error!, style: const TextStyle(color: Colors.red)),







                  TextButton(onPressed: data.load, child: const Text('Retry')),







                ],







              ),







            ),















          // TAB 0: ONGOING VISITS







          if (_selectedTab == 0) ...[
            if (hasGlobalActive && ongoingVisits.isEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xffea580c).withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xffea580c).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xffea580c).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.access_time_filled_rounded, color: Color(0xffea580c), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active ${activeVisitGlobal?['kind'] ?? 'Visit'} in Progress',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xffea580c)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activeVisitGlobal?['shopName'] ?? activeVisitGlobal?['clientName'] ?? 'Ongoing client',
                            style: TextStyle(fontSize: 13, color: textPrimary, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Only one visit can be active at a time. Punch out to start a new visit.',
                            style: TextStyle(fontSize: 11, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xffea580c),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => edit(activeVisitGlobal),
                      child: const Text('Punch Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],

            if (ongoingVisits.isEmpty && !hasGlobalActive && !data.loading) ...[

              Container(

                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),

                decoration: BoxDecoration(

                  color: cardBg,

                  borderRadius: BorderRadius.circular(18),

                  border: Border.all(color: borderColor),

                ),

                child: Column(

                  children: [

                    Container(

                      width: 56,

                      height: 56,

                      decoration: BoxDecoration(

                        color: const Color(0xff0284c7).withValues(alpha: 0.12),

                        borderRadius: BorderRadius.circular(14),

                      ),

                      child: const Icon(

                        Icons.storefront_outlined,

                        size: 30,

                        color: Color(0xff0284c7),

                      ),

                    ),

                    const SizedBox(height: 14),

                    Text(

                      'No ongoing visit in progress',

                      style: TextStyle(

                        fontSize: 16,

                        fontWeight: FontWeight.w700,

                        color: textPrimary,

                      ),

                    ),

                    const SizedBox(height: 4),

                    Text(

                      _isPastDate

                          ? 'Starting new visits on past dates is disabled.'

                          : 'Start a new client visit to track time and punch out.',

                      textAlign: TextAlign.center,

                      style: TextStyle(

                        fontSize: 13,

                        color: textSecondary,

                      ),

                    ),

                    if (!_isPastDate) ...[

                      const SizedBox(height: 20),

                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8, runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isOpening ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => SelectRegularPartyPage(data: data))),
                            icon: const Icon(Icons.store_rounded, color: Colors.white, size: 16),
                            label: const Text(
                              'Regular Visit',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff4338ca),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _isOpening ? null : () => edit(null, initialKind: 'Open'),
                            icon: const Icon(Icons.storefront_rounded, color: Colors.white, size: 16),
                            label: const Text(
                              'Open Visit',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff059669),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox.shrink(),
                      if (false) ElevatedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.add),
                        label: const Text('Start',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,

                          ),

                        ),

                        style: ElevatedButton.styleFrom(

                          backgroundColor: const Color(0xff0284c7),

                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),

                          shape: RoundedRectangleBorder(

                            borderRadius: BorderRadius.circular(12),

                          ),

                          elevation: 0,

                        ),

                      ),

                    ] else ...[

                      const SizedBox(height: 16),

                      Container(

                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

                        decoration: BoxDecoration(

                          color: isDark ? const Color(0x22f59e0b) : const Color(0xfffef3c7),

                          borderRadius: BorderRadius.circular(12),

                          border: Border.all(

                            color: isDark ? const Color(0x44f59e0b) : const Color(0xfffde68a),

                          ),

                        ),

                        child: Row(

                          mainAxisSize: MainAxisSize.min,

                          children: [

                            const Icon(Icons.history_rounded, size: 18, color: Color(0xffd97706)),

                            const SizedBox(width: 8),

                            Text(

                              'Visits disabled on past dates',

                              style: TextStyle(

                                color: isDark ? const Color(0xfffcd34d) : const Color(0xffb45309),

                                fontSize: 13,

                                fontWeight: FontWeight.w600,

                              ),

                            ),

                          ],

                        ),

                      ),

                    ],

                  ],

                ),

              ),

            ] else ...[

              for (final row in ongoingVisits)







                Builder(







                  builder: (context) {







                    final lat = ((row['inLatitude'] ?? row['latitude']) as num?)?.toDouble();







                    final lng = ((row['inLongitude'] ?? row['longitude']) as num?)?.toDouble();







                    final coordStr = (lat != null && lng != null)







                        ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'







                        : '';







                    final addressStr = cleanAddress('${row['address']}');







                    final start = DateTime.tryParse('${row['checkInUtc']}')?.toLocal() ?? DateTime.now();







                    final isOverstay = DateTime.now().difference(start).inMinutes >= 120;















                    return Column(







                      crossAxisAlignment: CrossAxisAlignment.stretch,







                      children: [







                        Container(







                          margin: const EdgeInsets.only(bottom: 16),







                          decoration: BoxDecoration(







                            color: cardBg,







                            borderRadius: BorderRadius.circular(18),







                            border: Border.all(







                              color: isOverstay ? const Color(0xfff43f5e) : borderColor,







                              width: isOverstay ? 1.5 : 1.0,







                            ),







                            boxShadow: [







                              BoxShadow(







                                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),







                                blurRadius: 10,







                                offset: const Offset(0, 3),







                              ),







                            ],







                          ),







                          child: Padding(







                            padding: const EdgeInsets.all(18),







                            child: Column(







                              crossAxisAlignment: CrossAxisAlignment.start,







                              children: [







                                // Header: Store Icon + Store Name + In progress badge







                                Row(







                                  children: [







                                    Container(







                                      width: 44,







                                      height: 44,







                                      decoration: BoxDecoration(







                                        color: isDark ? const Color(0xff0c2a42) : const Color(0xffeff6ff),







                                        borderRadius: BorderRadius.circular(12),







                                      ),







                                      child: const Icon(







                                        Icons.storefront_rounded,







                                        color: Color(0xff0284c7),







                                        size: 24,







                                      ),







                                    ),







                                    const SizedBox(width: 12),







                                    Expanded(







                                      child: Text(







                                        row['shopName']?.toString() ?? 'Client visit',







                                        style: TextStyle(







                                          fontSize: 18,







                                          fontWeight: FontWeight.bold,







                                          letterSpacing: -0.3,







                                          color: textPrimary,







                                        ),







                                        maxLines: 1,







                                        overflow: TextOverflow.ellipsis,







                                      ),







                                    ),







                                    Container(







                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),







                                      decoration: BoxDecoration(







                                        color: isDark ? const Color(0xff451a03) : const Color(0xfffffbeb),







                                        borderRadius: BorderRadius.circular(20),







                                        border: Border.all(







                                          color: const Color(0xfff59e0b).withValues(alpha: 0.3),







                                        ),







                                      ),







                                      child: const Row(







                                        mainAxisSize: MainAxisSize.min,







                                        children: [







                                          Icon(







                                            Icons.circle,







                                            size: 8,







                                            color: Color(0xfff59e0b),







                                          ),







                                          SizedBox(width: 5),







                                          Text(







                                            'In progress',







                                            style: TextStyle(







                                              fontSize: 11.5,







                                              fontWeight: FontWeight.w700,







                                              color: Color(0xffd97706),







                                            ),







                                          ),







                                        ],







                                      ),







                                    ),







                                  ],







                                ),















                                const SizedBox(height: 16),















                                // Elapsed time & Started at container







                                Container(







                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),







                                  decoration: BoxDecoration(







                                    color: isDark ? const Color(0xff15181b) : const Color(0xfff1f5f9),







                                    borderRadius: BorderRadius.circular(12),







                                  ),







                                  child: Row(







                                    children: [







                                      Expanded(







                                        child: Column(







                                          crossAxisAlignment: CrossAxisAlignment.start,







                                          children: [







                                            Text(







                                              'Elapsed time',







                                              style: TextStyle(







                                                fontSize: 12,







                                                fontWeight: FontWeight.w500,







                                                color: textSecondary,







                                              ),







                                            ),







                                            const SizedBox(height: 4),







                                            Text(







                                              _formatElapsed(start),







                                              style: TextStyle(







                                                fontSize: 22,







                                                fontWeight: FontWeight.w800,







                                                letterSpacing: -0.5,







                                                color: textPrimary,







                                              ),







                                            ),







                                          ],







                                        ),







                                      ),







                                      Expanded(







                                        child: Column(







                                          crossAxisAlignment: CrossAxisAlignment.start,







                                          children: [







                                            Text(







                                              'Started at',







                                              style: TextStyle(







                                                fontSize: 12,







                                                fontWeight: FontWeight.w500,







                                                color: textSecondary,







                                              ),







                                            ),







                                            const SizedBox(height: 4),







                                            Text(







                                              _format12Hour(start),







                                              style: TextStyle(







                                                fontSize: 18,







                                                fontWeight: FontWeight.w700,







                                                color: textPrimary,







                                              ),







                                            ),







                                          ],







                                        ),







                                      ),







                                    ],







                                  ),







                                ),















                                const SizedBox(height: 14),















                                // Location & Coordinates







                                if (addressStr.isNotEmpty || coordStr.isNotEmpty) ...[







                                  Row(







                                    crossAxisAlignment: CrossAxisAlignment.start,







                                    children: [







                                      const Padding(







                                        padding: EdgeInsets.only(top: 2),







                                        child: Icon(







                                          Icons.place_rounded,







                                          size: 16,







                                          color: Color(0xff0284c7),







                                        ),







                                      ),







                                      const SizedBox(width: 8),







                                      Expanded(







                                        child: Column(







                                          crossAxisAlignment: CrossAxisAlignment.start,







                                          children: [







                                            if (addressStr.isNotEmpty)







                                              Text(







                                                addressStr,







                                                style: TextStyle(







                                                  fontSize: 13,







                                                  height: 1.35,







                                                  color: textPrimary,







                                                  fontWeight: FontWeight.w500,







                                                ),







                                              ),







                                            if (coordStr.isNotEmpty) ...[







                                              if (addressStr.isNotEmpty) const SizedBox(height: 3),







                                              Text(







                                                coordStr,







                                                style: TextStyle(







                                                  fontSize: 11.5,







                                                  fontFamily: 'monospace',







                                                  color: textSecondary,







                                                  fontWeight: FontWeight.w600,







                                                ),







                                              ),







                                            ],







                                          ],







                                        ),







                                      ),







                                    ],







                                  ),







                                  const SizedBox(height: 16),







                                ],















                                // Arrival selfie button







                                SizedBox(







                                  width: double.infinity,







                                  child: _buildSelfieOutlinedButton(







                                    label: 'Arrival selfie',







                                    isDark: isDark,







                                    onTap: () => _openSelfie(row, out: false),







                                  ),







                                ),







                              ],







                            ),







                          ),







                        ),















                        // Punch Out Action Button at bottom







                        ElevatedButton.icon(







                          style: ElevatedButton.styleFrom(







                            backgroundColor: isOverstay ? const Color(0xfff43f5e) : const Color(0xff2563eb),







                            foregroundColor: Colors.white,







                            padding: const EdgeInsets.symmetric(vertical: 14),







                            shape: RoundedRectangleBorder(







                              borderRadius: BorderRadius.circular(14),







                            ),







                            elevation: 0,







                          ),







                          onPressed: (data.saving || _isOpening || !visitCheckoutReady(row, DateTime.now()))







                              ? null







                              : () => edit(row),







                          icon: const Icon(Icons.check_circle_outline_rounded, size: 20),







                          label: Text(







                            isOverstay ? 'Check Out & Complete Visit' : 'Check Out Visit',







                            style: const TextStyle(







                              fontSize: 15.5,







                              fontWeight: FontWeight.bold,







                            ),







                          ),







                        ),







                        if (isOverstay) ...[







                          const SizedBox(height: 8),







                          OutlinedButton.icon(







                            onPressed: () {







                              VisitOverstayAlertSheet.snooze(30);







                              setState(() {});







                              ScaffoldMessenger.of(context).showSnackBar(







                                const SnackBar(







                                  content: Text('Overstay alert snoozed for 30 minutes.'),







                                  backgroundColor: Color(0xfff97316),







                                ),







                              );







                            },







                            icon: const Icon(Icons.snooze_rounded, size: 18),







                            label: const Text('Still in Meeting (+30 min Snooze)'),







                            style: OutlinedButton.styleFrom(







                              foregroundColor: isDark ? const Color(0xffcbd5e1) : const Color(0xff475569),







                              side: BorderSide(color: isDark ? const Color(0xff334155) : const Color(0xffcbd5e1)),







                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),







                              padding: const EdgeInsets.symmetric(vertical: 12),







                            ),







                          ),







                        ],







                        const SizedBox(height: 20),







                      ],







                    );







                  },







                ),







            ],







          ],















          // TAB 1: COMPLETED VISITS







          if (_selectedTab == 1) ...[







            if (completedVisits.isEmpty && !data.loading) ...[







              Padding(







                padding: const EdgeInsets.all(32),







                child: Center(







                  child: Column(







                    children: [







                      Icon(







                        Icons.check_circle_outline_rounded,







                        size: 48,







                        color: textSecondary,







                      ),







                      const SizedBox(height: 12),







                      Text(







                        'No completed visits yet today.',







                        style: TextStyle(







                          fontSize: 14,







                          fontWeight: FontWeight.w500,







                          color: textSecondary,







                        ),







                      ),







                    ],







                  ),







                ),







              ),







            ] else ...[







              for (final row in completedVisits)







                Builder(







                  builder: (context) {







                    final lat = ((row['inLatitude'] ?? row['latitude']) as num?)?.toDouble();







                    final lng = ((row['inLongitude'] ?? row['longitude']) as num?)?.toDouble();







                    final coordStr = (lat != null && lng != null)







                        ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'







                        : '';







                    final addressStr = cleanAddress('${row['address']}');







                    final start = DateTime.tryParse('${row['checkInUtc']}')?.toLocal();







                    final end = DateTime.tryParse('${row['checkOutUtc']}')?.toLocal();







                    final durMin = (start != null && end != null) ? end.difference(start).inMinutes : 0;















                    return Container(







                      margin: const EdgeInsets.only(bottom: 16),







                      decoration: BoxDecoration(







                        color: cardBg,







                        borderRadius: BorderRadius.circular(18),







                        border: Border.all(color: borderColor),







                        boxShadow: [







                          BoxShadow(







                            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),







                            blurRadius: 10,







                            offset: const Offset(0, 3),







                          ),







                        ],







                      ),







                      child: Padding(







                        padding: const EdgeInsets.all(18),







                        child: Column(







                          crossAxisAlignment: CrossAxisAlignment.start,







                          children: [







                            // Header Row: Green Storefront Icon + Name + Completed Badge







                            Row(







                              children: [







                                Container(







                                  width: 44,







                                  height: 44,







                                  decoration: BoxDecoration(







                                    color: isDark ? const Color(0xff064e3b) : const Color(0xfff0fdf4),







                                    borderRadius: BorderRadius.circular(12),







                                  ),







                                  child: const Icon(







                                    Icons.storefront_rounded,







                                    color: Color(0xff16a34a),







                                    size: 24,







                                  ),







                                ),







                                const SizedBox(width: 12),







                                Expanded(







                                  child: Text(







                                    row['shopName']?.toString() ?? 'Client visit',







                                    style: TextStyle(







                                      fontSize: 18,







                                      fontWeight: FontWeight.bold,







                                      letterSpacing: -0.3,







                                      color: textPrimary,







                                    ),







                                    maxLines: 1,







                                    overflow: TextOverflow.ellipsis,







                                  ),







                                ),







                                Container(







                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),







                                  decoration: BoxDecoration(







                                    color: isDark ? const Color(0xff064e3b).withValues(alpha: 0.6) : const Color(0xffecfdf5),







                                    borderRadius: BorderRadius.circular(20),







                                    border: Border.all(







                                      color: const Color(0xff10b981).withValues(alpha: 0.3),







                                    ),







                                  ),







                                  child: const Row(







                                    mainAxisSize: MainAxisSize.min,







                                    children: [







                                      Icon(







                                        Icons.circle,







                                        size: 8,







                                        color: Color(0xff10b981),







                                      ),







                                      SizedBox(width: 5),







                                      Text(







                                        'Completed',







                                        style: TextStyle(







                                          fontSize: 11.5,







                                          fontWeight: FontWeight.w700,







                                          color: Color(0xff15803d),







                                        ),







                                      ),







                                    ],







                                  ),







                                ),







                              ],







                            ),















                            const SizedBox(height: 10),















                            // Stay pill (e.g. 345 min stay)







                            Container(







                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),







                              decoration: BoxDecoration(







                                color: isDark ? const Color(0xff064e3b).withValues(alpha: 0.4) : const Color(0xffecfdf5),







                                borderRadius: BorderRadius.circular(20),







                              ),







                              child: Text(







                                durMin > 0 ? '$durMin min stay' : '< 1 min stay',







                                style: const TextStyle(







                                  fontSize: 12,







                                  fontWeight: FontWeight.w600,







                                  color: Color(0xff15803d),







                                ),







                              ),







                            ),















                            const SizedBox(height: 14),















                            // Arrival & Departure Row







                            Row(







                              children: [







                                Expanded(







                                  child: Column(







                                    crossAxisAlignment: CrossAxisAlignment.start,







                                    children: [







                                      Text(







                                        'Arrival',







                                        style: TextStyle(







                                          fontSize: 12,







                                          fontWeight: FontWeight.w500,







                                          color: textSecondary,







                                        ),







                                      ),







                                      const SizedBox(height: 3),







                                      Text(







                                        start != null ? _format12Hour(start) : '--:--',







                                        style: TextStyle(







                                          fontSize: 16,







                                          fontWeight: FontWeight.bold,







                                          color: textPrimary,







                                        ),







                                      ),







                                    ],







                                  ),







                                ),







                                Expanded(







                                  child: Column(







                                    crossAxisAlignment: CrossAxisAlignment.start,







                                    children: [







                                      Text(







                                        'Departure',







                                        style: TextStyle(







                                          fontSize: 12,







                                          fontWeight: FontWeight.w500,







                                          color: textSecondary,







                                        ),







                                      ),







                                      const SizedBox(height: 3),







                                      Text(







                                        end != null ? _format12Hour(end) : '--:--',







                                        style: TextStyle(







                                          fontSize: 16,







                                          fontWeight: FontWeight.bold,







                                          color: textPrimary,







                                        ),







                                      ),







                                    ],







                                  ),







                                ),







                              ],







                            ),















                            const SizedBox(height: 14),















                            // Location & Coordinates







                            if (addressStr.isNotEmpty || coordStr.isNotEmpty) ...[







                              Row(







                                crossAxisAlignment: CrossAxisAlignment.start,







                                children: [







                                  const Padding(







                                    padding: EdgeInsets.only(top: 2),







                                    child: Icon(







                                      Icons.place_rounded,







                                      size: 16,







                                      color: Color(0xff0284c7),







                                    ),







                                  ),







                                  const SizedBox(width: 8),







                                  Expanded(







                                    child: Column(







                                      crossAxisAlignment: CrossAxisAlignment.start,







                                      children: [







                                        if (addressStr.isNotEmpty)







                                          Text(







                                            addressStr,







                                            style: TextStyle(







                                              fontSize: 13,







                                              height: 1.35,







                                              color: textPrimary,







                                              fontWeight: FontWeight.w500,







                                            ),







                                          ),







                                        if (coordStr.isNotEmpty) ...[







                                          if (addressStr.isNotEmpty) const SizedBox(height: 3),







                                          Text(







                                            coordStr,







                                            style: TextStyle(







                                              fontSize: 11.5,







                                              fontFamily: 'monospace',







                                              color: textSecondary,







                                              fontWeight: FontWeight.w600,







                                            ),







                                          ),







                                        ],







                                      ],







                                    ),







                                  ),







                                ],







                              ),







                              const SizedBox(height: 12),







                            ],















                            // Contact details: Person & mobile







                            if ((row['ownerName'] != null && '${row['ownerName']}'.trim().isNotEmpty) ||







                                (row['mobile'] != null && '${row['mobile']}'.trim().isNotEmpty)) ...[







                              Row(







                                children: [







                                  Icon(







                                    Icons.person_outline_rounded,







                                    size: 16,







                                    color: textSecondary,







                                  ),







                                  const SizedBox(width: 8),







                                  Expanded(







                                    child: Text(







                                      [







                                        if (row['ownerName'] != null && '${row['ownerName']}'.trim().isNotEmpty)







                                          '${row['ownerName']}',







                                        if (row['mobile'] != null && '${row['mobile']}'.trim().isNotEmpty)







                                          '${row['mobile']}',







                                      ].join(' • '),







                                      style: TextStyle(







                                        fontSize: 13,







                                        fontWeight: FontWeight.w500,







                                        color: textPrimary,







                                      ),







                                    ),







                                  ),







                                ],







                              ),







                              const SizedBox(height: 10),







                            ],















                            // Remark / Note







                            if (row['remark'] != null && '${row['remark']}'.trim().isNotEmpty) ...[







                              Row(







                                crossAxisAlignment: CrossAxisAlignment.start,







                                children: [







                                  Icon(







                                    Icons.chat_bubble_outline_rounded,







                                    size: 16,







                                    color: textSecondary,







                                  ),







                                  const SizedBox(width: 8),







                                  Expanded(







                                    child: Text(







                                      'Note: ${row['remark']}',







                                      style: TextStyle(







                                        fontSize: 13,







                                        fontWeight: FontWeight.w500,







                                        color: textPrimary,







                                      ),







                                    ),







                                  ),







                                ],







                              ),







                              const SizedBox(height: 14),







                            ],















                            // Selfie buttons: Arrival & Departure







                            Row(







                              children: [







                                Expanded(







                                  child: _buildSelfieOutlinedButton(







                                    label: 'Arrival selfie',







                                    isDark: isDark,







                                    onTap: () => _openSelfie(row, out: false),







                                  ),







                                ),







                                const SizedBox(width: 10),







                                Expanded(







                                  child: _buildSelfieOutlinedButton(







                                    label: 'Departure selfie',







                                    isDark: isDark,







                                    onTap: hasDeparturePhoto(row) ? () => _openSelfie(row, out: true) : null,







                                  ),







                                ),







                              ],







                            ),







                          ],







                        ),







                      ),







                    );







                  },







                ),







            ],







          ],







        ],







      ),







    );







  }







}























class VisitDuration extends StatelessWidget {







  final Json row;







  const VisitDuration({super.key, required this.row});







  @override







  Widget build(BuildContext context) {







    final start = DateTime.tryParse('${row['checkInUtc']}');







    if (start == null) {







      return const SizedBox();







    }







    final seconds = DateTime.now()







        .toUtc()







        .difference(start.toUtc())







        .inSeconds







        .clamp(0, 864000);







    final earliest = DateTime.tryParse('${row['earliestCheckoutUtc']}');







    final remaining =







        earliest?.toUtc().difference(DateTime.now().toUtc()).inSeconds ?? 0;







    final elapsed =







        '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';







    return Padding(







      padding: const EdgeInsets.symmetric(vertical: 12),







      child: Column(







        crossAxisAlignment: CrossAxisAlignment.start,







        children: [







          Text(







            'Visit duration  $elapsed',







            style: const TextStyle(







              fontWeight: FontWeight.w700,







              color: Color(0xff1c6799),







            ),







          ),







          







        ],







      ),







    );







  }







}















class VisitForm extends StatefulWidget {
  final VisitsData data;
  final Json? visit;
  final String? initialKind;
  final Json? initialRetailer;
  const VisitForm({super.key, required this.data, this.visit, this.initialKind, this.initialRetailer});







  @override







  State<VisitForm> createState() => _VisitFormState();







}















class _VisitFormState extends State<VisitForm> {







  final form = GlobalKey<FormState>();







  final shop = TextEditingController(),







      place = TextEditingController(),







      address = TextEditingController(),







      owner = TextEditingController(),







      mobile = TextEditingController(),







      remark = TextEditingController(),







      orderRemark = TextEditingController(),







      otherRemark = TextEditingController(),







      search = TextEditingController();







  String kind = 'Regular', lead = 'Y';
  double? _currentLat, _currentLng;

  String get _currentAddress {
    final cached = (_currentLat != null && _currentLng != null)
        ? TrackyuAddressCache.get(_currentLat!, _currentLng!)
        : null;
    if (cached != null && cached.isNotEmpty && cached != 'Resolving address...') {
      return cached;
    }
    if (address.text.isNotEmpty && address.text != 'Recorded via GPS') {
      return address.text;
    }
    return 'Acquiring GPS location...';
  }







  Json? retailer;







  List<Json> retailers = [];







  bool saving = false, searching = false, _fetchingLocation = false;







  bool _userEditedAddress = false, _userEditedPlace = false;







  String? error;







  bool get finish => widget.visit != null;







  bool get open => (finish ? widget.visit!['kind'] : kind) == 'Open';















  @override







  void initState() {







    super.initState();
    kind = widget.visit?['kind']?.toString() ?? widget.initialKind ?? 'Regular';
    if (widget.initialRetailer != null) {
      retailer = widget.initialRetailer;
      search.text = retailer!['name']?.toString() ?? '';
      if (retailer!['address'] != null && retailer!['address'].toString().trim().isNotEmpty) {
        address.text = retailer!['address'].toString().trim();
      }
    }

    // 1. Instant synchronous pre-fill from cached location (0ms delay!)







    _populateFromCache();















    // 2. Load fresh GPS location & reverse-geocoded place/address AFTER the page opens!







    WidgetsBinding.instance.addPostFrameCallback((_) {







      if (mounted) {







        _userEditedAddress = false;







        _userEditedPlace = false;







        _loadLocationAndAddress(force: true);







        if (!widget.data.session.offline) {







          widget.data.session.refreshMenus().catchError((Object _) {});







        }







      }







    });







    if (!finish && kind == 'Regular') {







      findRetailers();







    }







  }















  void _populateFromCache() {







    final lastLoc = widget.data.session.lastLocation;







    if (lastLoc != null) {







      // Discard stale session locations (> 5 minutes old) so old morning fixes (e.g. punch-in) never leak into new visits







      final capStr = lastLoc['capturedAtUtc']?.toString();







      if (capStr != null && capStr.isNotEmpty) {







        final capTime = DateTime.tryParse(capStr)?.toUtc();







        if (capTime != null && DateTime.now().toUtc().difference(capTime) > const Duration(minutes: 5)) {







          return;







        }







      }







      final lat = (lastLoc['latitude'] as num?)?.toDouble() ?? double.tryParse('${lastLoc["latitude"]}');







      final lng = (lastLoc['longitude'] as num?)?.toDouble() ?? double.tryParse('${lastLoc["longitude"]}');







      if (lat != null && lng != null) {







        final cachedAddr = TrackyuAddressCache.get(lat, lng) ?? lastLoc['address']?.toString();







        final clean = cleanAddress(cachedAddr);







        if (clean.isNotEmpty && clean != 'Recorded via GPS') {







          address.text = clean;







        }







        final cachedPlace = TrackyuAddressCache.getPlaceName(lat, lng);







        if (cachedPlace != null && cachedPlace.isNotEmpty && place.text.isEmpty) {







          place.text = cachedPlace;







        }







      }







    }







  }















  Future<void> _loadLocationAndAddress({bool force = false}) async {







    if (_fetchingLocation || saving) return;







    if (mounted) setState(() => _fetchingLocation = true);















    try {







      // Step A: Immediately check native background service recent fix (updated every 10-30s during active duty)







      try {







        final status = await DutyTracker.status();







        final fix = status['lastPoint'] is Map ? status['lastPoint'] as Map : null;







        if (fix != null) {







          final lat = (fix['latitude'] as num?)?.toDouble() ?? double.tryParse(fix['latitude']?.toString() ?? '');







          final lng = (fix['longitude'] as num?)?.toDouble() ?? double.tryParse(fix['longitude']?.toString() ?? '');







          if (lat != null && lng != null) {







            await _resolveAddressFromCoords(lat, lng, force: force);







          }







        }







      } catch (_) {}















      // Step B: Query live GPS with 12s window for high-accuracy satellite fix without stale fallbacks







      try {







        final loc = await widget.data.session.locate().timeout(







          const Duration(seconds: 12),







        );







        final lat = (loc['latitude'] as num?)?.toDouble();







        final lng = (loc['longitude'] as num?)?.toDouble();







        if (lat != null && lng != null) {







          await _resolveAddressFromCoords(lat, lng, force: force);







          return;







        }







      } catch (_) {}







    } finally {







      if (mounted) setState(() => _fetchingLocation = false);







    }







  }















  Future<void> _resolveAddressFromCoords(double lat, double lng, {bool force = false}) async {
    _currentLat = lat;
    _currentLng = lng;







    try {







      // 1. Check local in-memory TrackyuAddressCache first (instant!)







      final cached = TrackyuAddressCache.get(lat, lng);







      if (cached != null && cached.isNotEmpty && cached != 'Resolving address...') {







        if (force || !_userEditedAddress || address.text.isEmpty || address.text == 'Recorded via GPS') {







          address.text = cached;







        }







        final placeName = TrackyuAddressCache.getPlaceName(lat, lng);







        if (placeName != null && placeName.isNotEmpty && (force || !_userEditedPlace || place.text.isEmpty)) {







          place.text = placeName;







        }







        if (mounted) setState(() {});







        return;







      }















      // 2. Reverse geocode via platform







      final places = await Geocoding()







          .placemarkFromCoordinates(lat, lng)







          .timeout(const Duration(seconds: 4));







      if (places.isNotEmpty && mounted) {







        final p = places.first;







        final addr = formatPlacemarkAddress(p);







        TrackyuAddressCache.put(lat, lng, addr);







        if (addr.isNotEmpty && mounted) {







          if (force || !_userEditedAddress || address.text.isEmpty || address.text == 'Recorded via GPS') {







            address.text = addr;







          }







        }







        final placeStr = [p.subLocality ?? p.name, p.locality]







            .whereType<String>()







            .map((s) => s.trim())







            .where((s) => s.isNotEmpty)







            .toSet()







            .join(', ');







        if (placeStr.isNotEmpty && mounted) {







          







          if (force || !_userEditedPlace || place.text.isEmpty) {







            place.text = placeStr;







          }







        }







        if (mounted) setState(() {});







      }







    } catch (_) {}







  }















  @override







  void dispose() {







    for (final c in [







      shop,







      place,







      address,







      owner,







      mobile,







      remark,







      orderRemark,







      otherRemark,







      search,







    ]) {







      c.dispose();







    }







    super.dispose();







  }































  double _calculateDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295;
    final double a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742000 * math.asin(math.sqrt(a));
  }

  Future<void> findRetailers() async {







    if (searching || saving) return;







    setState(() {







      searching = true;







      error = null;







    });







    try {







      final rows = await widget.data.search(search.text);







      if (mounted) setState(() => retailers = rows);







    } catch (e) {







      if (mounted) {







        setState(







          () => error = e is ApiFailure







              ? e.toString()







              : 'Unable to load retailers. Retry.',







        );







      }







    } finally {







      if (mounted) setState(() => searching = false);







    }







  }















  Future<void> _discardVisit() async {







    final confirm = await showDialog<bool>(







      context: context,







      builder: (ctx) => AlertDialog(







        title: const Text('Discard In-Progress Visit?'),







        content: Text(







          'Are you sure you want to cancel and remove "${widget.visit!['shopName'] ?? 'this visit'}"?',







        ),







        actions: [







          TextButton(







            onPressed: () => Navigator.pop(ctx, false),







            child: const Text('Keep Visit'),







          ),







          FilledButton(







            style: FilledButton.styleFrom(







              backgroundColor: const Color(0xffef4444),







            ),







            onPressed: () => Navigator.pop(ctx, true),







            child: const Text('Discard'),







          ),







        ],







      ),







    );







    if (confirm != true || !mounted) return;







    setState(() => saving = true);







    try {







      await widget.data.discard(widget.visit!);







      widget.data.session.clearActiveVisit();







      if (mounted) Navigator.pop(context, true);







    } catch (e) {







      if (mounted) {







        setState(() => error = e.toString());







      }







    } finally {







      if (mounted) setState(() => saving = false);







    }







  }















  Future<void> submit() async {







    if (saving || !form.currentState!.validate()) return;







    if (finish && widget.visit != null && (visitClosed(widget.visit!) || widget.data.rows.any((r) => sameVisit(r, widget.visit!) && visitClosed(r)))) {







      widget.data.session.clearActiveVisit();







      widget.data.session.clearClosingVisit();







      if (mounted) Navigator.pop(context, true);







      return;







    }
    // Minimum duration validation removed







    if (!finish && kind == 'Regular') {
      if (retailer == null) {
        setState(() => error = 'Please search and choose your assigned retailer.');
        return;
      }
      final double? rLat = (retailer!['latitude'] as num?)?.toDouble() ?? double.tryParse('${retailer!["latitude"]}');
      final double? rLng = (retailer!['longitude'] as num?)?.toDouble() ?? double.tryParse('${retailer!["longitude"]}');
      
      if (rLat == null || rLng == null || (rLat == 0.0 && rLng == 0.0)) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.pin_drop, color: Color(0xfff59e0b), size: 22),
                SizedBox(width: 8),
                Text('Geo-Tagging Pending', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'GPS coordinates are pending for "${retailer!['name']}".\n\nPlease geotag the party location to start a Regular Visit.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_location_alt, size: 16),
                label: const Text('Geo-Tag Party Now'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff0284c7), foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RetailerGeoTagPage(controller: widget.data.session),
                    ),
                  );
                },
              ),
            ],
          ),
        );
        return;
      }

      final curLat = _currentLat;
      final curLng = _currentLng;
      if (curLat != null && curLng != null && curLat != 0.0 && curLng != 0.0) {
        final dist = _calculateDistanceMeters(curLat, curLng, rLat, rLng);
                final maxRange = widget.data.session.regularVisitRangeMeters;
        if (dist > maxRange) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.location_off_rounded, color: Color(0xffef4444), size: 22),
                  SizedBox(width: 8),
                  Text('Location Out of Range', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                'You are currently ${dist.round()}m away from "${retailer!['name']}".\n\nPlease be within ${maxRange.round()}m of the registered party location to start a Regular Visit.',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      }
    }







    final bool hasActive = widget.data.active != null ||







        widget.data.session.activeVisit != null ||







        widget.data.session.pendingVisits.any((p) => p['finish'] != true && !queuedRegularVisit(p));







    if (!finish && hasActive) {
      final active = widget.data.active ?? widget.data.session.activeVisit;
      if (active != null && (visitClosed(active) || widget.data.rows.any((r) => sameVisit(r, active) && visitClosed(r)))) {
        widget.data.session.clearActiveVisit();
        widget.data.session.clearClosingVisit();
      } else {
      final activeShop = active?['shopName'] ?? active?['clientName'] ?? 'ongoing visit';
      final activeKind = active?['kind']?.toString() ?? 'Visit';
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xffef4444), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Visit Already in Progress',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
            ],
          ),
          content: Text(
            'Cannot punch in: You already have an active $activeKind running at "$activeShop".\n\nOnly one visit can be active at a time. Please complete and punch out from that visit first.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff0284c7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
      }
    }







    setState(() {







      saving = true;







      error = null;







    });







    try {







      if (finish) {







        widget.data.session.setClosingVisit(







          shopName: widget.visit?['shopName'] ?? widget.visit?['clientName'] ?? shop.text.trim(),







          id: '',







        );







      }







      final saved = await widget.data.save(







        finish: finish,







        fields: finish







            ? {







                'id': widget.visit?['id'],







                'localId': widget.visit?['localId'],







                'shopName': widget.visit?['shopName'] ?? widget.visit?['clientName'] ?? shop.text.trim(),







                'kind': widget.visit?['kind'] ?? kind,







                'version': widget.visit?['version'],







                'remark': remark.text.trim(),







                if (open) ...{







                  'ownerName': owner.text.trim(),







                  'mobile': mobile.text.trim(),







                  'lead': lead,







                },







                if (!open) ...{







                  'orderRemark': orderRemark.text.trim(),







                  'otherRemark': otherRemark.text.trim(),







                },







              }







            : {







                'kind': kind,







                'address': cleanAddress(address.text),







                if (kind == 'Regular') ...{







                  'retailerId': (retailer!['id'] ?? retailer!['Id'] ?? retailer!['c_code'] ?? retailer!['retailer_id'])?.toString(),







                  'shopName': retailer!['name'],







                  'placeName': retailer!['place'],







                },







                if (open) ...{







                  'shopName': shop.text.trim(),







                  'placeName': place.text.trim(),







                },







              },







      );







      if (saved && mounted) {







        if (finish) {







          widget.data.session.clearActiveVisit();







        }







        Navigator.pop(context, true);







      } else if (!saved && mounted) {







        setState(() => error = 'Client photo / selfie is required to confirm visit.');







      }







    } catch (e) {







      if (mounted) {







        setState(







          () => error = e is ApiFailure







              ? e.toString()







              : 'Unable to save. Reload visits to check whether this request reached your workspace.',







        );







      }







    } finally {







      if (finish) widget.data.session.clearClosingVisit();

      if (mounted) setState(() => saving = false);







    }







  }















  Widget field(







    TextEditingController c,







    String label,







    int max, {







    bool required = true,







    bool phone = false,







    int maxLines = 1,







    IconData? icon,







    Widget? suffix,







    String? hintText,







    ValueChanged<String>? onChanged,







  }) {







    final isDark = Theme.of(context).brightness == Brightness.dark || widget.data.session.isDarkMode;







    final inputBg = isDark ? const Color(0xff181a1f) : const Color(0xfff8fafc);







    final inputBorder = isDark ? const Color(0xff2d333b) : const Color(0xffcbd5e1);







    final inputFocusBorder = finish ? (isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7)) : (isDark ? const Color(0xff4ade80) : const Color(0xff16a34a));







    final inputTextColor = isDark ? const Color(0xfff1f5f9) : const Color(0xff0f172a);







    final labelColor = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);







    final iconColor = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);















    return Padding(







      padding: const EdgeInsets.only(bottom: 16),







      child: TextFormField(







        controller: c,







        enabled: !saving,







        maxLength: max,







        buildCounter:







            (_, {required currentLength, required isFocused, maxLength}) => null,







        onChanged: onChanged,







        maxLines: maxLines,







        keyboardType: phone







            ? TextInputType.phone







            : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),







        style: TextStyle(







          fontSize: 15,







          fontWeight: FontWeight.w500,







          color: inputTextColor,







        ),







        decoration: InputDecoration(







          labelText: label,







          hintText: hintText,







          hintStyle: TextStyle(







            color: isDark ? const Color(0xff64748b) : const Color(0xff94a3b8),







            fontSize: 13,







          ),







          labelStyle: TextStyle(color: labelColor, fontSize: 14),







          floatingLabelStyle: TextStyle(







            color: inputFocusBorder,







            fontWeight: FontWeight.w600,







          ),







          prefixIcon: icon != null







              ? Icon(icon, size: 22, color: iconColor)







              : null,







          suffixIcon: suffix,







          filled: true,







          fillColor: inputBg,







          contentPadding: const EdgeInsets.symmetric(







            horizontal: 16,







            vertical: 14,







          ),







          border: OutlineInputBorder(







            borderRadius: BorderRadius.circular(14),







            borderSide: BorderSide(color: inputBorder),







          ),







          enabledBorder: OutlineInputBorder(







            borderRadius: BorderRadius.circular(14),







            borderSide: BorderSide(color: inputBorder),







          ),







          focusedBorder: OutlineInputBorder(







            borderRadius: BorderRadius.circular(14),







            borderSide: BorderSide(color: inputFocusBorder, width: 1.8),







          ),







          errorBorder: OutlineInputBorder(







            borderRadius: BorderRadius.circular(14),







            borderSide: const BorderSide(color: Color(0xffef4444)),







          ),







        ),







        validator: (v) {







          final text = (v ?? '').trim();







          if (required && text.length < (phone ? 10 : 2)) {







            return phone ? 'Enter a ten-digit mobile number.' : 'Enter $label.';







          }







          if (phone && !RegExp(r'^\d{10}$').hasMatch(text)) {







            return 'Enter a ten-digit mobile number.';







          }







          return null;







        },







      ),







    );







  }















  @override







  Widget build(BuildContext context) {







    final isDark = Theme.of(context).brightness == Brightness.dark || widget.data.session.isDarkMode;







    return PopScope(







      canPop: !saving,







      child: Scaffold(







        appBar: AppBar(
          leading: BackButton(color: isDark ? Colors.white : const Color(0xff0f172a)),
          backgroundColor: isDark
              ? const Color(0xff0b0f19)
              : (widget.data.session.isBetaMode ? widget.data.session.themeBackgroundColor : Colors.white),
          foregroundColor: isDark ? Colors.white : const Color(0xff0f172a),
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: isDark ? const Color(0xff0b0f19) : (widget.data.session.isBetaMode ? widget.data.session.themeBackgroundColor : Colors.white),
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: isDark ? const Color(0xff0b0f19) : const Color(0xfff3f6fc),
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          ),
          iconTheme: IconThemeData(
            color: isDark ? Colors.white : const Color(0xff0f172a),
          ),
          title: Text(
            finish
                ? 'Check Out - ${widget.visit!['shopName']}'
                : (kind == 'Regular' ? 'Regular visit punch in' : 'Open visit punch in'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xff0f172a),
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
          ),
          actions: [
            TrackyuAppBarActions(controller: widget.data.session),
          ],
        ),







        body: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Form(
                  key: form,
                  child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? (finish
                                ? [const Color(0xff0c2340), const Color(0xff082f49)]
                                : (kind == 'Regular'
                                    ? [const Color(0xff1e1b4b), const Color(0xff0f172a)]
                                    : [const Color(0xff062d1c), const Color(0xff052e16)]))
                            : (finish
                                ? [const Color(0xfff0f9ff), const Color(0xffe0f2fe)]
                                : (kind == 'Regular'
                                    ? [const Color(0xffeef2ff), const Color(0xffe0e7ff)]
                                    : [const Color(0xfff0fdf4), const Color(0xffdcfce7)])),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? (finish
                                ? const Color(0x3338bdf8)
                                : (kind == 'Regular' ? const Color(0x33818cf8) : const Color(0x334ade80)))
                            : (finish
                                ? const Color(0xffbae6fd)
                                : (kind == 'Regular' ? const Color(0xffc7d2fe) : const Color(0xffbbf7d0))),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (finish
                                  ? const Color(0xff0284c7)
                                  : (kind == 'Regular' ? const Color(0xff4338ca) : const Color(0xff16a34a)))
                              .withValues(alpha: isDark ? 0.25 : 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: finish
                                  ? [const Color(0xff0284c7), const Color(0xff0369a1)]
                                  : (kind == 'Regular'
                                      ? [const Color(0xff4338ca), const Color(0xff3730a3)]
                                      : [const Color(0xff16a34a), const Color(0xff15803d)]),
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: (finish
                                        ? const Color(0xff0284c7)
                                        : (kind == 'Regular' ? const Color(0xff4338ca) : const Color(0xff16a34a)))
                                    .withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            finish
                                ? Icons.business_center_rounded
                                : (kind == 'Regular' ? Icons.store_rounded : Icons.storefront_rounded),
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            finish
                                ? (widget.visit!['shopName']?.toString() ?? 'Visit Checkout')
                                : (kind == 'Regular'
                                    ? (retailer != null ? (retailer!['name']?.toString() ?? 'Regular Visit') : 'Regular Visit')
                                    : (shop.text.isNotEmpty ? shop.text : 'Open Visit')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: isDark ? Colors.white : const Color(0xff0f172a),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (!finish) ...[
                    if (!open) ...[
                      _buildRegularVisitLocationCard(isDark),
                    ],
                    if (open) ...[
                      field(shop, 'Shop name', 100),
                      field(place, 'Place', 50),
                    ],
                    field(address, 'Shop / Client address', 500),
                    const Text('Take your arrival selfie to confirm this visit.'),
                    const SizedBox(height: 16),
                  ],

                  if (finish) ...[
                    if (open) ...[
                      field(owner, 'Owner name', 50),
                      field(mobile, 'Mobile', 10, phone: true),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: lead,
                        decoration: const InputDecoration(
                          labelText: 'Lead status',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Y', child: Text('Interested')),
                          DropdownMenuItem(
                            value: 'N',
                            child: Text('Not interested'),
                          ),
                          DropdownMenuItem(value: 'L', child: Text('Later')),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setState(() => lead = v!),
                      ),
                      const SizedBox(height: 18),
                    ],
                    field(remark, 'Visit remark / Recovery remark', 500),
                    if (!open) ...[
                      field(orderRemark, 'Order remark', 500, required: false),
                      field(otherRemark, 'Other remark', 500, required: false),
                    ],
                    const Text(
                      'A fresh GPS reading will be saved with checkout.',
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xffef4444)),
                      ),
                    ),

                  Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: finish
                            ? [const Color(0xff0284c7), const Color(0xff0369a1)]
                            : (kind == 'Regular'
                                ? [const Color(0xff4338ca), const Color(0xff3730a3)]
                                : [const Color(0xff16a34a), const Color(0xff15803d)]),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (finish
                                  ? const Color(0xff0284c7)
                                  : (kind == 'Regular' ? const Color(0xff4338ca) : const Color(0xff16a34a)))
                              .withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              finish
                                  ? Icons.check_circle_outline
                                  : Icons.camera_alt_outlined,
                              size: 22,
                            ),
                      label: Text(
                        saving
                            ? 'Please wait…'
                            : finish
                                ? (open ? 'Selfie & Check Out' : 'Check Out Visit')
                                : (kind == 'Regular' ? 'Photo & punch in (Regular)' : 'Photo & punch in (Open)'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),

                  if (finish) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0x1aef4444) : const Color(0xfffff1f2),
                          foregroundColor: const Color(0xffef4444),
                          side: BorderSide(
                            color: const Color(0xffef4444).withValues(alpha: isDark ? 0.4 : 0.3),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: saving ? null : _discardVisit,
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        label: const Text(
                          'Discard / Cancel in-progress visit',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              await widget.data.load();
                              if (context.mounted) Navigator.pop(context);
                            },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Reload visits'),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (saving)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
              child: Center(
                child: GpsRadarLoader(
                  label: finish
                      ? 'Verifying Check-Out with Server...'
                      : (kind == 'Regular'
                          ? 'Validating Regular Visit with Server...'
                          : 'Recording Visit GPS Location...'),
                  sublabel: 'Verifying party geofence & server rules',
                  size: 110,
                ),
              ),
            ),
          ),
      ],
    ),
  ),
);







  }

  Widget _buildRegularVisitLocationCard(bool isDark) {
final r = retailer;
    if (r == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xff1e1b4b) : const Color(0xffeef2ff),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xff6366f1).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.store_rounded, color: Color(0xff6366f1), size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No retailer selected. Please choose a mapped retailer first.',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Choose'),
            ),
          ],
        ),
      );
    }

    final mappedAddress = r['address']?.toString().trim() ?? '';
    final mappedPlace = r['place']?.toString().trim() ?? '';
    final rLat = (r['latitude'] ?? r['Latitude'] ?? r['xretailer'] as num?)?.toDouble();
    final rLng = (r['longitude'] ?? r['Longitude'] ?? r['yretailer'] as num?)?.toDouble();
    final bool isGeotagged = rLat != null && rLng != null && rLat != 0.0 && rLng != 0.0;

    double? dist;
    if (isGeotagged && _currentLat != null && _currentLng != null && _currentLat != 0.0 && _currentLng != 0.0) {
      dist = _calculateDistanceMeters(_currentLat!, _currentLng!, rLat, rLng);
    }

    final maxRange = widget.data.session.regularVisitRangeMeters;
    final bool isWithinRange = dist != null && dist <= maxRange;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff161e2e) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isWithinRange
              ? const Color(0xff10b981).withValues(alpha: 0.4)
              : (dist != null
                  ? const Color(0xffef4444).withValues(alpha: 0.4)
                  : (isDark ? const Color(0xff334155) : const Color(0xffe2e8f0))),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Party Name & Change Button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xff4338ca).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.store_rounded, color: Color(0xff6366f1), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['name']?.toString() ?? 'Retailer',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xff0f172a),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (r['id'] != null)
                      Text(
                        'Party Code: #${r['id']}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: saving ? null : () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // 1. Mapped Address Section
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.pin_drop_rounded, size: 16, color: Color(0xff6366f1)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MAPPED ADDRESS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: isDark ? const Color(0xff818cf8) : const Color(0xff4338ca),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      mappedAddress.isNotEmpty ? mappedAddress : (mappedPlace.isNotEmpty ? mappedPlace : 'No registered address'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xff1e293b),
                      ),
                    ),
                    if (isGeotagged)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Coords: ${rLat!.toStringAsFixed(5)}, ${rLng!.toStringAsFixed(5)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 2. Current Address Section
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.my_location_rounded, size: 16, color: Color(0xff0284c7)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT LIVE ADDRESS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _currentAddress.isNotEmpty ? _currentAddress : 'Acquiring GPS location...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xff1e293b),
                      ),
                    ),
                    if (_currentLat != null && _currentLng != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Coords: ${_currentLat!.toStringAsFixed(5)}, ${_currentLng!.toStringAsFixed(5)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 3. Geofence & Distance Status Box (500 meter range indicator)
          if (!isGeotagged) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfff59e0b).withValues(alpha: isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xfff59e0b).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Color(0xfff59e0b), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Location Not Geo-Tagged',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xfff59e0b)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'This party has no registered GPS coordinates. Please tag location first.',
                    style: TextStyle(fontSize: 12, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff0284c7),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                      label: const Text('Geo-Tag Retailer Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RetailerGeoTagPage(
                              controller: widget.data.session,
                              initialRetailer: r,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ] else if (dist != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isWithinRange ? const Color(0xff10b981) : const Color(0xffef4444))
                    .withValues(alpha: isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (isWithinRange ? const Color(0xff10b981) : const Color(0xffef4444))
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isWithinRange ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: isWithinRange ? const Color(0xff10b981) : const Color(0xffef4444),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isWithinRange
                              ? 'Distance: ${dist.round()}m (Within ${maxRange.round()}m Allowed Range)'
                              : 'Distance: ${dist.round()}m (Out of ${maxRange.round()}m Range)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isWithinRange ? const Color(0xff10b981) : const Color(0xffef4444),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isWithinRange
                              ? 'You are at the verified shop location. Check-in allowed.'
                              : 'You are ${(dist - maxRange).round()}m outside the ${maxRange.round()}m geofence.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white70 : const Color(0xff334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: const [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Calculating live distance to party...',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}


double _calculateDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusMeters = 6371000.0;
  final dLat = (lat2 - lat1) * (math.pi / 180.0);
  final dLon = (lon2 - lon1) * (math.pi / 180.0);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * (math.pi / 180.0)) *
          math.cos(lat2 * (math.pi / 180.0)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

/// Dedicated Mapped Retailers Selection Screen for Regular Visits
class SelectRegularPartyPage extends StatefulWidget {
  final VisitsData data;
  const SelectRegularPartyPage({super.key, required this.data});

  @override
  State<SelectRegularPartyPage> createState() => _SelectRegularPartyPageState();
}

class _SelectRegularPartyPageState extends State<SelectRegularPartyPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Json> _retailers = [];
  bool _loading = true;
  String? _error;
  double? _currentLat, _currentLng;
  String _currentAddress = 'Acquiring GPS location...';
  String _filter = 'all'; // 'all', 'tagged', 'pending'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = widget.data.active ?? widget.data.session.activeVisit;
      if (active != null && mounted) {
        Navigator.pop(context);
      }
    });
    _loadLocationAndRetailers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocationAndRetailers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final loc = await widget.data.session.locate();
      final lat = (loc['latitude'] as num?)?.toDouble();
      final lng = (loc['longitude'] as num?)?.toDouble();
      String addr = loc['textLocation']?.toString() ?? '';
      if (lat != null && lng != null && (addr.isEmpty || addr == '-' || addr.contains('not loaded'))) {
        final rev = await TrackyuAddressCache.reverseGeocode(lat, lng);
        if (rev != null && rev.trim().isNotEmpty) {
          addr = rev.trim();
        }
      }

      List<Json> list = [];
      try {
        final serverList = await widget.data.session.api.request('MobileVisits/retailers?search=');
        list = jsonRows(serverList);
        if (widget.data.session.local != null) {
          await widget.data.session.local!.write('retailers', {'rows': list});
        }
      } catch (_) {
        list = await widget.data.search('');
      }

      if (mounted) {
        setState(() {
          _currentLat = lat;
          _currentLng = lng;
          _currentAddress = addr.isNotEmpty ? addr : 'Live GPS active';
          _retailers = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load assigned retailers: $e';
          _loading = false;
        });
      }
    }
  }

  bool _isTagged(Json r) {
    final lat = r['latitude'] ?? r['Latitude'] ?? r['xretailer'];
    final lng = r['longitude'] ?? r['Longitude'] ?? r['yretailer'];
    if (lat == null || lng == null) return false;
    final dLat = double.tryParse(lat.toString()) ?? 0.0;
    final dLng = double.tryParse(lng.toString()) ?? 0.0;
    return dLat != 0.0 && dLng != 0.0;
  }

  double? _getDistance(Json r) {
    if (_currentLat == null || _currentLng == null) return null;
    final lat = r['latitude'] ?? r['Latitude'] ?? r['xretailer'];
    final lng = r['longitude'] ?? r['Longitude'] ?? r['yretailer'];
    if (lat == null || lng == null) return null;
    final dLat = double.tryParse(lat.toString()) ?? 0.0;
    final dLng = double.tryParse(lng.toString()) ?? 0.0;
    if (dLat == 0.0 && dLng == 0.0) return null;
    return _calculateDistanceMeters(_currentLat!, _currentLng!, dLat, dLng);
  }

  Future<void> _onSelectRetailer(Json r) async {
    final active = widget.data.active ?? widget.data.session.activeVisit;
    final bool hasActive = active != null || widget.data.session.pendingVisits.any((p) => p['finish'] != true && !queuedRegularVisit(p));
    if (hasActive) {
      Navigator.pop(context);
      return;
    }

    final tagged = _isTagged(r);
    if (!tagged) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xfff59e0b), size: 24),
              SizedBox(width: 8),
              Text('Location Not Tagged', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: Text(
            '"${r['name']}" has not been geo-tagged yet.\n\nPlease tag the shop location with GPS coordinates to enable regular check-ins.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff0284c7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_location_alt_rounded, size: 16),
              label: const Text('Geo-Tag Retailer Now'),
              onPressed: () {
                Navigator.pop(ctx);
                _openGeotag(r);
              },
            ),
          ],
        ),
      );
      return;
    }

    final dist = _getDistance(r);
    final maxRange = widget.data.session.regularVisitRangeMeters;
    if (dist != null && dist > maxRange) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.location_off_rounded, color: Color(0xffef4444), size: 22),
              SizedBox(width: 8),
              Text('Location Out of Range', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'You are currently ${dist.round()}m away from "${r['name']}".\n\nPlease be within ${maxRange.round()}m of the registered party location to start a Regular Visit.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisitForm(
          data: widget.data,
          initialKind: 'Regular',
          initialRetailer: r,
        ),
      ),
    );
    if (res == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _openGeotag(Json r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RetailerGeoTagPage(
          controller: widget.data.session,
          initialRetailer: r,
        ),
      ),
    );
    _loadLocationAndRetailers();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xff0b0f19) : const Color(0xfff8fafc);
    final cardBg = isDark ? const Color(0xff161e2e) : Colors.white;
    final borderColor = isDark ? const Color(0xff334155) : const Color(0xffe2e8f0);
    final textPrimary = isDark ? Colors.white : const Color(0xff0f172a);
    final textSecondary = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _retailers.where((r) {
      if (_filter == 'tagged' && !_isTagged(r)) return false;
      if (_filter == 'pending' && _isTagged(r)) return false;
      if (query.isNotEmpty) {
        final name = (r['name']?.toString() ?? '').toLowerCase();
        final id = (r['id']?.toString() ?? '').toLowerCase();
        final addr = (r['address']?.toString() ?? '').toLowerCase();
        return name.contains(query) || id.contains(query) || addr.contains(query);
      }
      return true;
    }).toList();

    final taggedCount = _retailers.where(_isTagged).length;
    final pendingCount = _retailers.length - taggedCount;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        leading: BackButton(color: isDark ? Colors.white : const Color(0xff0f172a)),
        backgroundColor: isDark ? const Color(0xff0b0f19) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xff0f172a),
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
        title: const Text(
          'Select Retailer',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          TrackyuAppBarActions(controller: widget.data.session),
        ],
      ),
      body: _loading
          ? Center(
              child: GpsRadarLoader(
                label: 'Loading Assigned Retailers...',
                sublabel: 'Fetching mapped parties & GPS locations',
                size: 110,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadLocationAndRetailers,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location_rounded, size: 16, color: Color(0xff0284c7)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentAddress,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: _loadLocationAndRetailers,
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.refresh_rounded, size: 16, color: Color(0xff0284c7)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: 'Search mapped retailers by name or code...',
                      filled: true,
                      fillColor: cardBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Wrap(spacing: 8, runSpacing: 8,
                    children: [
                      _buildFilterChip('all', 'All (${_retailers.length})', isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('tagged', '📍 Tagged ($taggedCount)', isDark, activeColor: const Color(0xff10b981)),
                      const SizedBox(width: 8),
                      _buildFilterChip('pending', '⚠️ Pending ($pendingCount)', isDark, activeColor: const Color(0xfff59e0b)),
                    ],
                  ),

                  const SizedBox(height: 14),

                  if (filtered.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.storefront_outlined, size: 48, color: textSecondary.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text(
                              query.isNotEmpty
                                  ? 'No retailers matching "$query"'
                                  : 'No retailers found for selected filter.',
                              style: TextStyle(fontSize: 14, color: textSecondary, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xff4338ca),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RetailerGeoTagPage(
                                      controller: widget.data.session,
                                    ),
                                  ),
                                );
                                _loadLocationAndRetailers();
                              },
                              icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                              label: const Text('Open Retailer Geo-Tag', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    for (final r in filtered) ...[
                      _buildRetailerCard(r, isDark, cardBg, borderColor, textPrimary, textSecondary),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label, bool isDark, {Color? activeColor}) {
    final isSelected = _filter == filterKey;
    final color = activeColor ?? const Color(0xff4338ca);
    return InkWell(
      onTap: () => setState(() => _filter = filterKey),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: isDark ? 0.3 : 0.15) : (isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xff334155) : const Color(0xffe2e8f0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? (isDark ? Colors.white : color) : (isDark ? const Color(0xff94a3b8) : const Color(0xff64748b)),
          ),
        ),
      ),
    );
  }

  Widget _buildRetailerCard(
    Json r,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textPrimary,
    Color textSecondary,
  ) {
    final tagged = _isTagged(r);
    final dist = _getDistance(r);
    final maxRange = widget.data.session.regularVisitRangeMeters;
    final isWithinRange = dist != null && dist <= maxRange;
    final name = r['name']?.toString() ?? 'Retailer';
    final address = r['address']?.toString() ?? r['place']?.toString() ?? '';
    final id = r['id']?.toString() ?? '';

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onSelectRetailer(r),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xff4338ca).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.store_rounded, color: Color(0xff6366f1), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (id.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '#$id',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textSecondary),
                                ),
                              ),
                          ],
                        ),
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            address,
                            style: TextStyle(fontSize: 12, color: textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Wrap(
                spacing: 8, runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: tagged
                          ? const Color(0xff10b981).withValues(alpha: 0.15)
                          : const Color(0xfff59e0b).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tagged ? '📍 Geotagged' : '⚠️ Pending Geotag',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: tagged ? const Color(0xff10b981) : const Color(0xfff59e0b),
                      ),
                    ),
                  ),

                  if (tagged && dist != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isWithinRange
                            ? const Color(0xff10b981).withValues(alpha: 0.15)
                            : const Color(0xffef4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isWithinRange
                            ? '✅ ${dist.round()}m (Within ${maxRange.round()}m)'
                            : '⚠️ ${dist.round()}m (Out of range)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isWithinRange ? const Color(0xff10b981) : const Color(0xffef4444),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  if (!tagged) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff0284c7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                        label: const Text('Tag Location', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => _openGeotag(r),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isWithinRange ? const Color(0xff4338ca) : const Color(0xff64748b),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(isWithinRange ? Icons.store_rounded : Icons.location_off_rounded, size: 16),
                        label: Text(
                          isWithinRange ? 'Start Visit' : 'Start Visit (${dist != null ? "${dist.round()}m Away" : "Out of Range"})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => _onSelectRetailer(r),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_location_alt_outlined, size: 20, color: Color(0xff0284c7)),
                      tooltip: 'Update Geotag',
                      onPressed: () => _openGeotag(r),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
