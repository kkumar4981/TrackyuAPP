import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'api.dart';
import 'controller.dart';
import 'workspace.dart';

class GeoTagApprovalPage extends StatefulWidget {
  final TrackyuController controller;
  const GeoTagApprovalPage({super.key, required this.controller});

  @override
  State<GeoTagApprovalPage> createState() => _GeoTagApprovalPageState();
}

class _GeoTagApprovalPageState extends State<GeoTagApprovalPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String _statusFilter = 'Pending';
  String _typeFilter = 'ALL';
  String _search = '';
  List<Json> _items = const [];
  Map<String, dynamic> _stats = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final qs = <String>[];
      if (_statusFilter != 'ALL') qs.add('status=${Uri.encodeQueryComponent(_statusFilter)}');
      if (_typeFilter != 'ALL') qs.add('tagType=${Uri.encodeQueryComponent(_typeFilter)}');
      final path = qs.isEmpty ? 'GeoTags' : 'GeoTags?${qs.join('&')}';
      final res = await widget.controller.api.request(path);
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final rawItems = map['items'] ?? map['Items'] ?? const [];
      final myId = widget.controller.employeeId.trim().toLowerCase();
      final list = jsonRows(rawItems)
          .where((r) => '${r['userId'] ?? ''}'.trim().toLowerCase() != myId)
          .toList();
      final stats = map['stats'] is Map
          ? Map<String, dynamic>.from(map['stats'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _items = list;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Json> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((r) {
      final hay = '${r['employeeName'] ?? ''} ${r['userId'] ?? ''} ${r['name'] ?? ''} ${r['address'] ?? ''} ${r['tagType'] ?? ''}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Uint8List? _decodeSelfie(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var s = raw.trim();
    final idx = s.indexOf('base64,');
    if (idx >= 0) s = s.substring(idx + 7);
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> _viewPhoto(Json item) async {
    final id = item['id'];
    if (id == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _SelfiePreviewDialog(
        controller: widget.controller,
        item: item,
        decodeSelfie: _decodeSelfie,
      ),
    );
  }

  Future<void> _review(Json item, String decision) async {
    final id = item['id'];
    if (id == null || _submitting) return;
    final noteCtrl = TextEditingController();
    final isApprove = decision == 'Approved';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isApprove ? 'Approve Geo-Tag?' : 'Reject Geo-Tag?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item['employeeName'] ?? item['userId']} (${item['tagType'] ?? 'TAG'})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${item['name'] ?? ''} • ${item['address'] ?? ''}',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: isApprove ? 'Approval Note (optional)' : 'Rejection Reason',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isApprove ? const Color(0xff059669) : const Color(0xffdc2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isApprove ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      await widget.controller.api.request(
        'GeoTags/review',
        body: {
          'id': id,
          'decision': decision,
          'reviewNote': note.isEmpty ? null : note,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Geo-tag ${decision.toLowerCase()} successfully.'),
          backgroundColor: isApprove ? const Color(0xff059669) : const Color(0xffdc2626),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return const Color(0xff059669);
      case 'rejected':
        return const Color(0xffdc2626);
      default:
        return const Color(0xffd97706);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.controller.isDarkMode;
    final rows = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoTag Approvals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search employee, ID, or location...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final st in const ['Pending', 'Approved', 'Rejected', 'ALL']) ...[
                        ChoiceChip(
                          label: Text(st == 'ALL' ? 'All' : st),
                          selected: _statusFilter == st,
                          onSelected: (_) {
                            if (_statusFilter != st) {
                              setState(() => _statusFilter = st);
                              _load();
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                      const SizedBox(width: 6),
                      for (final tp in const ['ALL', 'HOME', 'GODOWN', 'CUSTOMER']) ...[
                        FilterChip(
                          label: Text(tp == 'ALL' ? 'All Types' : tp),
                          selected: _typeFilter == tp,
                          onSelected: (_) {
                            if (_typeFilter != tp) {
                              setState(() => _typeFilter = tp);
                              _load();
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                if (_stats.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Showing ${rows.length} request(s)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              ElevatedButton(onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : rows.isEmpty
                        ? const Center(child: Text('No geo-tag requests found in your team.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final item = rows[i];
                                final status = '${item['status'] ?? 'Pending'}';
                                final isPending = status.toLowerCase() == 'pending';
                                final hasSelfie = item['hasSelfie'] == true;
                                final color = _statusColor(status);
                                return Card(
                                  elevation: 1.5,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(color: color.withValues(alpha: 0.35)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${item['employeeName'] ?? ''} (${item['userId'] ?? ''})',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: color.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                status.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: color,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${item['tagType'] ?? ''} • ${item['name'] ?? ''}',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                        if ('${item['address'] ?? ''}'.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            '${item['address']}',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: isDark ? Colors.white70 : Colors.black54,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Text(
                                          'GPS: ${item['latitude']}, ${item['longitude']}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: isDark ? Colors.white54 : Colors.black45,
                                          ),
                                        ),
                                        if ('${item['managerName'] ?? ''}'.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Reporting Manager: ${item['managerName']}',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: isDark ? Colors.white54 : Colors.black45,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            if (hasSelfie)
                                              OutlinedButton.icon(
                                                onPressed: () => _viewPhoto(item),
                                                icon: const Icon(Icons.photo_camera_outlined, size: 16),
                                                label: const Text('Photo'),
                                              ),
                                            const Spacer(),
                                            if (isPending) ...[
                                              OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: const Color(0xffdc2626),
                                                  side: const BorderSide(color: Color(0xffdc2626)),
                                                ),
                                                onPressed: _submitting ? null : () => _review(item, 'Rejected'),
                                                child: const Text('Reject'),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xff059669),
                                                  foregroundColor: Colors.white,
                                                ),
                                                onPressed: _submitting ? null : () => _review(item, 'Approved'),
                                                child: const Text('Approve'),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _SelfiePreviewDialog extends StatefulWidget {
  final TrackyuController controller;
  final Json item;
  final Uint8List? Function(String?) decodeSelfie;

  const _SelfiePreviewDialog({
    required this.controller,
    required this.item,
    required this.decodeSelfie,
  });

  @override
  State<_SelfiePreviewDialog> createState() => _SelfiePreviewDialogState();
}

class _SelfiePreviewDialogState extends State<_SelfiePreviewDialog> {
  bool _loading = true;
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await widget.controller.api.request('GeoTags/${widget.item['id']}/selfie');
      final url = res is Map ? res['selfieUrl']?.toString() : null;
      final decoded = widget.decodeSelfie(url);
      if (!mounted) return;
      setState(() {
        _bytes = decoded;
        _error = decoded == null ? 'Photo unavailable' : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.item['employeeName'] ?? ''} • ${widget.item['tagType'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )
            else if (_bytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_bytes!, height: 320, fit: BoxFit.contain),
              )
            else
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error ?? 'No photo'),
              ),
            if ('${widget.item['watermarkText'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${widget.item['watermarkText']}',
                style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
