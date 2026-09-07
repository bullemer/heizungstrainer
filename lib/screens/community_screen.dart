import 'package:flutter/material.dart';

/// Community comparison placeholder screen.
///
/// Shows an elegant "coming soon" placeholder with decorative gradient orbs,
/// a large icon, title, subtitle, and a styled chip.
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  // ── palette ──────────────────────────────────────────────────────────
  static const Color _background = Color(0xFF1E1E24);
  static const Color _card = Color(0xFF2A2A32);
  static const Color _accent = Color(0xFF7C4DFF);
  static const Color _accentLight = Color(0xFFB388FF);
  static const Color _textPrimary = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFFB0B0BC);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          // ── decorative gradient orbs ────────────────────────────────
          _GradientOrb(
            color: _accent.withValues(alpha: 0.18),
            diameter: 280,
            top: -60,
            right: -80,
          ),
          _GradientOrb(
            color: _accentLight.withValues(alpha: 0.10),
            diameter: 220,
            bottom: 40,
            left: -70,
          ),
          _GradientOrb(
            color: _accent.withValues(alpha: 0.08),
            diameter: 160,
            bottom: 180,
            right: 30,
          ),

          // ── main content ───────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 48,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // icon area
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _accent.withValues(alpha: 0.25),
                            _accentLight.withValues(alpha: 0.10),
                          ],
                        ),
                        border: Border.all(
                          color: _accent.withValues(alpha: 0.30),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.bar_chart_rounded,
                        size: 52,
                        color: _accentLight,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // title
                    const Text(
                      'Community Vergleich',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        letterSpacing: 0.4,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // subtitle
                    const Text(
                      'Vergleiche die Effizienz deiner Heizung\n'
                      'mit 23 anderen Häusern in deiner Nachbarschaft.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: _textSecondary,
                      ),
                    ),

                    const SizedBox(height: 28),

                    // "coming soon" chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _accent.withValues(alpha: 0.40),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: _accentLight,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Demnächst verfügbar',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _accentLight,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),

                    // decorative mini-cards row (visual flair)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (i) {
                        final heights = [48.0, 68.0, 38.0];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Container(
                            width: 56,
                            height: heights[i],
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 28,
                                height: heights[i] * 0.55,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      _accent.withValues(alpha: 0.50),
                                      _accentLight.withValues(alpha: 0.20),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── helper: decorative blurred gradient orb ─────────────────────────────
class _GradientOrb extends StatelessWidget {
  const _GradientOrb({
    required this.color,
    required this.diameter,
    this.top,
    this.right,
    this.bottom,
    this.left,
  });

  final Color color;
  final double diameter;
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
