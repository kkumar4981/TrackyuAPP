import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'controller.dart';

enum NetworkQuality { offline, slow, good, fast }

class NetworkStatus {
  final bool isOnline;
  final String typeName; // 'WiFi', '4G/5G', 'Offline'
  final int? latencyMs;
  final NetworkQuality quality;
  final DateTime lastChecked;

  const NetworkStatus({
    required this.isOnline,
    required this.typeName,
    this.latencyMs,
    required this.quality,
    required this.lastChecked,
  });

  String get speedLabel {
    if (!isOnline) return 'No Internet';
    if (latencyMs == null) return '$typeName • Checking...';
    if (quality == NetworkQuality.fast) return '$typeName • Fast (${latencyMs}ms) ⚡';
    if (quality == NetworkQuality.good) return '$typeName • Good (${latencyMs}ms)';
    if (quality == NetworkQuality.slow) return '$typeName • Slow (${latencyMs}ms)';
    return '$typeName • Offline';
  }

  String get compactLabel {
    if (!isOnline) return 'Offline';
    if (latencyMs == null) return typeName;
    return '$typeName • ${latencyMs}ms';
  }

  Color get statusColor {
    if (!isOnline) return const Color(0xffef4444);
    if (quality == NetworkQuality.fast) return const Color(0xff10b981);
    if (quality == NetworkQuality.good) return const Color(0xff0284c7);
    if (quality == NetworkQuality.slow) return const Color(0xfff59e0b);
    return const Color(0xffef4444);
  }

  IconData get icon {
    if (!isOnline) return Icons.wifi_off_rounded;
    if (typeName == 'WiFi') return Icons.wifi_rounded;
    return Icons.signal_cellular_alt_rounded;
  }
}

class NetworkQualityMonitor extends ChangeNotifier {
  final TrackyuApi api;
  NetworkQualityMonitor(this.api);

  static NetworkQualityMonitor? _instance;
  static NetworkQualityMonitor instance(TrackyuApi api) =>
      _instance ??= NetworkQualityMonitor(api);

  NetworkStatus _status = NetworkStatus(
    isOnline: true,
    typeName: 'WiFi',
    latencyMs: null,
    quality: NetworkQuality.good,
    lastChecked: DateTime.now(),
  );

  NetworkStatus get status => _status;

  Timer? _timer;
  StreamSubscription? _sub;
  bool _disposed = false;
  bool _probing = false;

  void start() {
    _timer?.cancel();
    _sub?.cancel();

    // Listen to connectivity changes
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      probeNow();
    });

    // Probe latency every 15 seconds
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => probeNow());

    // Immediate initial probe
    probeNow();
  }

  Future<void> probeNow() async {
    if (_probing || _disposed) return;
    _probing = true;
    try {
      final connectivityList = await Connectivity().checkConnectivity();
      final hasConn = connectivityList.any((r) => r != ConnectivityResult.none);

      String type = 'Mobile data';
      if (connectivityList.contains(ConnectivityResult.wifi)) {
        type = 'WiFi';
      } else if (connectivityList.contains(ConnectivityResult.mobile)) {
        type = '4G/5G';
      } else if (connectivityList.contains(ConnectivityResult.ethernet)) {
        type = 'LAN';
      }

      if (!hasConn) {
        if (!_disposed) {
          _status = NetworkStatus(
            isOnline: false,
            typeName: 'Offline',
            quality: NetworkQuality.offline,
            lastChecked: DateTime.now(),
          );
          notifyListeners();
        }
        return;
      }

      final watch = Stopwatch()..start();
      int latency = 0;
      bool ok = false;
      try {
        final res = await api.dio.get(
          '${api.baseUrl.replaceAll(RegExp(r"/+$"), "")}/Health',
          options: Options(
            receiveTimeout: const Duration(seconds: 8),
            sendTimeout: const Duration(seconds: 8),
          ),
        );
        watch.stop();
        latency = watch.elapsedMilliseconds;
        ok = res.data is Map && res.data['success'] == true;
      } catch (_) {
        ok = false;
      }

      if (_disposed) return;

      if (!ok) {
        _status = NetworkStatus(
          isOnline: false,
          typeName: type,
          quality: NetworkQuality.offline,
          lastChecked: DateTime.now(),
        );
      } else {
        NetworkQuality q;
        if (latency < 600) {
          q = NetworkQuality.fast;
        } else if (latency < 1500) {
          q = NetworkQuality.good;
        } else {
          q = NetworkQuality.slow;
        }
        _status = NetworkStatus(
          isOnline: true,
          typeName: type,
          latencyMs: latency,
          quality: q,
          lastChecked: DateTime.now(),
        );
      }
      notifyListeners();
    } catch (_) {
    } finally {
      _probing = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    if (identical(_instance, this)) {
      _instance = null;
    }
    super.dispose();
  }
}

