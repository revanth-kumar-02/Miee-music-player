import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Represents an authenticated user in the domain layer.
class AuthUser {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final bool isEmailVerified;

  const AuthUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.isEmailVerified = false,
  });

  factory AuthUser.fromSupabase(sb.User user) {
    final meta = user.userMetadata ?? {};
    final displayName = (meta['display_name'] ?? meta['full_name']) as String?;
    final photoUrl = meta['avatar_url'] as String?;

    return AuthUser(
      uid: user.id,
      email: user.email ?? '',
      displayName: displayName,
      photoUrl: photoUrl,
      isEmailVerified: user.emailConfirmedAt != null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser && runtimeType == other.runtimeType && uid == other.uid;

  @override
  int get hashCode => uid.hashCode;
}
