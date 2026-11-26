import 'dart:async';
import 'package:flutter/material.dart';
import 'controller.dart';

String hoursLabel(Duration? duration) {
  if (duration == null) return '--:--:--';
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(duration.inHours)}:${pad(duration.inMinutes % 60)}:${pad(duration.inSeconds % 60)}';
}

class WorkingHoursDisplay extends StatefulWidget {
  final TrackyuController controller;
  final bool showSubtitle;
  final bool inRow;
  const WorkingHoursDisplay({
    super.key,
    required this.controller,
    this.showSubtitle = true,
    this.inRow = false,
  });
  @override
  State<WorkingHoursDisplay> createState() => _WorkingHoursDisplayState();
}

class _WorkingHoursDisplayState extends State<WorkingHoursDisplay>
    with WidgetsBindingObserver {
  Timer? timer;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(changed);
    sync();
  }

  void sync() {
    if (foreground &&
        widget.controller.onDuty &&
        widget.controller.stateKnown) {
      timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          widget.controller.checkDayChangeAndCutoff();
          setState(() {});
        }
      });
    } else {
      timer?.cancel();
      timer = null;
    }
  }

  void changed() {
    sync();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync();
  }

  @override
  void didUpdateWidget(WorkingHoursDisplay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(changed);
      widget.controller.addListener(changed);
    }
    sync();
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.controller.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.controller.isDarkMode;
    if (widget.inRow) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: isDark ? const Color(0xff94a3b8) : const Color(0xff0284c7),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'WORKING HOURS',
                      maxLines: 1,
                      style: TextStyle(
                        color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                hoursLabel(widget.controller.workingDuration),
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xff0f172a),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WORKING HOURS',
          style: TextStyle(
            color: isDark ? const Color(0xffbdd8ed) : const Color(0xff64748b),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            hoursLabel(widget.controller.workingDuration),
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xff0f172a),
              fontSize: 30,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (widget.showSubtitle) ...[
          const SizedBox(height: 2),
          Text(
            !widget.controller.stateKnown
                ? 'Waiting for attendance'
                : widget.controller.completed
                ? 'Final duration'
                : widget.controller.onDuty
                ? 'Live since punch-in'
                : 'Starts after punch-in',
            style: const TextStyle(fontSize: 11, color: Color(0xffa7efda)),
          ),
        ],
      ],
    );
  }
}