class SyncNetworkAppBarPill extends StatelessWidget {
  final TrackyuController controller;
  final NetworkQualityMonitor network;
  final bool busy;
  final VoidCallback onSync;

  const SyncNetworkAppBarPill({
    super.key,
    required this.controller,
    required this.network,
    required this.busy,
    required this.onSync,
  });

    @override
  Widget build(BuildContext context) {
    final isDark = controller.isDarkMode;
    final isSyncing = busy || controller.isSyncing;
    final pending = controller.pendingCount;
    final isOnline = network.status.isOnline;

    final isWifi = network.status.typeName == 'WiFi';
    final netIcon = !isOnline
        ? Icons.wifi_off_rounded
        : (isWifi ? Icons.wifi_rounded : Icons.signal_cellular_alt_rounded);

    final Color iconColor;
    final Color bgColor;
    final Color borderColor;
    final String tooltipMsg;

    if (isSyncing) {
      iconColor = const Color(0xff0284c7);
      bgColor = isDark ? const Color(0xff0c2a42) : const Color(0xfff0f9ff);
      borderColor = const Color(0xff38bdf8);
      tooltipMsg = 'Syncing...';
    } else if (!isOnline) {
      iconColor = const Color(0xffe11d48);
      bgColor = isDark ? const Color(0xff3f1218) : const Color(0xfffff1f2);
      borderColor = const Color(0xfff43f5e);
      tooltipMsg = 'No Internet connection';
    } else if (pending > 0) {
      iconColor = const Color(0xffea580c);
      bgColor = isDark ? const Color(0xff2d1704) : const Color(0xfffff7ed);
      borderColor = const Color(0xfff97316);
      tooltipMsg = '$pending pending to sync';
    } else {
      iconColor = isDark ? const Color(0xff34d399) : const Color(0xff059669);
      bgColor = isDark
          ? const Color(0xff064e3b).withValues(alpha: 0.35)
          : const Color(0xffecfdf5);
      borderColor = isDark
          ? const Color(0xff059669).withValues(alpha: 0.45)
          : const Color(0xffa7f3d0);
      tooltipMsg = isWifi ? 'WiFi connected & synced' : 'Mobile data connected & synced';
    }

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltipMsg,
        child: InkWell(
          onTap: () {
            network.probeNow();
            onSync();
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: borderColor,
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: isSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xff0284c7),
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        pending > 0 ? Icons.cloud_upload_rounded : netIcon,
                        size: 19,
                        color: iconColor,
                      ),
                      if (isOnline && pending == 0)
                        Positioned(
                          right: 1,
                          top: 1,
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: iconColor,
                            ),
                          ),
                        ),
                      if (pending > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xffea580c),
                            ),
                            constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class NetworkSyncStatusCard extends StatelessWidget {
  final TrackyuController controller;
  final NetworkQualityMonitor network;
  final VoidCallback onSync;

  const NetworkSyncStatusCard({
    super.key,
    required this.controller,
    required this.network,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = controller.isDarkMode;
    final status = network.status;
    final pending = controller.pendingCount;
    final isSyncing = controller.isSyncing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff181b20) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xff2d3135) : const Color(0xffe2e8f0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Internet speed & connection status
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: status.statusColor.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  status.icon,
                  color: status.statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Internet: ${status.typeName}',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xff0f172a),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: status.statusColor.withValues(alpha: isDark ? 0.25 : 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.isOnline
                                ? (status.latencyMs != null
                                    ? '${status.latencyMs}ms • ${status.quality == NetworkQuality.fast ? "Fast ⚡" : (status.quality == NetworkQuality.good ? "Normal" : "Slow")}'
                                    : 'Connected')
                                : 'Offline',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: status.statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.isOnline
                          ? 'Server connection active & responding.'
                          : 'No internet connection detected.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Test network speed & sync',
                icon: const Icon(Icons.refresh_rounded, size: 18),
                color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                onPressed: () {
                  network.probeNow();
                  onSync();
                },
              ),
            ],
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(
              height: 1,
              color: isDark ? const Color(0xff2d3135) : const Color(0xfff1f5f9),
            ),
          ),

          // Sync status row
          if (isSyncing)
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xff0284c7),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Syncing in progress... Uploading data.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),
                  ),
                ),
              ],
            )
          else if (pending > 0)
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 16,
                        color: Color(0xffea580c),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '$pending pending sync',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xffea580c),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xffea580c),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  onPressed: onSync,
                  icon: const Icon(Icons.bolt_rounded, size: 14),
                  label: const Text(
                    'Upload fast ⚡',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: Color(0xff10b981),
                ),
                const SizedBox(width: 6),
                Text(
                  'All phone records synced with server.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
