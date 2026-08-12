import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// On-device copy of the user's 6-digit app-lock PIN, in the platform
/// keystore/keychain (never SharedPreferences). This local copy is what the lock
/// screen verifies against, so unlocking works instantly and offline; the backend
/// keeps the authoritative PBKDF2 hash (the DB store the product requires). Keyed
/// per user id so multiple accounts on one device stay separate.
class AppPinStore {
  AppPinStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(int userId) => 'app_pin_$userId';

  Future<String?> read(int userId) => _storage.read(key: _key(userId));

  Future<void> write(int userId, String pin) =>
      _storage.write(key: _key(userId), value: pin);

  Future<void> clear(int userId) => _storage.delete(key: _key(userId));
}
