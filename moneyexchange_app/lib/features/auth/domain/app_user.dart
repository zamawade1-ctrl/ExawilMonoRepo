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
    this.hasAppPin = false,
    this.pinEnabled = true,
    this.role = 'User',
  });

  /// Rebuilds the cached user from what [toJson] stored in secure storage.
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as int,
    fullName: json['fullName'] as String? ?? '',
    username: json['username'] as String?,
    email: json['email'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
    profilePictureUrl: json['profilePictureUrl'] as String?,
    hasAppPin: json['hasAppPin'] as bool? ?? false,
    pinEnabled: json['pinEnabled'] as bool? ?? true,
    role: json['role'] as String? ?? 'User',
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
    hasAppPin: json['hasAppPin'] as bool? ?? false,
    pinEnabled: json['pinEnabled'] as bool? ?? true,
    role: json['role'] as String? ?? 'User',
  );

  final int id;
  final String fullName;
  final String? username;
  final String? email;
  final String? phoneNumber;

  /// No longer populated (Google profile photos are gone with the Google flow),
  /// but kept so the home/drawer avatar code doesn't need to special-case it.
  final String? profilePictureUrl;

  /// Whether this user has set their custom 6-digit app-lock PIN yet. Drives the
  /// "set your PIN" gate on first entry vs the PIN unlock screen on later opens.
  final bool hasAppPin;

  /// Whether the app-lock PIN is turned on at all. When false, the set-PIN / lock
  /// gates are skipped and the app opens straight in.
  final bool pinEnabled;

  /// "User" or "Admin" — Admins land on the admin console instead of the home shell.
  final String role;

  /// True when this account is an administrator.
  bool get isAdmin => role.toLowerCase() == 'admin';

  AppUser copyWith({bool? hasAppPin, bool? pinEnabled, String? role}) => AppUser(
    id: id,
    fullName: fullName,
    username: username,
    email: email,
    phoneNumber: phoneNumber,
    profilePictureUrl: profilePictureUrl,
    hasAppPin: hasAppPin ?? this.hasAppPin,
    pinEnabled: pinEnabled ?? this.pinEnabled,
    role: role ?? this.role,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fullName': fullName,
    'username': username,
    'email': email,
    'phoneNumber': phoneNumber,
    'profilePictureUrl': profilePictureUrl,
    'hasAppPin': hasAppPin,
    'pinEnabled': pinEnabled,
    'role': role,
  };
}
