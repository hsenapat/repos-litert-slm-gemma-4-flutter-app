import 'dart:math';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final AnimationController _textCtrl;
  late final AnimationController _waveCtrl;
  late final AnimationController _pulseCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _taglineOpacity;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _pulseCtrl = AnimationController( // ignore: unused_field
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _logoScale = CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut)
        .drive(Tween(begin: 0.0, end: 1.0));
    _logoOpacity = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn)
        .drive(Tween(begin: 0.0, end: 1.0));

    _textOpacity = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn)
        .drive(Tween(begin: 0.0, end: 1.0));
    _textSlide = CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut)
        .drive(Tween(begin: const Offset(0, 0.4), end: Offset.zero));
    _taglineOpacity = CurvedAnimation(
      parent: _textCtrl,
      curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
    ).drive(Tween(begin: 0.0, end: 1.0));

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _logoCtrl.forward();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _textCtrl.forward();
    await Future<void>.delayed(const Duration(milliseconds: 3000));
    if (mounted) widget.onComplete();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _waveCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A1628),
              Color(0xFF0D2B4E),
              Color(0xFF0A3D6B),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Animated wave background
            AnimatedBuilder(
              animation: _waveCtrl,
              builder: (_, child) => CustomPaint(
                painter: _WavePainter(_waveCtrl.value),
                size: Size.infinite,
              ),
            ),

            // Floating particles
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, child) => CustomPaint(
                painter: _ParticlePainter(_pulseCtrl.value),
                size: Size.infinite,
              ),
            ),

            // Main content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  AnimatedBuilder(
                    animation: _logoCtrl,
                    builder: (_, child) => Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: child,
                      ),
                    ),
                    child: AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) => Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Color(0xFF1565C0), Color(0xFF0A3D6B)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF42A5F5).withValues(
                                alpha: 0.3 + _pulseCtrl.value * 0.3,
                              ),
                              blurRadius: 40 + _pulseCtrl.value * 25,
                              spreadRadius: 6 + _pulseCtrl.value * 8,
                            ),
                          ],
                          border: Border.all(
                            color: const Color(0xFF42A5F5).withValues(alpha: 0.6),
                            width: 2.5,
                          ),
                        ),
                        child: child,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // App name + tagline
                  AnimatedBuilder(
                    animation: _textCtrl,
                    builder: (_, child) => FadeTransition(
                      opacity: _textOpacity,
                      child: SlideTransition(
                        position: _textSlide,
                        child: child,
                      ),
                    ),
                    child: Column(
                      children: [
                        // App name with gradient shimmer
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFF90CAF9),
                              Color(0xFFFFFFFF),
                              Color(0xFF90CAF9),
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            'Synergy RAG',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const Text(
                          'Offline SLM',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w300,
                            color: Color(0xFF90CAF9),
                            letterSpacing: 3.0,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Divider line
                        Container(
                          width: 60,
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Colors.transparent,
                                Color(0xFF42A5F5),
                                Colors.transparent,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Tagline
                        AnimatedBuilder(
                          animation: _textCtrl,
                          builder: (_, child) => Opacity(
                            opacity: _taglineOpacity.value,
                            child: child,
                          ),
                          child: const Text(
                            'Built for Marine Engineers',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFFB0BEC5),
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom version label
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _textCtrl,
                builder: (_, child) => Opacity(
                  opacity: _textOpacity.value,
                  child: child,
                ),
                child: const Text(
                  'v1.0.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF546E7A),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Animated wave background ──────────────────────────────────────────────────

class _WavePainter extends CustomPainter {
  final double progress;
  _WavePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final phase = progress * 2 * pi + i * pi * 0.66;
      final amplitude = size.height * (0.018 - i * 0.004);
      final yBase = size.height * (0.72 + i * 0.06);
      final opacity = 0.12 - i * 0.03;

      final paint = Paint()
        ..color = const Color(0xFF42A5F5).withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      final path = Path()..moveTo(0, yBase);
      for (var x = 0.0; x <= size.width; x += 2) {
        final y = yBase + sin(x / size.width * 2 * pi * 2 + phase) * amplitude;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress;
}

// ── Floating particles ────────────────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final double progress;
  _ParticlePainter(this.progress);

  static const _particles = [
    (0.15, 0.25, 2.0), (0.82, 0.18, 1.5), (0.45, 0.12, 2.5),
    (0.68, 0.42, 1.8), (0.25, 0.60, 1.2), (0.88, 0.65, 2.2),
    (0.10, 0.80, 1.6), (0.55, 0.78, 1.4), (0.72, 0.88, 2.0),
    (0.35, 0.35, 1.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final (rx, ry, r) in _particles) {
      final flicker = (sin(progress * pi * 2 + rx * 10) + 1) / 2;
      paint.color = const Color(0xFF42A5F5).withValues(alpha: 0.1 + flicker * 0.2);
      canvas.drawCircle(
        Offset(size.width * rx, size.height * ry),
        r + flicker * 1.5,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
