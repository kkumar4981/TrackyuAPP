import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'controller.dart';

/// Offline-first Profile Avatar Cache and Widget
/// Stores avatar image bytes permanently on disk so it loads in 0ms without hitting the server every time.
class TrackyuAvatarCache {
  static final Map<String, File> _fileCache = {};
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  static Future<Directory> _getAvatarDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/profile_avatars');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File?> getLocalAvatar(String userId) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) return null;
    if (_fileCache.containsKey(cleanId) && await _fileCache[cleanId]!.exists()) {
      return _fileCache[cleanId];
    }
    try {
      final dir = await _getAvatarDir();
      final file = File('${dir.path}/avatar_$cleanId.jpg');
      if (await file.exists() && await file.length() > 200) {
        _fileCache[cleanId] = file;
        return file;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveAvatarBytes(String userId, Uint8List bytes) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty || bytes.isEmpty) return;
    try {
      final dir = await _getAvatarDir();
      final file = File('${dir.path}/avatar_$cleanId.jpg');
      await file.writeAsBytes(bytes, flush: true);
      _fileCache[cleanId] = file;
      changeNotifier.value++;
    } catch (_) {}
  }

  static Future<void> syncFromUrl(String userId, String url) async {
    final cleanId = userId.trim();
    final cleanUrl = url.trim();
    if (cleanId.isEmpty || cleanUrl.isEmpty || !cleanUrl.startsWith('http')) return;

    try {
      final request = await HttpClient().getUrl(Uri.parse(cleanUrl));
      request.headers.set('User-Agent', 'TrackyuMobile/1.0');
      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        if (bytes.length > 200) {
          await saveAvatarBytes(cleanId, bytes);
        }
      }
    } catch (_) {}
  }
}

/// Helper method from flutter foundation for HttpClient response bytes
Future<Uint8List> consolidateHttpClientResponseBytes(HttpClientResponse response) {
  final completer = Completer<Uint8List>.sync();
  final chunks = <List<int>>[];
  int byteCount = 0;
  response.listen(
    (chunk) {
      chunks.add(chunk);
      byteCount += chunk.length;
    },
    onDone: () {
      final bytes = Uint8List(byteCount);
      int offset = 0;
      for (final chunk in chunks) {
        bytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      completer.complete(bytes);
    },
    onError: completer.completeError,
    cancelOnError: true,
  );
  return completer.future;
}

/// Offline-first Avatar Widget that prefers local disk cache over repeated network requests.
class TrackyuAvatarWidget extends StatefulWidget {
  final TrackyuController controller;
  final double size;
  final bool isDark;
  final Uint8List? previewBytes;
  final VoidCallback? onTap;

  const TrackyuAvatarWidget({
    super.key,
    required this.controller,
    this.size = 46,
    this.isDark = false,
    this.previewBytes,
    this.onTap,
  });

  @override
  State<TrackyuAvatarWidget> createState() => _TrackyuAvatarWidgetState();
}

class _TrackyuAvatarWidgetState extends State<TrackyuAvatarWidget> {
  File? _localFile;

  @override
  void initState() {
    super.initState();
    _checkDisk();
    TrackyuAvatarCache.changeNotifier.addListener(_onCacheChanged);
  }

  @override
  void dispose() {
    TrackyuAvatarCache.changeNotifier.removeListener(_onCacheChanged);
    super.dispose();
  }

  void _onCacheChanged() {
    if (mounted) _checkDisk();
  }

  Future<void> _checkDisk() async {
    final file = await TrackyuAvatarCache.getLocalAvatar(widget.controller.employeeId);
    if (mounted) {
      setState(() {
        _localFile = file;
      });
      // If local file is missing but a remote photoUrl is available, download in background to cache
      if (file == null && widget.controller.photoUrl.isNotEmpty) {
        unawaited(TrackyuAvatarCache.syncFromUrl(
          widget.controller.employeeId,
          widget.controller.photoUrl,
        ));
      }
    }
  }

  @override
  void didUpdateWidget(TrackyuAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.photoUrl != widget.controller.photoUrl ||
        oldWidget.controller.employeeId != widget.controller.employeeId) {
      _checkDisk();
    }
  }

  String _getInitials(String rawName) {
    final parts = rawName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Widget _buildFallbackIcon() {
    final isDark = widget.isDark;
    final initials = _getInitials(widget.controller.name);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xff0369a1), Color(0xff4338ca)]
              : const [Color(0xff0284c7), Color(0xff6366f1)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.size * 0.38,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.controller.photoUrl;

    Widget imageWidget;
    if (widget.previewBytes != null && widget.previewBytes!.isNotEmpty) {
      imageWidget = Image.memory(
        widget.previewBytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
      );
    } else if (_localFile != null) {
      // 1. Instant 0ms local disk cache
      imageWidget = Image.file(
        _localFile!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
      );
    } else if (photoUrl.isNotEmpty) {
      // 2. Network fallback with immediate local caching
      imageWidget = Image.network(
        photoUrl,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _buildFallbackIcon();
        },
      );
    } else {
      // 3. Fallback silhouette
      imageWidget = _buildFallbackIcon();
    }

    final content = ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: imageWidget,
      ),
    );

    if (widget.onTap != null) {
      return InkWell(
        onTap: widget.onTap,
        customBorder: const CircleBorder(),
        child: content,
      );
    }
    return content;
  }
}
