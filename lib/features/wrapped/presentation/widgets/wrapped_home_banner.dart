import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/app_colors.dart';
import '../../providers/wrapped_providers.dart';

class WrappedHomeBanner extends ConsumerWidget {
  const WrappedHomeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligibility = ref.watch(wrappedEligibilityProvider);

    // Miee Wrapped only appears when the user's account is at least 1 year old (or force-enabled)
    if (!eligibility.isEligible) {
      return const SizedBox.shrink();
    }

    final summary = ref.watch(wrappedSummaryProvider);
    final archetype = summary.archetype;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/wrapped'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.cocoaPlum,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.dustyRose.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: AppColors.cocoaPlum.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Glowing Icon Badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      archetype.primaryColor,
                      archetype.secondaryColor,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: archetype.primaryColor.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Banner Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'MIEE WRAPPED • YEAR ${eligibility.activeYear}',
                          style: GoogleFonts.geist(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: AppColors.dustyRose,
                          ),
                        ),
                        if (summary.isSampleData) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PREVIEW',
                              style: GoogleFonts.inter(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.amberAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your year in music is ready',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.vanillaCream,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Tap to explore top songs & listening archetype',
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        color: AppColors.vanillaCream.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Arrow
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.vanillaCream,
                  size: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
