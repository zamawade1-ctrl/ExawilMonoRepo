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
  });

  final AppUpdatePhase phase;
  final AppUpdateInfo? info;

  /// Download progress 0..1 while [phase] is [AppUpdatePhase.downloading].
  final double progress;

  /// A user-facing error from the most recent download/install attempt. Shown
  /// on the update screen with a retry, WITHOUT unblocking.
  final String? errorMessage;

  final int installedVersionCode;

  /// The update screen is shown for exactly these phases.
  bool get isBlocking =>
      phase == AppUpdatePhase.updateRequired ||
      phase == AppUpdatePhase.downloading ||
      phase == AppUpdatePhase.installing;

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    AppUpdateInfo? info,
    double? progress,
    String? errorMessage,
    bool clearError = false,
    int? installedVersionCode,
  }) =>
      AppUpdateState(
        phase: phase ?? this.phase,
        info: info ?? this.info,
        progress: progress ?? this.progress,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        installedVersionCode: installedVersionCode ?? this.installedVersionCode,
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

    final installed = await _installedVersionCode();
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

    if (info != null && info.isNewerThan(installed)) {
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

    // 2) Download the signed APK to app storage.
    state = state.copyWith(
      phase: AppUpdatePhase.downloading,
      progress: 0,
      clearError: true,
    );
    String filePath;
    try {
      filePath = await _downloadApk(info);
    } catch (_) {
      state = state.copyWith(
        phase: AppUpdatePhase.updateRequired,
        errorMessage: 'Download failed. Check your connection and try again.',
      );
      return;
    }

    // 3) Hand the APK to the native package installer.
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

    await Dio().download(
      info.apkUrl,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          state = state.copyWith(progress: received / total);
        }
      },
    );
    return path;
  }

  Future<int> _installedVersionCode() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      return int.tryParse(pkg.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
