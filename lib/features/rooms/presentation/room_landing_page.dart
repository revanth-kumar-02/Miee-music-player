import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../providers/room_providers.dart';

class RoomLandingPage extends ConsumerWidget {
  const RoomLandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomState = ref.watch(roomControllerProvider);
    final activeRoom = roomState.activeRoom;

    return Scaffold(
      backgroundColor: AppColors.vanillaCream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.cocoaPlum),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Listen Together',
          style: GoogleFonts.playfairDisplay(
            color: AppColors.cocoaPlum,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.marginMobile, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Hero Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.cocoaPlum,
                      AppColors.cocoaPlum.withOpacity(0.92),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cocoaPlum.withOpacity(0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.dustyRose.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 14, color: AppColors.dustyRose),
                          const SizedBox(width: 4),
                          Text(
                            'REALTIME AUDIO SYNC',
                            style: GoogleFonts.geist(
                              color: AppColors.dustyRose,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Stream music with your friends in real-time.',
                      style: GoogleFonts.playfairDisplay(
                        color: AppColors.vanillaCream,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Host a private room for up to 5 listeners. Playback, seeking, and queue changes synchronize across devices instantly.',
                      style: GoogleFonts.geist(
                        color: AppColors.vanillaCream.withOpacity(0.8),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. Active Session Card (if user is currently in a room)
              if (activeRoom != null) ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.softClay.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(color: AppColors.softClay.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ACTIVE SESSION',
                                style: GoogleFonts.geist(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: AppColors.cocoaPlum,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Code: ${activeRoom.joinCode}',
                            style: GoogleFonts.geist(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.cocoaPlum,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        activeRoom.name,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.cocoaPlum,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${roomState.members.length} / ${activeRoom.capacity} participants • ${roomState.isHost ? "Host" : "Listener"}',
                        style: GoogleFonts.geist(
                          fontSize: 12,
                          color: AppColors.cocoaPlum.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => context.push('/rooms/active'),
                              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                              label: const Text('Return to Room'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cocoaPlum,
                                foregroundColor: AppColors.vanillaCream,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppColors.vanillaCream,
                                  title: Text('Leave Room', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
                                  content: Text(
                                    roomState.isHost
                                        ? 'As host, leaving will close the room for all participants. Continue?'
                                        : 'Are you sure you want to leave this listening room?',
                                    style: GoogleFonts.geist(),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel', style: TextStyle(color: AppColors.cocoaPlum)),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: Text(roomState.isHost ? 'End Room' : 'Leave'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                if (roomState.isHost) {
                                  await ref.read(roomControllerProvider.notifier).endRoom();
                                } else {
                                  await ref.read(roomControllerProvider.notifier).leaveRoom();
                                }
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            ),
                            child: const Text('Exit'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // 3. Action Cards
              Row(
                children: [
                  // Create Room Card
                  Expanded(
                    child: _buildActionTile(
                      context: context,
                      title: 'Create Room',
                      subtitle: 'Choose capacity (1-5) and share code with friends',
                      icon: Icons.add_circle_outline_rounded,
                      accentColor: AppColors.dustyRose,
                      onTap: () => context.push('/rooms/create'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Join Room Card
                  Expanded(
                    child: _buildActionTile(
                      context: context,
                      title: 'Join Room',
                      subtitle: 'Enter a 6-digit room code to listen in sync',
                      icon: Icons.login_rounded,
                      accentColor: AppColors.softClay,
                      onTap: () => context.push('/rooms/join'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // 4. Feature Highlights
              Text(
                'HOW IT WORKS',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.cocoaPlum.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 14),

              _buildFeatureRow(
                icon: Icons.people_outline_rounded,
                title: 'Locked Capacity (1 to 5)',
                description: 'The host sets the maximum capacity at room creation. Server enforces seat limits atomically.',
              ),
              const SizedBox(height: 12),
              _buildFeatureRow(
                icon: Icons.tune_rounded,
                title: 'Host Authority',
                description: 'The host chooses the music, skips tracks, and scrubs time. Listeners stay perfectly in sync.',
              ),
              const SizedBox(height: 12),
              _buildFeatureRow(
                icon: Icons.speed_rounded,
                title: 'Automatic Drift Correction',
                description: 'Continuous timestamp checks correct playback drift quietly without audible jitter.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        height: 175,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: AppColors.cocoaPlum.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 24),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    color: AppColors.cocoaPlum.withOpacity(0.65),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.dustyRose),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    color: AppColors.cocoaPlum.withOpacity(0.65),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
