import 'dart:math' as math;
import 'package:flutter/material.dart';

class WorkdayArt extends StatelessWidget {
  final bool dark;
  final IconData icon;
  const WorkdayArt({
    super.key,
    this.dark = false,
    this.icon = Icons.location_on_rounded,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 128,
    height: 128,
    child: CustomPaint(
      painter: _OrbitPainter(dark),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: dark ? Colors.white.withValues(alpha: .12) : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xff1c6799).withValues(alpha: .12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 32,
            color: dark ? const Color(0xffa7efda) : const Color(0xff1c6799),
          ),
        ),
      ),
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  final bool dark;
  const _OrbitPainter(this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (dark ? Colors.white : const Color(0xff1c6799)).withValues(
        alpha: dark ? .15 : .12,
      );
    canvas.drawCircle(center, 47, stroke);
    canvas.drawCircle(center, 62, stroke);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = dark ? const Color(0xff80d9bd) : const Color(0xff4e9fc5);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 47),
      -math.pi / 2,
      math.pi * .65,
      false,
      arc,
    );
    canvas.drawCircle(
      center + const Offset(-48, 13),
      5,
      Paint()..color = const Color(0xffffc879),
    );
    canvas.drawCircle(
      center + const Offset(36, -43),
      4,
      Paint()..color = dark ? const Color(0xff84c5e8) : const Color(0xff84cbb6),
    );
    canvas.drawCircle(
      center + const Offset(32, 50),
      3,
      Paint()..color = dark ? Colors.white54 : const Color(0xff86aecb),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.dark != dark;
}

class LoginMasthead extends StatelessWidget {
  const LoginMasthead({super.key});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff1e293b) : const Color(0xff102c4a),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: isDark ? const Color(0xff334155) : const Color(0xffe4ebf2),
                ),
              ),
              child: Image.asset('assets/legacy/logo.png', width: 29, height: 27),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trackyu',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: isDark ? Colors.white : const Color(0xff102c4a),
                    ),
                  ),
                  Text(
                    'YOUR EVERYDAY WORKSPACE',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xff94a3b8) : const Color(0xff8192a7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: isDark
                ? const LinearGradient(
                    colors: [Color(0xff1e293b), Color(0xff0f172a)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xffe3f0f9), Color(0xffe7f5ef)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            border: isDark
                ? Border.all(color: const Color(0xff334155))
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A better start\nto every workday.',
                        style: TextStyle(
                          fontSize: 25,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.9,
                          color: isDark ? Colors.white : const Color(0xff102c4a),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Show up. Stay connected.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: isDark ? const Color(0xff94a3b8) : const Color(0xff5e7a8e),
                        ),
                      ),
                    ],
                  ),
                ),
                if (constraints.maxWidth > 290 &&
                    MediaQuery.textScalerOf(context).scale(14) < 20)
                  WorkdayArt(dark: isDark),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
