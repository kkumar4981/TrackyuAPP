import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'controller.dart';

class EnvironmentItem {
  final String key;
  final String name;
  final String apiBaseUrl;
  final String portalUrl;
  final String downloadPortalUrl;
  final String downloadUrl;
  final bool isDefault;
  String get displayName => name;

  const EnvironmentItem({
    required this.key,
    required this.name,
    required this.apiBaseUrl,
    required this.portalUrl,
    required this.downloadPortalUrl,
    required this.downloadUrl,
    this.isDefault = false,
  });

  factory EnvironmentItem.fromJson(Map<String, dynamic> json) {
    final key = (json['key'] ?? json['environmentKey'] ?? 'prod').toString().toLowerCase();
    final name = (json['name'] ?? json['displayName'] ?? key.toUpperCase()).toString();
    final apiBaseUrl = (json['apiBaseUrl'] ?? 'https://oyuapi.in/trackyuapi/api').toString().trim().replaceAll(RegExp(r'/+$'), '');
    final portalUrl = (json['portalUrl'] ?? 'https://trackyuweb.runasp.net').toString().trim().replaceAll(RegExp(r'/+$'), '');
    final dlPortal = (json['downloadPortalUrl'] ?? '$portalUrl/download').toString().trim();
    final dlUrl = (json['downloadUrl'] ?? json['apkBaseDownloadUrl'] != null
        ? '${json['apkBaseDownloadUrl'].toString().replaceAll(RegExp(r'/+$'), '')}/Trackyu_latest.apk'
        : '$apiBaseUrl/../apk/Trackyu_latest.apk').toString().trim();

    return EnvironmentItem(
      key: key,
      name: name,
      apiBaseUrl: apiBaseUrl,
      portalUrl: portalUrl,
      downloadPortalUrl: dlPortal,
      downloadUrl: dlUrl,
      isDefault: json['isDefault'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'apiBaseUrl': apiBaseUrl,
    'portalUrl': portalUrl,
    'downloadPortalUrl': downloadPortalUrl,
    'downloadUrl': downloadUrl,
    'isDefault': isDefault,
  };
}

class TrackyuEnv {
  static const String _defaultProdApi = 'https://oyuapi.in/trackyuapi/api';
  static EnvironmentItem current = const EnvironmentItem(
    key: 'prod',
    name: 'Production',
    apiBaseUrl: _defaultProdApi,
    portalUrl: 'https://trackyuweb.runasp.net',
    downloadPortalUrl: 'https://trackyuweb.runasp.net/download',
    downloadUrl: 'https://trackyuweb.runasp.net/Trackyu_latest.apk',
    isDefault: true,
  );

  static final Map<String, EnvironmentItem> environments = {
    'prod': const EnvironmentItem(
      key: 'prod',
      name: 'Production',
      apiBaseUrl: 'https://oyuapi.in/trackyuapi/api',
      portalUrl: 'https://trackyuweb.runasp.net',
      downloadPortalUrl: 'https://trackyuweb.runasp.net/download',
      downloadUrl: 'https://trackyuweb.runasp.net/Trackyu_latest.apk',
      isDefault: true,
    ),
    'uat': const EnvironmentItem(
      key: 'uat',
      name: 'UAT Testing',
      apiBaseUrl: 'https://uat-trackyu.runasp.net/api',
      portalUrl: 'https://uat-trackyuweb.runasp.net',
      downloadPortalUrl: 'https://uat-trackyuweb.runasp.net/download',
      downloadUrl: 'https://uat-trackyu.runasp.net/apk/Trackyu_latest.apk',
    ),
    'dev': const EnvironmentItem(
      key: 'dev',
      name: 'Development',
      apiBaseUrl: 'https://dev-trackyu.runasp.net/api',
      portalUrl: 'https://dev-trackyuweb.runasp.net',
      downloadPortalUrl: 'https://dev-trackyuweb.runasp.net/download',
      downloadUrl: 'https://dev-trackyu.runasp.net/apk/Trackyu_latest.apk',
    ),
    'local': const EnvironmentItem(
      key: 'local',
      name: 'Localhost / Emulator',
      apiBaseUrl: 'http://10.0.2.2:5000/api',
      portalUrl: 'http://localhost:5173',
      downloadPortalUrl: 'http://localhost:5173/download',
      downloadUrl: 'http://10.0.2.2:5000/apk/Trackyu_latest.apk',
    ),
  };

  static String get apiBaseUrl => current.apiBaseUrl;
  static String get portalUrl => current.portalUrl;
  static String get downloadPortalUrl => current.downloadPortalUrl;
  static String get downloadUrl => current.downloadUrl;
  static String get activeKey => current.key;

  /// Initialize environment from assets/env_config.json, and sync active DB environment
  static Future<void> initialize() async {
    try {
      final configStr = await rootBundle.loadString('assets/env_config.json');
      final data = jsonDecode(configStr);
      if (data is Map<String, dynamic>) {
        if (data['environments'] is Map<String, dynamic>) {
          final envMap = data['environments'] as Map<String, dynamic>;
          for (final entry in envMap.entries) {
            if (entry.value is Map<String, dynamic>) {
              final item = EnvironmentItem.fromJson(Map<String, dynamic>.from(entry.value));
              environments[item.key] = item;
            }
          }
        }
        final activeKey = data['activeEnvironment']?.toString().toLowerCase().trim();
        if (activeKey != null && environments.containsKey(activeKey)) {
          current = environments[activeKey]!;
        }
      }
    } catch (_) {}

    // Synchronize active environment configured by DBA in Admin table
    await _syncFromDatabase().catchError((_) {});
  }

  static Future<void> _syncFromDatabase() async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: current.apiBaseUrl,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ));
      final res = await dio.get('/environments/current');
      if (res.statusCode == 200 && res.data is Map && res.data['environment'] is Map) {
        final item = EnvironmentItem.fromJson(Map<String, dynamic>.from(res.data['environment']));
        current = item;
      }
    } catch (_) {}
  }

  /// Update active environment based on server response (controlled by DBA in dbo.Admin table)
  static void updateActiveEnvironment(String envName, {TrackyuController? controller}) {
    final clean = envName.trim().toLowerCase();
    for (final env in environments.values) {
      if (env.key.toLowerCase() == clean ||
          env.displayName.toLowerCase() == clean ||
          env.displayName.toLowerCase().contains(clean)) {
        current = env;
        if (controller != null) {
          controller.api.baseUrl = env.apiBaseUrl;
        }
        return;
      }
    }
  }

  /// Switch environment and persist selection
  static Future<void> setEnvironment(String key, {TrackyuController? controller}) async {
    final cleanKey = key.trim().toLowerCase();
    if (!environments.containsKey(cleanKey)) return;
    current = environments[cleanKey]!;

    try {
      final prefFile = File('${Directory.systemTemp.path}/trackyu_active_env.txt');
      prefFile.writeAsStringSync(cleanKey);
    } catch (_) {}

    if (controller != null) {
      controller.api.baseUrl = current.apiBaseUrl;
      await controller.refresh();
    }
  }

  /// Show interactive environment picker dialog for switching between Dev, UAT, Prod, Local
  static Future<void> showEnvironmentPicker(
    BuildContext context, {
    TrackyuController? controller,
    VoidCallback? onChanged,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xff161b22) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xff30363d) : const Color(0xffe2e8f0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xff0284c7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.dns_rounded, color: Color(0xff0284c7), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Environment',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xff0f172a),
                        ),
                      ),
                      Text(
                        'Dynamic API & Portal configurations from SQL',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...environments.values.map((env) {
                final isSelected = env.key == current.key;
                Color badgeColor;
                switch (env.key) {
                  case 'prod':
                    badgeColor = const Color(0xff10b981);
                    break;
                  case 'uat':
                    badgeColor = const Color(0xfff59e0b);
                    break;
                  case 'dev':
                    badgeColor = const Color(0xff3b82f6);
                    break;
                  default:
                    badgeColor = const Color(0xff8b5cf6);
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await setEnvironment(env.key, controller: controller);
                      onChanged?.call();
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? badgeColor.withValues(alpha: 0.12)
                            : (isDark ? const Color(0xff1e293b) : const Color(0xfff8fafc)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? badgeColor
                              : (isDark ? const Color(0xff334155) : const Color(0xffe2e8f0)),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              env.key.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  env.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: isDark ? Colors.white : const Color(0xff0f172a),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  env.apiBaseUrl,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded, color: badgeColor, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              Text(
                'Note: Change in assets/env_config.json sets default startup environment.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xff64748b) : const Color(0xff94a3b8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

