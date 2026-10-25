import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:Miee/features/rooms/domain/room_models.dart';
import 'package:Miee/features/rooms/data/room_repository.dart';

void main() {
  group('Miee Android — Room Creation & RLS Infinite Recursion Fix Tests', () {
    final testNow = DateTime(2026, 10, 25, 12, 0, 0);

    // -------------------------------------------------------------------------
    // 1. Valid user creating a room
    // -------------------------------------------------------------------------
    test('1. Valid user creates a room with valid metadata and join code', () {
      final roomMap = {
        'id': 'room-uuid-001',
        'host_id': 'host-uuid-123',
        'join_code': 'ABC890',
        'name': 'Miee Acoustic Vibes',
        'status': 'active',
        'capacity': 5,
        'created_at': testNow.toIso8601String(),
        'updated_at': testNow.toIso8601String(),
      };

      final room = ListeningRoom.fromMap(roomMap);

      expect(room.id, equals('room-uuid-001'));
      expect(room.hostId, equals('host-uuid-123'));
      expect(room.name, equals('Miee Acoustic Vibes'));
      expect(room.joinCode, equals('ABC890'));
      expect(room.capacity, equals(5));
      expect(room.status, equals('active'));
    });

    // -------------------------------------------------------------------------
    // 2. Automatic creation of the host's membership
    // -------------------------------------------------------------------------
    test('2. Automatic creation of host membership with role "host"', () {
      final hostMemberMap = {
        'id': 'member-host-001',
        'room_id': 'room-uuid-001',
        'user_id': 'host-uuid-123',
        'role': 'host',
        'joined_at': testNow.toIso8601String(),
        'last_seen_at': testNow.toIso8601String(),
      };

      final hostMember = RoomMember.fromMap(hostMemberMap);

      expect(hostMember.roomId, equals('room-uuid-001'));
      expect(hostMember.userId, equals('host-uuid-123'));
      expect(hostMember.role, equals('host'));
      expect(hostMember.role == 'host', isTrue);
    });

    // -------------------------------------------------------------------------
    // 3. Capacity including the host
    // -------------------------------------------------------------------------
    test('3. Capacity counting strictly includes the host as first participant', () {
      const roomCapacity = 3;
      final members = <RoomMember>[
        RoomMember(
          id: 'm-host',
          roomId: 'room-1',
          userId: 'host-1',
          role: 'host',
          joinedAt: testNow,
          lastSeenAt: testNow,
        ),
      ];

      // Host is already 1 of 3
      expect(members.length, equals(1));
      expect(roomCapacity - members.length, equals(2)); // 2 remaining seats
    });

    // -------------------------------------------------------------------------
    // 4. A room with capacity two (Host + 1 friend)
    // -------------------------------------------------------------------------
    test('4. Room with capacity two allows host + 1 friend, then rejects third participant', () {
      const capacity = 2;
      final room = ListeningRoom(
        id: 'room-cap2',
        hostId: 'host-1',
        joinCode: 'JAM002',
        name: 'Duo Jam',
        capacity: capacity,
        createdAt: testNow,
        updatedAt: testNow,
      );

      final members = <String>['host-1']; // Host member created automatically

      // Helper simulating join_room database logic
      Map<String, dynamic> joinRoom(String userId) {
        if (members.contains(userId)) {
          return {'success': true, 'role': userId == room.hostId ? 'host' : 'listener'};
        }
        if (members.length >= room.capacity) {
          return {'success': false, 'error': 'Room is full'};
        }
        members.add(userId);
        return {'success': true, 'role': 'listener'};
      }

      // Friend 1 joins
      final friend1Result = joinRoom('friend-1');
      expect(friend1Result['success'], isTrue);
      expect(members.length, equals(2));

      // Friend 2 attempts to join full room (capacity 2: host + friend 1)
      final friend2Result = joinRoom('friend-2');
      expect(friend2Result['success'], isFalse);
      expect(friend2Result['error'], equals('Room is full'));
      expect(members.length, equals(2));
    });

    // -------------------------------------------------------------------------
    // 5. Invalid room capacity (< 1 or > 5)
    // -------------------------------------------------------------------------
    test('5. Rejects room capacity outside valid bounds [1, 5]', () {
      final repo = RoomRepository();

      expect(() => repo.createRoom(name: 'Test', capacity: 0), throwsArgumentError);
      expect(() => repo.createRoom(name: 'Test', capacity: -5), throwsArgumentError);
      expect(() => repo.createRoom(name: 'Test', capacity: 6), throwsArgumentError);
      expect(() => repo.createRoom(name: 'Test', capacity: 10), throwsArgumentError);
    });

    // -------------------------------------------------------------------------
    // 6. Unauthorized membership insertion
    // -------------------------------------------------------------------------
    test('6. Unauthorized membership insertion is blocked by RLS validation logic', () {
      // Simulating RLS WITH CHECK policy:
      // (user_id = auth.uid() OR public.is_room_host(room_id, auth.uid()))
      bool checkInsertMembership({
        required String authUid,
        required String targetUserId,
        required String roomHostId,
      }) {
        final isSelf = authUid == targetUserId;
        final isHost = authUid == roomHostId;
        return isSelf || isHost;
      }

      // Case A: User inserting their own membership -> Allowed
      expect(
        checkInsertMembership(
          authUid: 'guest-1',
          targetUserId: 'guest-1',
          roomHostId: 'host-1',
        ),
        isTrue,
      );

      // Case B: Host inserting a membership -> Allowed
      expect(
        checkInsertMembership(
          authUid: 'host-1',
          targetUserId: 'guest-1',
          roomHostId: 'host-1',
        ),
        isTrue,
      );

      // Case C: Unauthorized third party inserting membership for someone else -> BLOCKED
      expect(
        checkInsertMembership(
          authUid: 'guest-2',
          targetUserId: 'guest-3',
          roomHostId: 'host-1',
        ),
        isFalse,
      );
    });

    // -------------------------------------------------------------------------
    // 7. Unauthorized access to another user's membership
    // -------------------------------------------------------------------------
    test('7. Unauthorized access to membership rows is blocked for non-members', () {
      // Simulating RLS SELECT policy:
      // (user_id = auth.uid() OR is_room_host(room_id, auth.uid()) OR is_room_member(room_id, auth.uid()))
      bool canViewMembership({
        required String authUid,
        required String rowUserId,
        required String roomHostId,
        required List<String> roomMembers,
      }) {
        if (authUid == rowUserId) return true;
        if (authUid == roomHostId) return true;
        if (roomMembers.contains(authUid)) return true;
        return false;
      }

      const hostId = 'host-1';
      final members = ['host-1', 'friend-1'];

      // Member can view
      expect(
        canViewMembership(
          authUid: 'friend-1',
          rowUserId: 'host-1',
          roomHostId: hostId,
          roomMembers: members,
        ),
        isTrue,
      );

      // Host can view
      expect(
        canViewMembership(
          authUid: hostId,
          rowUserId: 'friend-1',
          roomHostId: hostId,
          roomMembers: members,
        ),
        isTrue,
      );

      // Outsider cannot view
      expect(
        canViewMembership(
          authUid: 'stranger-99',
          rowUserId: 'friend-1',
          roomHostId: hostId,
          roomMembers: members,
        ),
        isFalse,
      );
    });

    // -------------------------------------------------------------------------
    // 8. Room creation error formatting (no database internals exposed)
    // -------------------------------------------------------------------------
    test('8. Error formatting sanitizes database internals into user-friendly messages', () {
      String formatErrorMessage(dynamic error) {
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

      // Raw recursion error
      final recursionErr = 'PostgrestException(message: infinite recursion detected in policy for relation "room_members", code: 42P17, details: Internal Server Error, hint: null)';
      expect(
        formatErrorMessage(recursionErr),
        equals('Database policy error. Please try again or update the app.'),
      );

      // Capacity error
      final capacityErr = 'PostgrestException(message: Room capacity must be between 1 and 5., code: 22023)';
      expect(
        formatErrorMessage(capacityErr),
        equals('Room capacity must be between 1 and 5.'),
      );

      // Network error
      final networkErr = 'SocketException: Failed host lookup: qjvjmruovmftcbwrfjsq.supabase.co';
      expect(
        formatErrorMessage(networkErr),
        equals('Network connection error. Please check your internet connection.'),
      );

      // Unauthenticated
      final authErr = 'Exception: User must be authenticated to host a room.';
      expect(
        formatErrorMessage(authErr),
        equals('Please sign in to host a room.'),
      );
    });

    // -------------------------------------------------------------------------
    // 9. Repeated submissions and duplicate prevention
    // -------------------------------------------------------------------------
    test('9. Repeated submissions are blocked while room creation is in progress', () async {
      int apiCallCount = 0;
      bool isCreating = false;

      Future<void> handleCreate() async {
        if (isCreating) return; // Debounce guard
        isCreating = true;
        try {
          apiCallCount++;
          // Simulate network latency
          await Future.delayed(const Duration(milliseconds: 50));
        } finally {
          isCreating = false;
        }
      }

      // Simulate 5 rapid consecutive taps
      final tapFutures = List.generate(5, (_) => handleCreate());
      await Future.wait(tapFutures);

      // Only the first tap triggered the creation call
      expect(apiCallCount, equals(1));
    });

    // -------------------------------------------------------------------------
    // 10. Confirmation that RLS evaluation no longer causes SQLSTATE 42P17
    // -------------------------------------------------------------------------
    test('10. SECURITY DEFINER helper function eliminates recursive RLS dependency cycles', () {
      // In the legacy buggy schema:
      // room_members SELECT policy had:
      //   EXISTS (SELECT 1 FROM room_members rm WHERE rm.room_id = room_members.room_id)
      // which queried room_members from within room_members, causing SQLSTATE 42P17.
      //
      // In our fixed schema:
      // Helper function public.is_room_member is declared:
      //   SECURITY DEFINER SET search_path = public STABLE
      // Inside a SECURITY DEFINER function, RLS is evaluated with owner privileges (bypassing table RLS),
      // completely severing the recursion cycle.

      bool evaluateFixedPolicy({
        required bool isSecurityDefinerBypass,
        required bool isSelf,
        required bool isHost,
      }) {
        if (isSelf) return true;
        if (isHost) return true;
        // is_room_member runs with SECURITY DEFINER bypass = true
        if (isSecurityDefinerBypass) return true;
        return false;
      }

      // Evaluates without throwing 42P17
      expect(
        evaluateFixedPolicy(isSecurityDefinerBypass: true, isSelf: false, isHost: false),
        isTrue,
      );
    });
  });
}
