import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../providers/room_providers.dart';

class CreateRoomPage extends ConsumerStatefulWidget {
  const CreateRoomPage({super.key});

  @override
  ConsumerState<CreateRoomPage> createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends ConsumerState<CreateRoomPage> {
  final _nameController = TextEditingController(text: 'Miee Jam');
  int _selectedCapacity = 5; // Default capacity is 5 as locked requirement
  bool _startWithEmptyQueue = true; // Default to starting clean queue
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _getCapacityDescription(int cap) {
    switch (cap) {
      case 1:
        return 'Host only (1 listener total • private stream)';
      case 2:
        return 'Host + 1 friend (2 listeners total)';
      case 3:
        return 'Host + 2 friends (3 listeners total)';
      case 4:
        return 'Host + 3 friends (4 listeners total)';
      case 5:
      default:
        return 'Host + 4 friends (5 listeners total • Maximum)';
    }
  }

  Future<void> _handleCreate() async {
    if (_isCreating) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a room name.');
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      await ref.read(roomControllerProvider.notifier).createRoom(
            name: name,
            capacity: _selectedCapacity,
            clearQueue: _startWithEmptyQueue,
          );
      if (mounted) {
        context.pushReplacement('/rooms/active');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreating = false;
          _error = _formatErrorMessage(e);
        });
      }
    }
  }

  String _formatErrorMessage(dynamic error) {
    final str = error.toString();
    if (str.contains('42P17') || str.contains('infinite recursion')) {
      return 'Database policy error. Please try again or update the app.';
    }
    if (str.contains('SocketException') || str.contains('Failed host lookup') || str.contains('Network')) {
      return 'Network connection error. Please check your internet connection.';
    }
    if (str.contains('authenticated') || str.contains('sign in')) {
      return 'Please sign in to host a room.';
    }
    if (str.contains('capacity') || str.contains('22023')) {
      return 'Room capacity must be between 1 and 5.';
    }
    return str
        .replaceFirst('Exception: ', '')
        .replaceFirst('ArgumentError: ', '')
        .replaceFirst('PostgrestException(message: ', '')
        .split(', code:')[0];
  }

  @override
  Widget build(BuildContext context) {
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
          'Create Room',
          style: GoogleFonts.playfairDisplay(
            color: AppColors.cocoaPlum,
            fontSize: 20,
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
              // 1. Room Name Input
              Text(
                'ROOM NAME',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.cocoaPlum.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: GoogleFonts.geist(
                  color: AppColors.cocoaPlum,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. Late Night Vibes',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.cocoaPlum.withOpacity(0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.cocoaPlum.withOpacity(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.dustyRose, width: 2),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // 2. Room Capacity Selector (1-5 Locked Requirement)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ROOM CAPACITY (INCLUDES HOST)',
                    style: GoogleFonts.geist(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: AppColors.cocoaPlum.withOpacity(0.6),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.dustyRose.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Max $_selectedCapacity',
                      style: GoogleFonts.geist(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dustyRose,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 1 to 5 Pill Selection
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [1, 2, 3, 4, 5].map((cap) {
                  final isSelected = _selectedCapacity == cap;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => setState(() => _selectedCapacity = cap),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.cocoaPlum : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.cocoaPlum
                                  : AppColors.cocoaPlum.withOpacity(0.12),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppColors.cocoaPlum.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            children: [
                              Text(
                                '$cap',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? AppColors.vanillaCream : AppColors.cocoaPlum,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                cap == 1 ? 'solo' : 'seats',
                                style: GoogleFonts.geist(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? AppColors.vanillaCream.withOpacity(0.7)
                                      : AppColors.cocoaPlum.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),
              // Explanation text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.vanillaCream,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cocoaPlum.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.dustyRose),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getCapacityDescription(_selectedCapacity),
                        style: GoogleFonts.geist(
                          fontSize: 12,
                          color: AppColors.cocoaPlum.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 3. Queue Starting Option
              Text(
                'ROOM QUEUE OPTION',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.cocoaPlum.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 10),

              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppColors.cocoaPlum.withOpacity(0.1)),
                ),
                clipBehavior: Clip.antiAlias,
                child: SwitchListTile.adaptive(
                  value: _startWithEmptyQueue,
                  activeColor: AppColors.dustyRose,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    'Start with Empty Queue',
                    style: GoogleFonts.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.cocoaPlum,
                    ),
                  ),
                  subtitle: Text(
                    _startWithEmptyQueue
                        ? 'Starts fresh with an empty queue for your room'
                        : 'Imports your currently playing songs into the room',
                    style: GoogleFonts.geist(
                      fontSize: 12,
                      color: AppColors.cocoaPlum.withOpacity(0.6),
                    ),
                  ),
                  onChanged: (val) => setState(() => _startWithEmptyQueue = val),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.geist(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 36),

              // 3. Create Button
              ElevatedButton(
                onPressed: _isCreating ? null : _handleCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dustyRose,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 2,
                ),
                child: _isCreating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Create Room & Get Code',
                        style: GoogleFonts.geist(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
