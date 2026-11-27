import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'controller.dart';
import 'env_config.dart';
import 'app.dart' show appVersion;
import 'apk_installer.dart';

class ApkUpdateRequiredPage extends StatefulWidget {
  final TrackyuController controller;
  final bool isDark;

  const ApkUpdateRequiredPage({
    super.key,
    required this.controller,
    this.isDark = false,
  });

  @override
  State<ApkUpdateRequiredPage> createState() => _ApkUpdateRequiredPageState();
}

class _ApkUpdateRequiredPageState extends State<ApkUpdateRequiredPage> {
  bool _checking = false;

  Future<void> _checkAgain() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await widget.controller.checkVersionPolicy(appVersion);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openUrl(String? urlString, {String? fallback}) async {
    final target = (urlString != null && urlString.isNotEmpty)
        ? urlString
        : (fallback ?? TrackyuEnv.downloadUrl);
    try {
      final uri = Uri.parse(target);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $target')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.controller.versionPolicy;
    final defaultVer = policy?['defaultVersion']?.toString() ?? '1.0.72';
    final downloadUrl = policy?['downloadUrl']?.toString() ?? TrackyuEnv.downloadUrl;
    final portalUrl = policy?['portalUrl']?.toString() ?? TrackyuEnv.downloadPortalUrl;
    final releaseNotes = policy?['releaseNotes']?.toString() ??
        'Attendance History UI redesign, live photo selfies, and stability improvements.';
    final message = policy?['message']?.toString() ??
        'Trackyu $appVersion has been discontinued by administrator. Please update to v$defaultVer to continue.';

    final bgColor = widget.isDark ? const Color(0xff121212) : const Color(0xfff3f6fb);
    final cardColor = widget.isDark ? const Color(0xff1e1e1e) : Colors.white;
    final textColor = widget.isDark ? Colors.white : const Color(0xff102c4a);
    final textMuted = widget.isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);
    final borderColor = widget.isDark ? const Color(0xff2d3135) : const Color(0xffe2e8f0);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Pill
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xffdc2626).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xffdc2626).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xffdc2626)),
                            SizedBox(width: 6),
                            Text(
                              'UPDATE MANDATORY',
                              style: TextStyle(
                                color: Color(0xffdc2626),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Big Visual Icon
                    Center(
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xffdc2626).withValues(alpha: 0.1),
                          border: Border.all(color: const Color(0xffdc2626).withValues(alpha: 0.25), width: 2),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.system_update_rounded,
                            size: 46,
                            color: Color(0xffdc2626),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Header Title
                    Text(
                      'App Update Required',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Current vs Required text
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // New Version Details Card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'LATEST PRODUCTION BUILD',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Trackyu v$defaultVer',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xff16a34a).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, size: 13, color: Color(0xff16a34a)),
                                    SizedBox(width: 4),
                                    Text(
                                      'VERIFIED',
                                      style: TextStyle(
                                        color: Color(0xff16a34a),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Text(
                            "What's New in this update:",
                            style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            releaseNotes,
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: widget.isDark ? const Color(0xff2d3135) : const Color(0xfff1f5f9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 14, color: textMuted),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Your installed build: $appVersion',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Primary Download Button
                    FilledButton.icon(
                      onPressed: () => ApkInstaller.showUpdatePopup(context, controller: widget.controller, force: true),
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        'Download Trackyu v$defaultVer',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff1c6799),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Secondary Portal Page Button
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(portalUrl),
                      icon: const Icon(Icons.language_rounded, size: 18),
                      label: const Text(
                        'Open Download Portal in Browser',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: widget.isDark ? const Color(0xff26c6da) : const Color(0xff1c6799),
                        side: BorderSide(
                          color: widget.isDark ? const Color(0xff26c6da) : const Color(0xff1c6799),
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Check again button
                    Center(
                      child: TextButton.icon(
                        onPressed: _checking ? null : _checkAgain,
                        icon: _checking
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.refresh_rounded, size: 16, color: textMuted),
                        label: Text(
                          _checking ? 'Checking...' : 'Check Again',
                          style: TextStyle(
                            color: textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

