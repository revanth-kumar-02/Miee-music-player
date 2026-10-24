import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';

/// A quiet, personal dedication page for Miee.
///
/// Designed with generous whitespace, warm ivory paper aesthetics,
/// sage green / soft olive details, restrained terracotta accents,
/// and thoughtful typographic contrast.
class MieeDedicationPage extends StatelessWidget {
  const MieeDedicationPage({super.key});

  static const Color _kCharcoal = Color(0xFF2E2326);
  static const Color _kBodyText = Color(0xFF483A3E);
  static const Color _kMutedText = Color(0xFF7E6F74);
  static const Color _kSageGreen = Color(0xFF7E8F7A);
  static const Color _kSoftOlive = Color(0xFF6E7864);
  static const Color _kTerracotta = Color(0xFFC87565);
  static const Color _kPaperCard = Color(0xFFFAF5EE);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 840;

    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _kCharcoal,
            size: 22,
          ),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 48.0 : 28.0,
                vertical: 20.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12.0),

                  // Subtle static musical detail: 5 delicate staff lines with musical 'M' insignia
                  CustomPaint(
                    size: const Size(88.0, 18.0),
                    painter: _MusicalStaffWatermarkPainter(
                      lineColor: _kSoftOlive.withValues(alpha: 0.28),
                      accentColor: _kTerracotta.withValues(alpha: 0.82),
                    ),
                  ),

                  const SizedBox(height: 32.0),

                  // Opening Heading
                  Text(
                    'Some names are more than names.',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: isDesktop ? 32.0 : 27.0,
                      fontWeight: FontWeight.w700,
                      color: _kCharcoal,
                      height: 1.28,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: 38.0),

                  // Paragraph 1
                  _buildParagraph(
                    'Somewhere between a memory and a feeling, a little name found its way into something bigger.',
                  ),

                  const SizedBox(height: 26.0),

                  // Paragraph 2
                  _buildParagraph(
                    'And that is how Miee came to be.',
                  ),

                  const SizedBox(height: 30.0),

                  // Paragraph 3
                  _buildParagraph(
                    'This little space was created in memory of someone who will always be my favorite — someone whose place in my story doesn\'t need to be explained to the world.',
                  ),

                  const SizedBox(height: 30.0),

                  // Paragraph 4
                  _buildParagraph(
                    'Maybe time changes things. Maybe life takes people in different directions. But some feelings leave behind something beautiful.',
                  ),

                  const SizedBox(height: 26.0),

                  // Paragraph 5
                  _buildParagraph(
                    'For me, that something became Miee.',
                  ),

                  const SizedBox(height: 44.0),

                  // Elegant Callout Box with terracotta hairline & warm ivory paper surface
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22.0,
                      vertical: 22.0,
                    ),
                    decoration: BoxDecoration(
                      color: _kPaperCard,
                      borderRadius: BorderRadius.circular(14.0),
                      border: Border.all(
                        color: AppColors.oatBeige.withValues(alpha: 0.9),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 3.0,
                          height: 48.0,
                          margin: const EdgeInsets.only(right: 16.0, top: 2.0),
                          decoration: BoxDecoration(
                            color: _kTerracotta.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(2.0),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'A little piece of a memory, made to live on in music.',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 18.0,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                              color: _kCharcoal,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 36.0),

                  // Closing Whisper with quiet sage green bullet
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 5.0,
                        height: 5.0,
                        margin: const EdgeInsets.only(right: 10.0),
                        decoration: BoxDecoration(
                          color: _kSageGreen.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Some things are better kept in the heart than explained in words.',
                          style: GoogleFonts.geist(
                            fontSize: 13.5,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w400,
                            color: _kMutedText,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 60.0 + bottomInset),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Text(
      text,
      style: GoogleFonts.geist(
        fontSize: 16.0,
        height: 1.82,
        fontWeight: FontWeight.w400,
        color: _kBodyText,
        letterSpacing: 0.1,
      ),
    );
  }
}

/// A static, subtle musical staff watermark detail with a musical 'M' insignia.
class _MusicalStaffWatermarkPainter extends CustomPainter {
  const _MusicalStaffWatermarkPainter({
    required this.lineColor,
    required this.accentColor,
  });

  final Color lineColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final musicalPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final notePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    // 1. Draw the 5 subtle static staff lines
    final spacing = size.height / 4;
    for (int i = 0; i < 5; i++) {
      final y = i * spacing;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // 2. Musical "M" insignia: two eighth-note stems and noteheads joined into an 'M'
    const startX = 14.0;
    const mWidth = 24.0;
    const x1 = startX;
    const xMid = startX + mWidth / 2;
    const x2 = startX + mWidth;

    final yBottom = 4 * spacing; // bottom staff line
    const yTop = 0.5;            // top staff line
    final yMid = 2 * spacing;    // center staff line

    // Left musical notehead (angled)
    canvas.save();
    canvas.translate(x1, yBottom);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 5.4, height: 3.8),
      notePaint,
    );
    canvas.restore();

    // Right musical notehead (angled)
    canvas.save();
    canvas.translate(x2, yBottom);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 5.4, height: 3.8),
      notePaint,
    );
    canvas.restore();

    // Flowing musical "M" arch path connecting stems through the middle staff line
    final mPath = Path()
      ..moveTo(x1 + 1.2, yBottom)
      ..lineTo(x1 + 1.2, yTop + 2.0)
      ..cubicTo(
        x1 + 1.2, yTop - 0.5,
        xMid - 3.0, yTop + 1.0,
        xMid, yMid,
      )
      ..cubicTo(
        xMid + 3.0, yTop + 1.0,
        x2 - 1.2, yTop - 0.5,
        x2 - 1.2, yTop + 2.0,
      )
      ..lineTo(x2 - 1.2, yBottom);

    canvas.drawPath(mPath, musicalPaint);

    // Delicate musical eighth-note flag/flourish trailing from top right
    final flagPath = Path()
      ..moveTo(x2 - 1.2, yTop + 1.5)
      ..cubicTo(
        x2 + 4.5, yTop + 1.5,
        x2 + 5.5, yMid - 1.0,
        x2 + 2.2, yMid + 2.0,
      );

    canvas.drawPath(flagPath, musicalPaint..strokeWidth = 1.3);
  }

  @override
  bool shouldRepaint(covariant _MusicalStaffWatermarkPainter oldDelegate) => false;
}
