import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/sync/supabase_config.dart';
import '../domain/room_models.dart';

class RoomRepository {
  SupabaseClient? get _client {
    if (!SupabaseConfig.hasActiveSupabase) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Creates a listening room atomically via Postgres stored procedure,
  /// enforcing capacity (1-5), host membership, and initial playback state.
  Future<ListeningRoom> createRoom({
    required String name,
    int capacity = 5,
  }) async {
    if (capacity < 1 || capacity > 5) {
      throw ArgumentError('Room capacity must be between 1 and 5.');
    }

    final client = _client;
    if (client == null) {
      throw Exception('Supabase is not configured.');
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User must be authenticated to host a room.');
    }

    final trimmedName = name.trim().isNotEmpty ? name.trim() : 'Miee Jam';

    try {
      final response = await client.rpc(
        'create_room',
        params: {
          'p_name': trimmedName,
          'p_capacity': capacity,
        },
      );

      if (response is Map) {
        return ListeningRoom.fromMap(Map<String, dynamic>.from(response));
      }
      throw Exception('Unexpected response from room creation service.');
    } on PostgrestException catch (e) {
      debugPrint('[RoomRepository] createRoom PostgrestException: ${e.message} (code: ${e.code})');
      if (e.code == '22023') {
        throw ArgumentError('Room capacity must be between 1 and 5.');
      }
      if (e.code == '42501') {
        throw Exception('You are not authorized to create a room. Please sign in again.');
      }
      throw Exception(e.message);
    } catch (e) {
      debugPrint('[RoomRepository] createRoom error: $e');
      rethrow;
    }
  }

  /// Atomically joins a room via Postgres stored procedure, enforcing capacity (1-5) server-side.
  Future<Map<String, dynamic>> joinRoom(String joinCode) async {
    final cleanedCode = joinCode.trim().toUpperCase();
    if (cleanedCode.isEmpty) {
      throw ArgumentError('Join code cannot be empty.');
    }

    final client = _client;
    if (client == null) {
      throw Exception('Supabase is not configured.');
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User must be authenticated to join a room.');
    }

    final response = await client.rpc(
      'join_room',
      params: {'p_join_code': cleanedCode},
    );

    if (response is Map) {
      final success = response['success'] as bool? ?? false;
      if (!success) {
        throw Exception(response['error'] ?? 'Failed to join room.');
      }
      return Map<String, dynamic>.from(response);
    }

    throw Exception('Unexpected response from room service.');
  }

  /// Fetches a room by its ID.
  Future<ListeningRoom?> getRoom(String roomId) async {
    final client = _client;
    if (client == null) return null;

    final res = await client.from('rooms').select().eq('id', roomId).maybeSingle();
    return res != null ? ListeningRoom.fromMap(res) : null;
  }

  /// Fetches all members of a room and enriches with profile data.
  Future<List<RoomMember>> getRoomMembers(String roomId) async {
    final client = _client;
    if (client == null) return [];

    final res = await client.from('room_members').select().eq('room_id', roomId);
    final members = (res as List)
        .map((m) => RoomMember.fromMap(m as Map<String, dynamic>))
        .toList();

    if (members.isEmpty) return [];

    try {
      final userIds = members.map((m) => m.userId).toList();
      final profilesRes = await client
          .from('profiles')
          .select('id, display_name, avatar_url')
          .inFilter('id', userIds);

      final profileMap = {
        for (final p in (profilesRes as List))
          p['id'] as String: p as Map<String, dynamic>
      };

      return members.map((m) {
        final prof = profileMap[m.userId];
        if (prof != null) {
          return m.copyWith(
            displayName: prof['display_name'] as String?,
            avatarUrl: prof['avatar_url'] as String?,
          );
        }
        return m;
      }).toList();
    } catch (_) {
      return members;
    }
  }

  /// Fetches current playback state of a room.
  Future<RoomPlaybackState?> getRoomState(String roomId) async {
    final client = _client;
    if (client == null) return null;

    final res = await client.from('room_state').select().eq('room_id', roomId).maybeSingle();
    return res != null ? RoomPlaybackState.fromMap(res) : null;
  }

  /// Updates room playback state (RLS ensures only host can update).
  Future<void> updatePlaybackState(RoomPlaybackState state) async {
    final client = _client;
    if (client == null) return;

    final userId = client.auth.currentUser?.id;
    await client.from('room_state').upsert({
      'room_id': state.roomId,
      'current_track_id': state.currentTrackId,
      'title': state.title,
      'artist': state.artist,
      'image_url': state.imageUrl,
      'duration_ms': state.durationMs,
      'is_youtube': state.isYoutube,
      'queue': state.queue,
      'playback_status': state.playbackStatus,
      'position_ms': state.positionMs,
      'updated_at': DateTime.now().toIso8601String(),
      'updated_by': userId,
    });
  }

  /// Ends a room (host only).
  Future<void> endRoom(String roomId) async {
    final client = _client;
    if (client == null) return;
    await client.from('rooms').update({'status': 'ended'}).eq('id', roomId);
  }

  /// Removes current user from room membership. If host leaves, marks room ended.
  Future<void> leaveRoom(String roomId) async {
    final client = _client;
    if (client == null) return;

    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    // Check if host
    final room = await getRoom(roomId);
    if (room?.hostId == userId) {
      await endRoom(roomId);
    }

    await client
        .from('room_members')
        .delete()
        .eq('room_id', roomId)
        .eq('user_id', userId);
  }

  /// Fetches recent messages for a room ordered chronologically.
  Future<List<RoomMessage>> getRoomMessages(String roomId, {int limit = 100}) async {
    final client = _client;
    if (client == null) return [];

    try {
      final res = await client
          .from('room_messages')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: true)
          .limit(limit);

      return (res as List)
          .map((m) => RoomMessage.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[RoomRepository] getRoomMessages error: $e');
      return [];
    }
  }

  /// Sends a text message or rich song suggestion into the room.
  Future<RoomMessage> sendMessage({
    required String roomId,
    required String content,
    String type = 'text',
    String? trackId,
    String? trackTitle,
    String? trackArtist,
    String? trackImageUrl,
    bool isYoutube = true,
  }) async {
    final client = _client;
    if (client == null) {
      throw Exception('Supabase is not configured.');
    }

    final user = client.auth.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated to chat.');
    }

    String? displayName = user.userMetadata?['display_name'] as String? ??
        user.userMetadata?['name'] as String? ??
        user.email?.split('@').first;
    String? avatarUrl = user.userMetadata?['avatar_url'] as String?;

    try {
      final profile = await client
          .from('profiles')
          .select('display_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) {
        if (profile['display_name'] != null) displayName = profile['display_name'] as String?;
        if (profile['avatar_url'] != null) avatarUrl = profile['avatar_url'] as String?;
      }
    } catch (_) {}

    final now = DateTime.now();
    final insertData = {
      'room_id': roomId,
      'user_id': user.id,
      'user_name': displayName ?? 'Listener',
      'user_avatar': avatarUrl,
      'content': content.trim(),
      'type': type,
      'track_id': trackId,
      'track_title': trackTitle,
      'track_artist': trackArtist,
      'track_image_url': trackImageUrl,
      'is_youtube': isYoutube,
      'created_at': now.toIso8601String(),
    };

    final res = await client.from('room_messages').insert(insertData).select().single();
    return RoomMessage.fromMap(res);
  }

  /// Subscribes to Supabase Realtime channel for room updates.
  RealtimeChannel? subscribeToRoom({
    required String roomId,
    required void Function(RoomPlaybackState state) onStateChanged,
    required void Function() onMembersChanged,
    void Function(RoomMessage message)? onMessageReceived,
    void Function()? onRoomEnded,
  }) {
    final client = _client;
    if (client == null) return null;

    final channelName = 'room:$roomId';
    final channel = client.channel(channelName);

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_state',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                onStateChanged(RoomPlaybackState.fromMap(newRecord));
              }
            } catch (e) {
              debugPrint('[RoomRepository] Realtime state parse error: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (_) {
            onMembersChanged();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                onMessageReceived?.call(RoomMessage.fromMap(newRecord));
              }
            } catch (e) {
              debugPrint('[RoomRepository] Realtime message event error: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty && newRecord['status'] == 'ended') {
                onRoomEnded?.call();
              }
            } catch (e) {
              debugPrint('[RoomRepository] Realtime room event error: $e');
            }
          },
        )
        .subscribe();

    return channel;
  }
}
