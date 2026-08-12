import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// A stable, privacy-preserving identifier for the current device, sent on sign-up / sign-in so an
/// account can be bound to one phone (the backend rejects a login from a different device).
///
/// On Android the source is `ANDROID_ID`, hashed with SHA-256 so the raw id never leaves the device.
/// `ANDROID_ID` is stable across app **reinstalls** (tied to the signing key + device), so a
/// reinstall doesn't lock the real owner out — a fresh random id would. On other platforms (iOS,
/// tests) [id] is null, which the backend treats as "no device presented" (no lock enforced).
class DeviceIdentity {
  const DeviceIdentity({this.id, this.label});

  /// SHA-256 hash of the device's hardware id, or null if unavailable (non-Android / error).
  final String? id;

  /// Human-readable device label (e.g. "samsung SM-A065F"), for admin/support. Null off Android.
  final String? label;

  static DeviceIdentity? _cached;

  /// Resolves (and caches) the current device identity. Never throws — any failure yields an
  /// empty identity so auth still proceeds.
  static Future<DeviceIdentity> resolve() async {
    if (_cached != null) return _cached!;
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        final androidId = info.id; // ANDROID_ID
        final hashed = sha256.convert(utf8.encode(androidId)).toString();
        _cached = DeviceIdentity(
          id: hashed,
          label: '${info.manufacturer} ${info.model}'.trim(),
        );
      } else {
        _cached = const DeviceIdentity();
      }
    } catch (_) {
      _cached = const DeviceIdentity();
    }
    return _cached!;
  }
}
