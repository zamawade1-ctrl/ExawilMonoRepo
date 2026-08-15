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

  /// True when this server release is newer than the [installedVersionCode] and
  /// carries a usable HTTPS APK URL to update to.
  bool isNewerThan(int installedVersionCode) =>
      versionCode > installedVersionCode &&
      apkUrl.startsWith('https://');
}
