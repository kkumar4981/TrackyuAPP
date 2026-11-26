import 'dart:math' as math;
import 'package:flutter/material.dart';

class GpsRadarLoader extends StatefulWidget {
  final String label;
  final String? sublabel;
  final double size;
  final Color primaryColor;
  final Color accentColor;

  const GpsRadarLoader({
    super.key,
    this.label = 'Acquiring GPS Telemetry...',
    this.sublabel = 'Connecting to high-precision satellites',
    this.size = 110.0,
    this.primaryColor = const Color(0xff0284c7),
    this.accentColor = const Color(0xff10b981),
  });

  @override
  State<GpsRadarLoader> createState() => _GpsRadarLoaderState();
}

class _GpsRadarLoaderState extends State<GpsRadarLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Animated Radar Custom Paint
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: _RadarPainter(
                      progress: _controller.value,
                      primaryColor: widget.primaryColor,
                      accentColor: widget.accentColor,
                    ),
                  );
                },
              ),

              // Center GPS Beacon Icon
              Container(
                width: widget.size * 0.32,
                height: widget.size * 0.32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.primaryColor,
                      widget.primaryColor.withValues(alpha: 0.8),
                    ],
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: widget.primaryColor.withValues(alpha: 0.6),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: widget.size * 0.20,
                ),
              ),
            ],
          ),
        ),

      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color accentColor;

  _RadarPainter({
    required this.progress,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background dark disk
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xff0f172a),
          Color(0xff020617),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);

    // Border ring
    final borderPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius - 1, borderPaint);

    // Concentric grid rings
    final gridPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius * 0.35, gridPaint);
    canvas.drawCircle(center, radius * 0.65, gridPaint);
    canvas.drawCircle(center, radius * 0.90, gridPaint);

    // Crosshairs
    final crosshairPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.20)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy), crosshairPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius), crosshairPaint);

    // Expanding ripple waves
    final wave1Radius = radius * ((progress * 1.4) % 1.0);
    final wave1Opacity = (1.0 - (wave1Radius / radius)).clamp(0.0, 0.8);
    final wave1Paint = Paint()
      ..color = primaryColor.withValues(alpha: wave1Opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, wave1Radius, wave1Paint);

    final wave2Progress = (progress + 0.5) % 1.0;
    final wave2Radius = radius * ((wave2Progress * 1.4) % 1.0);
    final wave2Opacity = (1.0 - (wave2Radius / radius)).clamp(0.0, 0.6);
    final wave2Paint = Paint()
      ..color = accentColor.withValues(alpha: wave2Opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, wave2Radius, wave2Paint);

    // Rotating Radar Sweep Cone
    final angle = progress * 2 * math.pi;
    final sweepGradient = SweepGradient(
      startAngle: 0.0,
      endAngle: math.pi / 2.5,
      colors: [
        primaryColor.withValues(alpha: 0.45),
        primaryColor.withValues(alpha: 0.12),
        Colors.transparent,
      ],
      transform: GradientRotation(angle),
    );

    final sweepPaint = Paint()
      ..shader = sweepGradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, sweepPaint);

    // Blinking target satellite blips
    final blip1Angle = 0.8 * math.pi;
    final blip1Dist = radius * 0.68;
    final blip1Pos = Offset(
      center.dx + blip1Dist * math.cos(blip1Angle),
      center.dy + blip1Dist * math.sin(blip1Angle),
    );
    final blip1Opacity = (math.sin((progress * 2 * math.pi) + 1.0).abs()).clamp(0.2, 1.0);
    final blip1Paint = Paint()
      ..color = accentColor.withValues(alpha: blip1Opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(blip1Pos, 3.5, blip1Paint);

    final blip2Angle = 1.6 * math.pi;
    final blip2Dist = radius * 0.52;
    final blip2Pos = Offset(
      center.dx + blip2Dist * math.cos(blip2Angle),
      center.dy + blip2Dist * math.sin(blip2Angle),
    );
    final blip2Opacity = (math.sin((progress * 2 * math.pi) + 3.0).abs()).clamp(0.15, 0.95);
    final blip2Paint = Paint()
      ..color = const Color(0xfff59e0b).withValues(alpha: blip2Opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(blip2Pos, 3.0, blip2Paint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
