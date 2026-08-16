import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/app_update_api.dart';
import '../domain/app_update_info.dart';

/// Where we are in the update lifecycle. Only [updateRequired], [downloading],
/// and [installing] are *blocking* — the gate shows the non-dismissible update
/// screen for those and nothing else, so a failed/expired check never traps the
/// user in the old app.
enum AppUpdatePhase {
  /// Not checked yet.
  idle,

  /// A check is in flight.
  checking,

  /// The installed build is current (or newer). App proceeds normally.
  upToDate,

  /// The server reports a newer versionCode → the update is enforced.
  updateRequired,

  /// The APK is downloading.
  downloading,

  /// The download finished; the native installer has been launched.
  installing,
}

/// Immutable snapshot the update gate renders from.
class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.info,
    this.progress = 0,
    this.errorMessage,
    this.installedVersionCode = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.downloadStartedAt,
  });

  final AppUpdatePhase phase;
  final AppUpdateInfo? info;

  /// Download progress 0..1 while [phase] is [AppUpdatePhase.downloading].
  final double progress;

  /// A user-facing error from the most recent download/install attempt. Shown
  /// on the update screen with a retry, WITHOUT unblocking.
  final String? errorMessage;

  final int installedVersionCode;

  /// Bytes received / total so far in the current download (for the live
  /// "12.3 / 25.0 MB" + speed + ETA readout on the update screen).
  final int downloadedBytes;
  final int totalBytes;

  /// When the current download started, so [elapsed]/[bytesPerSecond]/[eta]
  /// can be computed live (a 1s ticker in the controller rebuilds the screen
  /// even between byte-progress callbacks).
  final DateTime? downloadStartedAt;

  /// The update screen is shown for exactly these phases.
  bool get isBlocking =>
      phase == AppUpdatePhase.updateRequired ||
      phase == AppUpdatePhase.downloading ||
      phase == AppUpdatePhase.installing;

  /// Time elapsed since the download began (recomputed each build → live clock).
  Duration get elapsed => downloadStartedAt == null
      ? Duration.zero
      : DateTime.now().difference(downloadStartedAt!);

  /// Current average download speed in bytes/second (0 until enough elapsed).
  double get bytesPerSecond {
    final ms = elapsed.inMilliseconds;
    if (ms <= 0 || downloadedBytes <= 0) return 0;
    return downloadedBytes / (ms / 1000);
  }

  /// Estimated time remaining, or null when it can't be estimated yet.
  Duration? get eta {
    final speed = bytesPerSecond;
    if (speed <= 0 || totalBytes <= 0 || downloadedBytes >= totalBytes) {
      return null;
    }
    return Duration(seconds: ((totalBytes - downloadedBytes) / speed).round());
  }

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    AppUpdateInfo? info,
    double? progress,
    String? errorMessage,
    bool clearError = false,
    int? installedVersionCode,
    int? downloadedBytes,
    int? totalBytes,
    DateTime? downloadStartedAt,
    bool clearDownloadStats = false,
  }) =>
      AppUpdateState(
        phase: phase ?? this.phase,
        info: info ?? this.info,
        progress: clearDownloadStats ? 0 : (progress ?? this.progress),
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        installedVersionCode: installedVersionCode ?? this.installedVersionCode,
        downloadedBytes:
            clearDownloadStats ? 0 : (downloadedBytes ?? this.downloadedBytes),
        totalBytes: clearDownloadStats ? 0 : (totalBytes ?? this.totalBytes),
        downloadStartedAt: clearDownloadStats
            ? null
            : (downloadStartedAt ?? this.downloadStartedAt),
      );
}

final appUpdateApiProvider = Provider<AppUpdateApi>(
  (ref) => AppUpdateApi(dio: ref.watch(apiClientProvider).dio),
);

final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
  AppUpdateController.new,
);

/// Checks the public update endpoint on launch and on every resume, and (when a
/// newer server versionCode exists) drives the mandatory download+install flow.
///
/// Fail-safe rules:
///  - A check that fails (API down / offline) NEVER blocks the app: if we're not
///    already enforcing an update, we leave the app usable.
///  - Once an update is enforced, a later failed check does NOT clear it.
///  - After installing, the resume-triggered re-check sees the new build number
///    and unblocks only when installed >= server.
class AppUpdateController extends Notifier<AppUpdateState> {
  @override
  AppUpdateState build() {
    // Stop the download ticker if this notifier is ever disposed.
    ref.onDispose(_stopTicker);
    // Kick off the first check after the first frame's providers settle.
    Future.microtask(check);
    return const AppUpdateState();
  }

