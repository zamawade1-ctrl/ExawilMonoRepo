import '../../../core/storage/session_storage.dart';
import '../domain/app_user.dart';
import 'auth_api.dart';
import 'google_auth_service.dart';

/// Orchestrates a full sign-in: Google account picker -> ID token -> backend
/// exchange -> persisted session. This is the one place that knows all three
/// pieces (Google, the backend, secure storage) have to happen together.
class AuthRepository {
  AuthRepository({
    required GoogleAuthService googleAuthService,
    required AuthApi authApi,
    required SessionStorage sessionStorage,
  }) : _googleAuthService = googleAuthService,
       _authApi = authApi,
       _sessionStorage = sessionStorage;

  final GoogleAuthService _googleAuthService;
  final AuthApi _authApi;
  final SessionStorage _sessionStorage;

  Future<AppUser> signInWithGoogle() async {
    final idToken = await _googleAuthService.signInAndGetIdToken();
    final (accessToken, user) = await _authApi.signInWithGoogle(idToken);
    await _sessionStorage.save(
      accessToken: accessToken,
      userProfileJson: user.toJson(),
    );
    return user;
  }

  /// Restores the cached profile from a previous sign-in, if a session is
  /// still stored. Returns null if the user is signed out.
  Future<AppUser?> restoreSession() async {
    final token = await _sessionStorage.readAccessToken();
    if (token == null) return null;

    final profile = await _sessionStorage.readUserProfile();
    if (profile == null) return null;

    return AppUser.fromJson(profile);
  }

  Future<void> signOut() async {
    await _googleAuthService.signOut();
    await _sessionStorage.clear();
  }
}
