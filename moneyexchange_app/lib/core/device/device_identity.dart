import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

/// A stable, privacy-preserving identifier for the current device, sent on sign-up / sign-in so an
/// account can be bound to one phone (the backend rejects a login from a different device).
///
/// On Android the source is `Settings.Secure.ANDROID_ID` (read natively, see [_channel]), hashed
/// with SHA-256 so the raw id never leaves the device. ANDROID_ID is **unique per physical device**
/// (per app-signing key) and stable across app **reinstalls**, so a reinstall doesn't lock the real
/// owner out — and, crucially, two different phones of the *same model + firmware* get *different*
/// ids. The earlier source (`device_info_plus`'s `AndroidDeviceInfo.id`) is `Build.ID` — the
/// firmware build string — which is IDENTICAL on every device of the same model/build, so two
/// distinct "samsung SM-A075F" phones collided under the one-account-per-device check. On other
/// platforms (iOS, tests) [id] is null, which the backend treats as "no device presented" (no lock).
class DeviceIdentity {
  const DeviceIdentity({this.id, this.label});

  /// SHA-256 hash of the device's unique hardware id, or null if unavailable (non-Android / error).
  final String? id;

  /// Human-readable device label (e.g. "samsung SM-A065F"), for admin/support. Null off Android.
  /// NOT used for the device lock — it isn't unique (see [id]).
  final String? label;

  static DeviceIdentity? _cached;

  /// Same native channel the forwarding bridge uses; `getDeviceId` returns the raw ANDROID_ID.
  static const _channel = MethodChannel('xawil/forwarding');

  /// Resolves (and caches) the current device identity. Never throws — any failure yields an
  /// empty identity so auth still proceeds.
  static Future<DeviceIdentity> resolve() async {
    if (_cached != null) return _cached!;
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        final label = '${info.manufacturer} ${info.model}'.trim();

        // Prefer the truly-unique ANDROID_ID from the native side. Fall back to the (non-unique)
        // build id only if the channel is unavailable, so auth never hard-fails on the id lookup.
        String? rawId;
        try {
          rawId = await _channel.invokeMethod<String>('getDeviceId');
        } catch (_) {
          rawId = null;
        }
        if (rawId == null || rawId.isEmpty) {
          rawId = info.id; // Build.ID fallback (not unique across identical devices)
        }

        final hashed = rawId.isEmpty
            ? null
            : sha256.convert(utf8.encode(rawId)).toString();

        // Append a short slice of the unique device-id hash to the human label, so two phones of
        // the SAME model (which share "samsung SM-A065F") are still distinguishable in the admin
        // table — e.g. "samsung SM-A065F · f2aae5". The lock itself keys on the full [id]; this
        // suffix is purely for display.
        final labelWithSuffix = (hashed != null && hashed.length >= 6)
            ? '$label · ${hashed.substring(0, 6)}'
            : label;
        _cached = DeviceIdentity(id: hashed, label: labelWithSuffix);
      } else {
        _cached = const DeviceIdentity();
      }
    } catch (_) {
      _cached = const DeviceIdentity();
    }
    return _cached!;
  }
}
