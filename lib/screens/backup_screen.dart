import 'package:flutter/material.dart';

/// Sicherungen (Time Machine) tab — placeholder screen for cloud backups
/// and system restore functionality.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  // ── Dark palette ──────────────────────────────────────────────────────
  static const Color _background = Color(0xFF1E1E24);
  static const Color _card = Color(0xFF2A2A32);
  static const Color _accent = Color(0xFF00BFA5);
  static const Color _accentDim = Color(0x3300BFA5); // 20 % opacity
  static const Color _textPrimary = Color(0xFFEEEEEE);
  static const Color _textSecondary = Color(0xFF9E9EA8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          // ── Decorative gradient orbs ─────────────────────────────────
          _buildOrb(
            top: -60,
            right: -40,
            size: 220,
            colors: [_accent.withValues(alpha: 0.22), Colors.transparent],
          ),
          _buildOrb(
            bottom: -80,
            left: -50,
            size: 260,
            colors: [
              const Color(0xFF6C63FF).withValues(alpha: 0.15),
              Colors.transparent,
            ],
          ),
          _buildOrb(
            top: MediaQuery.of(context).size.height * 0.35,
            left: MediaQuery.of(context).size.width * 0.6,
            size: 140,
            colors: [_accent.withValues(alpha: 0.10), Colors.transparent],
          ),

          // ── Main content ────────────────────────────────────────────
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
                    // ── Icon illustration area ────────────────────────
                    _buildIllustration(),
                    const SizedBox(height: 36),

                    // ── Title ─────────────────────────────────────────
                    const Text(
                      'Sicherungen',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Subtitle ──────────────────────────────────────
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Erstelle Cloud-Backups deiner Reglereinstellungen '
                        'und stelle vorherige Konfigurationen wieder her.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: 15,
                          height: 1.55,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── "Demnächst verfügbar" chip ────────────────────
                    _buildComingSoonChip(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Illustration: layered circle + icon ──────────────────────────────
  Widget _buildIllustration() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [_accentDim, _card.withValues(alpha: 0.6)],
          radius: 0.85,
        ),
        border: Border.all(color: _accent.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.12),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_accent, Color(0xFF6C63FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: const Icon(
            Icons.cloud_done_outlined,
            size: 64,
            color: Colors.white, // masked by shader
          ),
        ),
      ),
    );
  }

  // ── "Demnächst verfügbar" badge ──────────────────────────────────────
  Widget _buildComingSoonChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, color: _accent, size: 18),
          const SizedBox(width: 8),
          Text(
            'Demnächst verfügbar',
            style: TextStyle(
              color: _accent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Decorative blurred gradient orb ──────────────────────────────────
  Widget _buildOrb({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required List<Color> colors,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: colors),
          ),
        ),
      ),
    );
  }
}
