import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../providers/sleep_timer_provider.dart';

/// Preset durations required by Miee Sleep Timer specification.
const List<int> _kPresetMinutes = [5, 10, 15, 20, 30, 45, 60, 90];

/// Modal bottom sheet for configuring Miee Sleep Timer.
class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});

  /// Presents the [SleepTimerSheet] as a styled modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SleepTimerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(sleepTimerProvider);
    final timerNotifier = ref.read(sleepTimerProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.vanillaCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.0)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: AppColors.oatBeige,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Sheet Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.dustyRose.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.bedtime_rounded,
                        color: AppColors.dustyRose,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sleep Timer',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.cocoaPlum,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            timerState.isActive
                                ? (timerState.isCountdown
                                    ? 'Stops in ${timerState.formattedRemainingTime}'
                                    : 'Stops after current song')
                                : 'Music will stop automatically',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: timerState.isActive
                                  ? AppColors.dustyRose
                                  : AppColors.industrialSteel,
                              fontWeight: timerState.isActive
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (timerState.isActive)
                      TextButton.icon(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Turn Off'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: () {
                          timerNotifier.cancelTimer();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Sleep timer turned off'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 18),
              const Divider(height: 1, color: AppColors.oatBeige),
              const SizedBox(height: 14),

              // End of Current Track Option
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: InkWell(
                  onTap: () {
                    timerNotifier.startEndOfTrack();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Playback will stop after the current song'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: timerState.isEndOfTrack
                          ? AppColors.dustyRose.withValues(alpha: 0.12)
                          : AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: timerState.isEndOfTrack
                            ? AppColors.dustyRose
                            : AppColors.oatBeige,
                        width: timerState.isEndOfTrack ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.skip_next_rounded,
                          color: timerState.isEndOfTrack
                              ? AppColors.dustyRose
                              : AppColors.cocoaPlum,
                          size: 24,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stop after current song',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.cocoaPlum,
                                ),
                              ),
                              Text(
                                'Let the active track finish naturally',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  color: AppColors.industrialSteel,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (timerState.isEndOfTrack)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.dustyRose,
                            size: 22,
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Section Label: Preset Durations
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  'TIMER DURATION',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.industrialSteel,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Presets Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: _kPresetMinutes.map((mins) {
                    final isSelected = timerState.isCountdown &&
                        timerState.totalDuration != null &&
                        timerState.totalDuration!.inMinutes == mins;

                    return ChoiceChip(
                      label: Text('$mins min'),
                      labelStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected ? Colors.white : AppColors.cocoaPlum,
                      ),
                      selected: isSelected,
                      selectedColor: AppColors.dustyRose,
                      backgroundColor: AppColors.white,
                      side: BorderSide(
                        color: isSelected ? AppColors.dustyRose : AppColors.oatBeige,
                        width: 1.0,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          timerNotifier.startTimer(Duration(minutes: mins));
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Sleep timer set for $mins minutes'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // Custom Duration Option
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: InkWell(
                  onTap: () => _showCustomDurationDialog(context, timerNotifier),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.oatBeige),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          color: AppColors.cocoaPlum,
                          size: 22,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Custom Duration...',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.industrialSteel,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomDurationDialog(BuildContext context, SleepTimerNotifier notifier) {
    int selectedMinutes = 25;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.vanillaCream,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                'Custom Sleep Timer',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: AppColors.cocoaPlum,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$selectedMinutes minutes',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dustyRose,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selectedMinutes >= 60
                        ? '${selectedMinutes ~/ 60}h ${selectedMinutes % 60}m'
                        : 'Playback will stop after $selectedMinutes minutes',
                    style: const TextStyle(color: AppColors.industrialSteel, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: selectedMinutes.toDouble(),
                    min: 1,
                    max: 180,
                    divisions: 179,
                    activeColor: AppColors.dustyRose,
                    inactiveColor: AppColors.oatBeige,
                    label: '$selectedMinutes min',
                    onChanged: (val) {
                      setDialogState(() {
                        selectedMinutes = val.round();
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.industrialSteel)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.dustyRose,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    notifier.startTimer(Duration(minutes: selectedMinutes));
                    Navigator.pop(context); // Close bottom sheet
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sleep timer set for $selectedMinutes minutes'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('Start Timer'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
