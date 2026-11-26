visits_page_code = '''class _VisitsPageState extends State<VisitsPage> {
  late final VisitsData data;
  Timer? _ticker;
  bool _isOpening = false;
  int _selectedTab = 0; // 0 = Ongoing, 1 = Completed
  DateTime _selectedDate = DateTime.now();

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

  Future<void> edit(Json? visit) async {
    if (_isOpening) return;
    final bool hasActive = data.active != null ||
        widget.controller.activeVisit != null ||
        widget.controller.pendingVisits.any((p) => p['finish'] != true);
    if (visit == null && hasActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have an active visit in progress. Please check out from your ongoing visit before starting a new one.'),
          backgroundColor: Color(0xffea580c),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
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
          builder: (_) => VisitForm(data: data, visit: visit),
        ),
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              visit == null
                  ? 'Visit punch-in confirmed.'
                  : 'Visit punch-out confirmed.',
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

  Widget _buildSelfieOutlinedButton({
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onTap: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xff0284c7),
        side: BorderSide(
          color: isDark ? const Color(0xff0284c7).withValues(alpha: 0.5) : const Color(0xff0284c7),
          width: 1.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      icon: const Icon(Icons.camera_alt_outlined, size: 17),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.controller.isDarkMode;
    final cardBg = isDark ? const Color(0xff1e2023) : Colors.white;
    final borderColor = isDark ? const Color(0xff2d3135) : const Color(0xffe2e8f0);
    final textPrimary = isDark ? Colors.white : const Color(0xff0f172a);
    final textSecondary = isDark ? const Color(0xff94a3b8) : const Color(0xff64748b);

    final ongoingVisits = data.rows.where((r) => r['checkOutUtc'] == null).toList();
    if (data.active != null && !ongoingVisits.any((r) => r['id'] == data.active!['id'] || r['localId'] == data.active!['localId'])) {
      ongoingVisits.insert(0, data.active!);
    }

    final completedVisits = data.rows.where((r) => r['checkOutUtc'] != null).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Open visits', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
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
          IconButton(
            tooltip: isDark ? 'Light mode' : 'Dark mode',
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            onPressed: () => widget.controller.toggleDarkMode(),
          ),
          IconButton(
            tooltip: 'Reload visits',
            onPressed: data.loading || data.saving ? null : data.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        children: [
          // 1. Date Selector and Visit Count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                '${data.rows.length} ${data.rows.length == 1 ? 'visit' : 'visits'} recorded',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

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
            if (ongoingVisits.isEmpty && !data.loading) ...[
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
                      'Start a new client visit to track time and punch out.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isOpening ? null : () => edit(null),
                      icon: const Icon(Icons.add_business_rounded, color: Colors.white, size: 19),
                      label: const Text(
                        'Start Open Visit',
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

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
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
                            backgroundColor: const Color(0xff2563eb),
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
                          label: const Text(
                            'Punch Out',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
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
                                    onTap: () => _openSelfie(row, out: true),
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
'''

with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\visits.dart', 'r', encoding='utf-8') as f:
    full_text = f.read()

# Replace from class _VisitsPageState to class VisitDuration
idx_start = full_text.find('class _VisitsPageState extends State<VisitsPage> {')
idx_end = full_text.find('class VisitDuration extends StatelessWidget {')

if idx_start != -1 and idx_end != -1:
    new_full = full_text[:idx_start] + visits_page_code + '\n\n' + full_text[idx_end:]
    with open(r'C:\Development\Oyu\fieldforce_hrms\lib\trackyu\visits.dart', 'w', encoding='utf-8') as f:
        f.write(new_full)
    print("visits.dart successfully updated!")
else:
    print(f"Indices: {idx_start}, {idx_end}")
