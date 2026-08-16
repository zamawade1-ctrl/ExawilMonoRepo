/// The currently-active Android release as reported by the public backend
/// endpoint `GET /api/app-updates/android`. This is the single source of truth
/// the app compares against the installed build to decide whether to force an
/// update. All fields mirror the `app_versions` row for the active Android
/// release.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.platform,
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    this.releaseNotes,
    this.mandatory = true,
    this.releasedAtUtc,
  });

  /// e.g. "android".
  final String platform;

  /// Human-readable version, e.g. "1.2.0". Shown to the user.
  final String versionName;

  /// Android versionCode / build number. This — NOT [versionName] — is what the
  /// app compares against the installed build number to decide on an update.
  final int versionCode;

  /// Public HTTPS URL of the signed APK (Supabase Storage). Downloaded and
  /// handed to the native package installer.
  final String apkUrl;

  /// What changed in this release. Optional.
  final String? releaseNotes;

  /// Whether this release is a forced update. The app additionally enforces any
  /// release whose [versionCode] is newer than the installed build.
  final bool mandatory;

  /// When the release was published (UTC). Optional.
  final DateTime? releasedAtUtc;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) =>
        v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
    return AppUpdateInfo(
      platform: (json['platform'] ?? 'android').toString(),
      versionName: (json['versionName'] ?? '').toString(),
      versionCode: asInt(json['versionCode']),
      apkUrl: (json['apkUrl'] ?? '').toString(),
      releaseNotes: json['releaseNotes']?.toString(),
      mandatory: json['mandatory'] == null ? true : json['mandatory'] == true,
      releasedAtUtc: json['releasedAtUtc'] == null
          ? null
          : DateTime.tryParse(json['releasedAtUtc'].toString()),
    );
  }

  /// True when this server release is newer than what's installed and carries a
  /// usable HTTPS APK URL to update to.
  ///
  /// The gate compares the **versionName** (semantic, e.g. "1.0.10") as the
  /// PRIMARY signal, NOT the [versionCode] integer. The versionCode is an
  /// admin-entered field on the `app_versions` row that is trivial to mistype
  /// (e.g. entering 13 for an APK that is actually build 10) — and when it drifts
  /// ABOVE any APK's real build number, the old code-only comparison forced an
  /// update that installing could never satisfy, trapping users in a permanent
  /// "update required" loop. The versionName, by contrast, is the same string in
  /// pubspec, the APK, the download filename, and the row, so it stays in sync.
  ///
  /// Rule: force an update only when the server versionName is semantically newer
  /// than the installed one. If the names are EQUAL you are on this release — no
  /// update — regardless of any versionCode mismatch, which is what breaks the
  /// loop. Only when a versionName can't be parsed do we fall back to the legacy
  /// versionCode comparison.
  bool isNewerThan(int installedVersionCode, [String installedVersionName = '']) {
    if (!apkUrl.startsWith('https://')) return false;
    final cmp = _compareSemanticVersions(versionName, installedVersionName);
    if (cmp != null) return cmp > 0;
    // Unparseable name(s) → legacy behaviour so we never silently stop gating.
    return versionCode > installedVersionCode;
  }

  /// Compares two dotted numeric version strings ("1.0.10" vs "1.0.9"), returning
  /// >0 if [a] is newer, <0 if older, 0 if equal, or null if either has no parsable
  /// numeric segment (so the caller can fall back). Segments compare NUMERICALLY,
  /// so "1.0.10" > "1.0.9" (10 > 9), not as strings. Any non-digit suffix on a
  /// segment (e.g. "1.0.9-beta") is stripped to its leading digits.
  static int? _compareSemanticVersions(String a, String b) {
    List<int>? parse(String v) {
      final parts = v.trim().split('.');
      final nums = <int>[];
      for (final p in parts) {
        final m = RegExp(r'\d+').firstMatch(p);
        if (m == null) continue;
        nums.add(int.parse(m.group(0)!));
      }
      return nums.isEmpty ? null : nums;
    }

    final av = parse(a);
    final bv = parse(b);
    if (av == null || bv == null) return null;
    final len = av.length > bv.length ? av.length : bv.length;
    for (var i = 0; i < len; i++) {
      final ai = i < av.length ? av[i] : 0;
      final bi = i < bv.length ? bv[i] : 0;
      if (ai != bi) return ai - bi;
    }
    return 0;
  }
}
