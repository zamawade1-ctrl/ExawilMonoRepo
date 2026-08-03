/// The signed-in user, as returned by POST /api/auth/google.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.profilePictureUrl,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['userId'] as int,
    email: json['email'] as String,
    fullName: json['fullName'] as String,
    profilePictureUrl: json['profilePictureUrl'] as String?,
  );

  final int id;
  final String email;
  final String fullName;
  final String? profilePictureUrl;

  Map<String, dynamic> toJson() => {
    'userId': id,
    'email': email,
    'fullName': fullName,
    'profilePictureUrl': profilePictureUrl,
  };
}
