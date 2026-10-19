import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized brand emblem and wordmark matching the Stitch Design System.
///
/// Features two canonical Stitch representations:
/// 1. [MieeBrandMark.emblem] — Burgundy square emblem with rounded corners,
///    featuring the white graphic soundwave icon, followed by the "miee" wordmark
///    and crimson accent dot.
/// 2. [MieeBrandMark.soundwaveWordmark] — Desktop header variant with 4 standalone
///    burgundy vertical soundwave bars and "miee." text.
class MieeBrandMark extends StatelessWidget {
  final bool isDesktopSoundwave;
  final double emblemSize;
  final double fontSize;
  final bool showWordmark;
  final Color emblemColor;
  final Color dotColor;
  final Color textColor;

  const MieeBrandMark({
    super.key,
    this.isDesktopSoundwave = false,
    this.emblemSize = 52,
    this.fontSize = 24,
    this.showWordmark = true,
    this.emblemColor = const Color(0xFF6E0D25),
    this.dotColor = const Color(0xFFBA0032),
    this.textColor = const Color(0xFF1A0F12),
  });

  const MieeBrandMark.emblem({
    super.key,
    this.emblemSize = 52,
    this.fontSize = 24,
    this.showWordmark = true,
    this.emblemColor = const Color(0xFF6E0D25),
    this.dotColor = const Color(0xFFBA0032),
    this.textColor = const Color(0xFF1A0F12),
  }) : isDesktopSoundwave = false;

  const MieeBrandMark.soundwaveWordmark({
    super.key,
    this.fontSize = 24,
    this.emblemColor = const Color(0xFF6E0D25),
    this.dotColor = const Color(0xFFBA0032),
    this.textColor = const Color(0xFF1A0F12),
  })  : isDesktopSoundwave = true,
        emblemSize = 24,
        showWordmark = true;

  @override
  Widget build(BuildContext context) {
    if (isDesktopSoundwave) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 4 Vertical Burgundy Soundwave bars
          SizedBox(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildBar(height: 14, color: emblemColor),
                const SizedBox(width: 2.5),
                _buildBar(height: 24, color: emblemColor),
                const SizedBox(width: 2.5),
                _buildBar(height: 18, color: emblemColor),
                const SizedBox(width: 2.5),
                _buildBar(height: 8, color: emblemColor),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.plusJakartaSans(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: textColor,
              ),
              children: [
                const TextSpan(text: 'miee'),
                TextSpan(
                  text: '.',
                  style: TextStyle(color: dotColor),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Default Emblem Variant
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Burgundy rounded square emblem
        Container(
          width: emblemSize,
          height: emblemSize,
          decoration: BoxDecoration(
            color: emblemColor,
            borderRadius: BorderRadius.circular(emblemSize * 0.31),
            boxShadow: const [
              BoxShadow(
                color: Color(0x141A0F12),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: emblemSize * 0.52,
            ),
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'miee',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 2),
              Container(
                width: fontSize * 0.25,
                height: fontSize * 0.25,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBar({required double height, required Color color}) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
