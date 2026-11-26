import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'controller.dart';
import 'app.dart' show appVersion, isBetaVersion;
import 'env_config.dart';

class ApkInstaller {
  static const MethodChannel _channel = MethodChannel('trackyu/device_settings');
  static bool _dialogShowing = false;

  /// Trigger APK installation via native Android FileProvider + Intent.
  static Future<bool> installFile(String filePath) async {
    try {
      final res = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Open Android native Downloads folder in My Files / Downloads app
  static Future<bool> openDownloadsFolder() async {
    try {
      final res = await _channel.invokeMethod<bool>('openDownloads');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Scan device for previously downloaded Trackyu APK
  static Future<File?> findDownloadedApk(String version) async {
    final cleanVer = version.replaceAll(RegExp(r'^[vV]'), '').trim();
    final candidates = <String>[
      '/storage/emulated/0/Download/trackyu_v$cleanVer.apk',
      '/storage/emulated/0/Download/Trackyu_v$cleanVer.apk',
      '/storage/emulated/0/Download/trackyu_v$version.apk',
      '/storage/emulated/0/Download/Trackyu_v$version.apk',
      '/storage/emulated/0/Download/Trackyu_latest.apk',
      '/storage/emulated/0/Download/Trackyu_latest (1).apk',
      '/storage/emulated/0/Download/Trackyu_latest (2).apk',
      '/storage/emulated/0/Download/trackyu_latest.apk',
    ];
    try {
      final extDirs = await getExternalCacheDirectories();
      if (extDirs != null) {
        for (final dir in extDirs) {
          candidates.add('${dir.path}/trackyu_v$version.apk');
          candidates.add('${dir.path}/trackyu_v$cleanVer.apk');
        }
      }
      final temp = await getTemporaryDirectory();
      candidates.add('${temp.path}/trackyu_v$version.apk');
      candidates.add('${temp.path}/trackyu_v$cleanVer.apk');
    } catch (_) {}

    for (final p in candidates) {
      try {
        final f = File(p);
        if (f.existsSync() && f.lengthSync() > 10 * 1024 * 1024) {
          return f;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Show the interactive in-app update popup dialog.
  static Future<void> showUpdatePopup(
    BuildContext context, {
    required TrackyuController controller,
    bool force = false,
  }) async {
    if (_dialogShowing) return;
    if (isBetaVersion) return; // Never show update dialog on Beta builds
    final policy = controller.versionPolicy;
    if (policy == null) return;

    final isDefault = policy['isDefault'] == true;
    final isForce = force || policy['forceUpdate'] == true || policy['isAllowed'] == false;
    if (isDefault && !isForce) return;

    final defaultVer = (policy['defaultVersion']?.toString() ?? '').replaceAll(RegExp(r'^[vV]'), '').trim();
    if (!isForce && defaultVer.isNotEmpty && compareVersions(appVersion, defaultVer) >= 0) {
      return;
    }

    _dialogShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !isForce,
        builder: (dialogCtx) => PopScope(
          canPop: !isForce,
          child: _UpdateDialog(
            controller: controller,
            policy: policy,
            isForce: isForce,
          ),
        ),
      );
    } finally {
      _dialogShowing = false;
    }
  }
}

class _UpdateDialog extends StatefulWidget {
  final TrackyuController controller;
  final Json policy;
  final bool isForce;

  const _UpdateDialog({
    required this.controller,
    required this.policy,
    required this.isForce,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  String _status = '';
  CancelToken? _cancelToken;
  File? _downloadedFile;
  bool _browserOpened = false;

  String get defaultVer => widget.policy['defaultVersion']?.toString() ?? 'Latest';
  String get downloadUrl =>
      widget.policy['downloadUrl']?.toString() ?? TrackyuEnv.downloadUrl;
  String get portalUrl =>
      widget.policy['portalUrl']?.toString() ?? TrackyuEnv.downloadPortalUrl;
  String get releaseNotes =>
      widget.policy['releaseNotes']?.toString() ?? 'Performance improvements and bug fixes.';

  @override
  void initState() {
    super.initState();
    _scanDownloadedFile();
  }

  Future<void> _scanDownloadedFile() async {
    try {
      final f = await ApkInstaller.findDownloadedApk(defaultVer);
      if (f != null && mounted) {
        setState(() => _downloadedFile = f);
      }
    } catch (_) {}
  }

  Future<void> _startDownloadAndInstall() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0.0;
      _status = 'Connecting to server...';
    });

    _cancelToken = CancelToken();

    try {
      Directory? targetDir;
      try {
        final extDirs = await getExternalCacheDirectories();
        if (extDirs != null && extDirs.isNotEmpty) {
          targetDir = extDirs.first;
        }
      } catch (_) {}
      targetDir ??= await getTemporaryDirectory();

      final savePath = '${targetDir.path}/trackyu_v$defaultVer.apk';
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      final dio = Dio();
      await dio.download(
        downloadUrl,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            final p = received / total;
            final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totMb = (total / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _progress = p;
              _status = 'Downloading: ${(p * 100).toInt()}% ($recMb MB / $totMb MB)';
            });
          }
        },
      );

      if (!mounted) return;
      final downloaded = File(savePath);
      setState(() {
        _downloading = false;
        _downloadedFile = downloaded;
        _status = 'Opening APK Installer...';
      });

      final installed = await ApkInstaller.installFile(savePath);
      if (!installed && mounted) {
        setState(() {
          _status = 'Installer closed. Tap "Install Now" or "Open Downloads".';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _status = 'Download failed. Tap below to download from browser.';
        });
      }
    }
  }

  Future<void> _openBrowser() async {
    setState(() => _browserOpened = true);
    try {
      final uri = Uri.parse(downloadUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        final uri = Uri.parse(portalUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    // Poll for downloaded file in Downloads folder
    for (int i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _scanDownloadedFile();
      if (_downloadedFile != null) break;
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = widget.isForce ? const Color(0xffdc2626) : const Color(0xff1c6799);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 10,
      backgroundColor: isDark ? const Color(0xff1e1e1e) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isForce ? Icons.warning_amber_rounded : Icons.system_update_rounded,
                        size: 14,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        widget.isForce ? 'FORCE UPDATE REQUIRED' : 'UPDATE AVAILABLE',
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (!widget.isForce && !_downloading)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Icon + Title Row
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.install_mobile_rounded, color: primaryColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Trackyu v$defaultVer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xff102c4a),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isForce
                            ? 'This update is required to continue using the app.'
                            : 'A new version is ready to install.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Release Notes Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff25292e) : const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xff33383f) : const Color(0xffe2e8f0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "What's New:",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? const Color(0xffcbd5e1) : const Color(0xff475569),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    releaseNotes,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: isDark ? Colors.white70 : const Color(0xff1e293b),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Progress or Buttons
            if (_downloading) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: isDark ? const Color(0xff33383f) : const Color(0xffe2e8f0),
                color: primaryColor,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              if (_downloadedFile != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xff064e3b).withValues(alpha: 0.3)
                        : const Color(0xffecfdf5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xff10b981).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xff10b981),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Downloaded File Ready',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Color(0xff10b981),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_downloadedFile!.path.split(Platform.pathSeparator).last} | ${(_downloadedFile!.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? const Color(0xff94a3b8)
                                    : const Color(0xff475569),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await ApkInstaller.installFile(_downloadedFile!.path);
                    if (!ok) {
                      await ApkInstaller.openDownloadsFolder();
                    }
                  },
                  icon: const Icon(Icons.install_mobile_rounded, size: 20),
                  label: Text(
                    'Install Now (v$defaultVer)',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ] else ...[
                FilledButton.icon(
                  onPressed: _startDownloadAndInstall,
                  icon: const Icon(Icons.system_update_alt_rounded, size: 19),
                  label: Text(
                    'Update Now (v$defaultVer)',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              if (_browserOpened && _downloadedFile == null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Downloading update in browser. Please check your notification drawer or Downloads folder.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? const Color(0xff94a3b8) : const Color(0xff475569),
                    ),
                  ),
                ),
              // Open Downloads Folder Button
              OutlinedButton.icon(
                onPressed: () => ApkInstaller.openDownloadsFolder(),
                icon: const Icon(Icons.folder_open_rounded, size: 19),
                label: const Text(
                  'Open Downloads Folder',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              if (_downloadedFile != null)
                Center(
                  child: TextButton(
                    onPressed: _startDownloadAndInstall,
                    child: const Text(
                      'Re-download update',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),

              if (!widget.isForce) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Later',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xff94a3b8)
                          : const Color(0xff64748b),
                    ),
                  ),
                ),
              ],
            ],

            // Fallback link
            Center(
              child: TextButton.icon(
                onPressed: _openBrowser,
                icon: const Icon(Icons.open_in_browser_rounded, size: 15),
                label: const Text(
                  'Download from browser',
                  style: TextStyle(fontSize: 11.5),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: isDark
                      ? const Color(0xff26c6da)
                      : const Color(0xff1c6799),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