  /// Re-evaluate against the server. Safe to call repeatedly (on resume).
  Future<void> check() async {
    // Self-updating install is Android-only; other platforms never gate.
    if (!Platform.isAndroid) {
      state = state.copyWith(phase: AppUpdatePhase.upToDate);
      return;
    }
    // Don't interrupt an in-progress download/install.
    if (state.phase == AppUpdatePhase.downloading ||
        state.phase == AppUpdatePhase.installing) {
      return;
    }

    final (installed, installedName) = await _installedVersion();
    state = state.copyWith(
      phase: AppUpdatePhase.checking,
      installedVersionCode: installed,
      clearError: true,
    );

    AppUpdateInfo? info;
    try {
      info = await ref.read(appUpdateApiProvider).fetchAndroid();
    } catch (_) {
      // API unavailable / offline → treat as "unknown". Never fabricate an
      // update. Keep an already-enforced update in place; otherwise proceed.
      if (state.phase != AppUpdatePhase.updateRequired) {
        state = state.copyWith(phase: AppUpdatePhase.upToDate);
      }
      return;
    }

    if (info != null && info.isNewerThan(installed, installedName)) {
      state = state.copyWith(
        phase: AppUpdatePhase.updateRequired,
        info: info,
        clearError: true,
      );
    } else {
      state = state.copyWith(phase: AppUpdatePhase.upToDate, clearError: true);
    }
  }

  /// The whole "Update Now" flow: ensure the install permission, download the
  /// APK, and launch the native installer. Any failure keeps the app blocked on
  /// the update screen with a retryable error — it never unblocks the old app.
  Future<void> downloadAndInstall() async {
    final info = state.info;
    if (info == null) return;
    if (state.phase == AppUpdatePhase.downloading) return;

    // 1) The app must be an allowed install source ("install unknown apps").
    if (!await _ensureInstallPermission()) {
      state = state.copyWith(
        phase: AppUpdatePhase.updateRequired,
        errorMessage:
            'Allow installing apps from this app, then tap Update Now again.',
      );
      return;
    }

    // 2) Download the signed APK to app storage, showing live progress/time.
    state = state.copyWith(
      phase: AppUpdatePhase.downloading,
      clearDownloadStats: true,
      downloadStartedAt: DateTime.now(),
      clearError: true,
    );
    _startTicker();
    String filePath;
    try {
      filePath = await _downloadApk(info);
    } catch (_) {
      _stopTicker();
      state = state.copyWith(
        phase: AppUpdatePhase.updateRequired,
        errorMessage: 'Download failed. Check your connection and try again.',
      );
      return;
    }
    _stopTicker();

    // 3) Download finished → AUTO-INSTALL: hand the APK straight to the native
    // package installer, no extra tap. (The "Update Now" tap already covers the
    // download+install as one action.)
    state = state.copyWith(phase: AppUpdatePhase.installing);
    final result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      state = state.copyWith(
        phase: AppUpdatePhase.updateRequired,
        errorMessage: 'Could not open the installer. Tap Update Now to retry.',
      );
    }
    // On success the OS installer takes over; when the app resumes after the
    // install, check() re-runs and unblocks only if the new build is >= server.
  }

  /// A 1-second ticker that nudges the state during a download so the elapsed
  /// clock / speed / ETA on the update screen advance even between Dio's
  /// byte-progress callbacks. Started when a download begins, stopped when it
  /// ends (success or failure) and when the notifier is disposed.
  Timer? _ticker;

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.phase == AppUpdatePhase.downloading) {
        state = state.copyWith(); // recompute elapsed/speed/eta getters
      } else {
        _stopTicker();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<bool> _ensureInstallPermission() async {
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;
    final requested = await Permission.requestInstallPackages.request();
    if (requested.isGranted) return true;
    if (requested.isPermanentlyDenied) {
      // Route the user to the system "install unknown apps" toggle for this app.
      await openAppSettings();
    }
    return false;
  }

  Future<String> _downloadApk(AppUpdateInfo info) async {
    final dir = await getTemporaryDirectory();
    final safeVersion = info.versionName.replaceAll(RegExp(r'[^0-9.]'), '');
    final path = '${dir.path}/xawil-update-$safeVersion-${info.versionCode}.apk';
    // Fresh copy each attempt so a half-written file from a failed run can't be
    // handed to the installer.
    final file = File(path);
    if (await file.exists()) await file.delete();

    // Best-effort: count this download server-side. The shared client's base URL
    // (which honors the local→prod fallback) + the public tracking endpoint that
    // increments DownloadCount and 302-redirects to the same APK. If it's
    // unreachable we still fetch the APK directly below — counting must never
    // block a mandatory update.
    final base = ref.read(apiClientProvider).dio.options.baseUrl;
    final source = base.isNotEmpty
        ? '${base.replaceAll(RegExp(r'/+$'), '')}/api/app-updates/android/download'
        : info.apkUrl;

    Future<void> run(String url) => Dio().download(
          url,
          path,
          onReceiveProgress: (received, total) {
            state = state.copyWith(
              downloadedBytes: received,
              totalBytes: total > 0 ? total : state.totalBytes,
              progress: total > 0 ? received / total : state.progress,
            );
          },
        );

    try {
      await run(source);
    } catch (_) {
      // Tracking redirect failed (API down) but Supabase may be fine → retry the
      // absolute APK URL directly so the update can still proceed.
      if (source == info.apkUrl) rethrow;
      final f = File(path);
      if (await f.exists()) await f.delete();
      await run(info.apkUrl);
    }
    return path;
  }

  /// The installed build number AND version name, read together from the package
  /// so the gate can compare by the (loop-proof) semantic version name and keep
  /// the code as a fallback. Returns (0, '') if the package info can't be read.
  Future<(int, String)> _installedVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      return (int.tryParse(pkg.buildNumber) ?? 0, pkg.version);
    } catch (_) {
      return (0, '');
    }
  }
}
