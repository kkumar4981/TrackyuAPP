import 'package:flutter/material.dart';
import 'api.dart';
import 'controller.dart';
import 'workspace.dart';

class LeaveBalancePage extends StatefulWidget {
  final TrackyuController controller;
  const LeaveBalancePage({super.key, required this.controller});

  @override
  State<LeaveBalancePage> createState() => _LeaveBalancePageState();
}

class _LeaveBalancePageState extends State<LeaveBalancePage> {
  bool get _isPrivileged => widget.controller.menuEnabled('manager_team_map');
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _year = DateTime.now().year;
  List<Json> _balances = const [];
  List<Json> _compOffs = const [];
  List<Json> _teamCompOffs = const [];

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
      final res = await widget.controller.api.request('LeaveBalance/mine?year=$_year');
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final balances = jsonRows(map['balances'] ?? map['Balances'] ?? const []);
      final compOffs = jsonRows(map['compOffRequests'] ?? map['CompOffRequests'] ?? const []);
      List<Json> team = const [];
      if (_isPrivileged) {
        final tRes = await widget.controller.api.request('LeaveBalance/team?status=Pending');
        team = jsonRows(tRes);
      }
      if (!mounted) return;
      setState(() {
        _year = (map['year'] ?? map['Year'] ?? _year) as int;
        _balances = balances;
        _compOffs = compOffs;
        _teamCompOffs = team;
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

  Future<void> _applyCompOff() async {
    DateTime picked = DateTime.now();
    double days = 1.0;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          return AlertDialog(
            title: const Text('Claim Comp-Off'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Worked Date (Sunday / Holiday)'),
                  subtitle: Text(dateStr),
                  trailing: const Icon(Icons.calendar_today_rounded, size: 18),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: picked,
                      firstDate: DateTime.now().subtract(const Duration(days: 60)),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setD(() => picked = d);
                  },
                ),
                DropdownButtonFormField<double>(
                  initialValue: days,
                  decoration: const InputDecoration(labelText: 'Days', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 1.0, child: Text('1.0 Day (Full Day)')),
                    DropdownMenuItem(value: 0.5, child: Text('0.5 Day (Half Day)')),
                  ],
                  onChanged: (v) => setD(() => days = v ?? 1.0),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
                ),
              ],
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
      final dateStr = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      await widget.controller.api.request(
        'LeaveBalance/comp-off/apply',
        body: {'workedDate': dateStr, 'days': days, 'reason': reason},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comp-off request submitted.'), backgroundColor: Color(0xff059669)),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewCompOff(Json item, String decision) async {
    final noteCtrl = TextEditingController();
    final isApprove = decision == 'Approved';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$decision Comp-Off?'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: isApprove ? 'Note (optional)' : 'Rejection Reason',
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
        'LeaveBalance/comp-off/review',
        body: {'id': item['id'], 'decision': decision, 'reviewNote': note.isEmpty ? null : note},
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Leave Balance ($_year)'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _applyCompOff,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Claim Comp-Off'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _balances.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.55,
                        ),
                        itemBuilder: (_, i) {
                          final b = _balances[i];
                          return Card(
                            elevation: 1.5,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${b['leaveType'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xff0284c7))),
                                  Text('${b['available'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
                                  Text('Alloc: ${b['allocated'] ?? 0}  •  Used: ${b['used'] ?? 0}', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      if (_isPrivileged && _teamCompOffs.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text('Pending Team Comp-Off Approvals', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 8),
                        for (final c in _teamCompOffs)
                          Card(
                            child: ListTile(
                              title: Text('${c['employeeName'] ?? c['userId']} • ${c['days']}d (${c['workedDate']})'),
                              subtitle: Text('${c['reason'] ?? ''}'),
                              trailing: Wrap(
                                spacing: 6,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, color: Colors.red),
                                    onPressed: _busy ? null : () => _reviewCompOff(c, 'Rejected'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.check_rounded, color: Colors.green),
                                    onPressed: _busy ? null : () => _reviewCompOff(c, 'Approved'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 18),
                      const Text('My Comp-Off Requests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      if (_compOffs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('No comp-off claims submitted yet.', style: TextStyle(color: Colors.black54)),
                        )
                      else
                        for (final c in _compOffs)
                          Card(
                            child: ListTile(
                              title: Text('${c['workedDate']} • ${c['days']} day(s)'),
                              subtitle: Text('${c['reason'] ?? ''}'),
                              trailing: Text('${c['status'] ?? 'Pending'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                      const SizedBox(height: 70),
                    ],
                  ),
                ),
    );
  }
}
