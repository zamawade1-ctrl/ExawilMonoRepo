/// The signed-in user, as returned by POST /api/auth/register and
/// POST /api/auth/login. [id] is the backend `User` id (the JWT's subject); the
/// linked forwarding profile is fetched separately via /api/customers/me.
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    this.username,
    this.email,
    this.phoneNumber,
    this.profilePictureUrl,
  });

  /// Rebuilds the cached user from what [toJson] stored in secure storage.
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    fullName: json['fullName'] as String? ?? '',
    username: json['username'] as String?,
    email: json['email'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
    profilePictureUrl: json['profilePictureUrl'] as String?,
  );

  /// Builds the user from the backend's auth response (`data` envelope of
  /// /api/auth/register|login), whose identity id field is `userId`.
  factory AppUser.fromAuthResponse(Map<String, dynamic> json) => AppUser(
    id: json['userId'] as int,
    fullName: json['fullName'] as String? ?? '',
    username: json['username'] as String?,
    email: json['email'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
    profilePictureUrl: json['profilePictureUrl'] as String?,
  );

  final int id;
  final String fullName;
  final String? username;
  final String? email;
  final String? phoneNumber;

  /// No longer populated (Google profile photos are gone with the Google flow),
  /// but kept so the home/drawer avatar code doesn't need to special-case it.
  final String? profilePictureUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fullName': fullName,
    'username': username,
    'email': email,
    'phoneNumber': phoneNumber,
    'profilePictureUrl': profilePictureUrl,
  };
}
