import 'package:flutter/material.dart';
import 'api.dart';
import 'controller.dart';
import 'workspace.dart';

class RegularizationPage extends StatefulWidget {
  final TrackyuController controller;
  const RegularizationPage({super.key, required this.controller});

  @override
  State<RegularizationPage> createState() => _RegularizationPageState();
}

class _RegularizationPageState extends State<RegularizationPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool get _isPrivileged => widget.controller.menuEnabled('manager_team_map');

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _teamStatus = 'Pending';
  List<Json> _mine = const [];
  List<Json> _team = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _isPrivileged ? 2 : 1, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mineRes = await widget.controller.api.request('AttendanceRegularization/mine');
      final mineList = jsonRows(mineRes);
      List<Json> teamList = const [];
      if (_isPrivileged) {
        final teamRes = await widget.controller.api.request(
          'AttendanceRegularization/team?status=${Uri.encodeQueryComponent(_teamStatus)}',
        );
        teamList = jsonRows(teamRes);
      }
      if (!mounted) return;
      setState(() {
        _mine = mineList;
        _team = teamList;
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

  String _fmtTime(dynamic iso) {
    final dt = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (dt == null) return '—';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Color _statusColor(String st) {
    switch (st.toLowerCase()) {
      case 'approved':
        return const Color(0xff059669);
      case 'rejected':
        return const Color(0xffdc2626);
      case 'cancelled':
        return Colors.grey;
      default:
        return const Color(0xffd97706);
    }
  }

  Future<void> _openApplyDialog() async {
    DateTime pickedDate = DateTime.now();
    String mode = 'Field';
    String reqType = 'MissedPunchOut';
    TimeOfDay inTime = const TimeOfDay(hour: 9, minute: 30);
    TimeOfDay outTime = const TimeOfDay(hour: 18, minute: 30);
    final reasonCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final needIn = reqType == 'MissedPunchIn' || reqType == 'TimeCorrection' || reqType == 'MissedFullDay';
          final needOut = reqType == 'MissedPunchOut' || reqType == 'TimeCorrection' || reqType == 'MissedFullDay';
          final dateStr = '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
          return AlertDialog(
            title: const Text('Apply Regularization'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Work Date'),
                    subtitle: Text(dateStr),
                    trailing: const Icon(Icons.calendar_today_rounded, size: 18),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: pickedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 60)),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setD(() => pickedDate = d);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: 'Mode', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'Field', child: Text('Field')),
                      DropdownMenuItem(value: 'Office', child: Text('Office')),
                    ],
                    onChanged: (v) => setD(() => mode = v ?? 'Field'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: reqType,
                    decoration: const InputDecoration(labelText: 'Request Type', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'MissedPunchOut', child: Text('Missed Punch Out')),
                      DropdownMenuItem(value: 'MissedPunchIn', child: Text('Missed Punch In')),
                      DropdownMenuItem(value: 'TimeCorrection', child: Text('Time Correction')),
                      DropdownMenuItem(value: 'MissedFullDay', child: Text('Missed Full Day')),
                    ],
                    onChanged: (v) => setD(() => reqType = v ?? 'MissedPunchOut'),
                  ),
                  if (needIn)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Punch-In Time'),
                      subtitle: Text(inTime.format(ctx)),
                      trailing: const Icon(Icons.access_time_rounded, size: 18),
                      onTap: () async {
                        final t = await showTimePicker(context: ctx, initialTime: inTime);
                        if (t != null) setD(() => inTime = t);
                      },
                    ),
                  if (needOut)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Punch-Out Time'),
                      subtitle: Text(outTime.format(ctx)),
                      trailing: const Icon(Icons.access_time_rounded, size: 18),
                      onTap: () async {
                        final t = await showTimePicker(context: ctx, initialTime: outTime);
                        if (t != null) setD(() => outTime = t);
                      },
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
            ],
          );
        },
      ),
    );

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true || reason.length < 3) return;

    setState(() => _busy = true);
    try {
      final dateStr = '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
      final needIn = reqType == 'MissedPunchIn' || reqType == 'TimeCorrection' || reqType == 'MissedFullDay';
      final needOut = reqType == 'MissedPunchOut' || reqType == 'TimeCorrection' || reqType == 'MissedFullDay';
      String? toIso(TimeOfDay t) => DateTime(pickedDate.year, pickedDate.month, pickedDate.day, t.hour, t.minute).toUtc().toIso8601String();
      await widget.controller.api.request(
        'AttendanceRegularization/apply',
        body: {
          'workDate': dateStr,
          'attendanceMode': mode,
          'requestType': reqType,
          'requestedPunchInUtc': needIn ? toIso(inTime) : null,
          'requestedPunchOutUtc': needOut ? toIso(outTime) : null,
          'reason': reason,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Regularization request submitted.'), backgroundColor: Color(0xff059669)),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(Json item, String decision) async {
    final noteCtrl = TextEditingController();
    final isApprove = decision == 'Approved';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$decision Regularization?'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: isApprove ? 'Note (optional)' : 'Rejection Reason (required)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(decision)),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true) return;
    if (!isApprove && note.isEmpty) return;

    setState(() => _busy = true);
    try {
      await widget.controller.api.request(
        'AttendanceRegularization/review',
        body: {
          'id': item['id'],
          'decision': decision,
          'reviewNote': note.isEmpty ? null : note,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request ${decision.toLowerCase()}.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Json item) async {
    setState(() => _busy = true);
    try {
      await widget.controller.api.request('AttendanceRegularization/cancel', body: {'id': item['id']});
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildList(List<Json> rows, {required bool isTeam}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (rows.isEmpty) return const Center(child: Text('No regularization requests found.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final r = rows[i];
          final st = '${r['status'] ?? 'Pending'}';
          final color = _statusColor(st);
          final isPending = st.toLowerCase() == 'pending';
          return Card(
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
                          isTeam
                              ? '${r['employeeName'] ?? r['userId']} (${r['userId']})'
                              : '${r['workDate']} • ${r['requestType']}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(st.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
                      ),
                    ],
                  ),
                  if (isTeam) ...[
                    const SizedBox(height: 4),
                    Text('${r['workDate']} • ${r['requestType']} (${r['attendanceMode']})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                  const SizedBox(height: 6),
                  Text('In: ${_fmtTime(r['requestedPunchInUtc'])}  |  Out: ${_fmtTime(r['requestedPunchOutUtc'])}', style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Text('${r['reason'] ?? ''}', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                  if ('${r['reviewNote'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Note: ${r['reviewNote']}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                  if (isPending) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isTeam)
                          OutlinedButton(onPressed: _busy ? null : () => _cancel(r), child: const Text('Cancel'))
                        else ...[
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xffdc2626)),
                            onPressed: _busy ? null : () => _review(r, 'Rejected'),
                            child: const Text('Reject'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff059669), foregroundColor: Colors.white),
                            onPressed: _busy ? null : () => _review(r, 'Approved'),
                            child: const Text('Approve'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Regularization'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load),
        ],
        bottom: _isPrivileged
            ? TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'My Requests'),
                  Tab(text: 'Team Approvals'),
                ],
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _openApplyDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Apply'),
      ),
      body: _isPrivileged
          ? TabBarView(
              controller: _tabs,
              children: [
                _buildList(_mine, isTeam: false),
                Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: Row(
                        children: [
                          for (final st in const ['Pending', 'Approved', 'Rejected', 'ALL']) ...[
                            ChoiceChip(
                              label: Text(st == 'ALL' ? 'All' : st),
                              selected: _teamStatus == st,
                              onSelected: (_) {
                                setState(() => _teamStatus = st);
                                _load();
                              },
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    Expanded(child: _buildList(_team, isTeam: true)),
                  ],
                ),
              ],
            )
          : _buildList(_mine, isTeam: false),
    );
  }
}
