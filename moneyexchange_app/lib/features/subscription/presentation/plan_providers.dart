import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/device_identity.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../forwarding/data/forwarding_channel.dart';
import '../data/subscription_api.dart';
import '../domain/plan_snapshot.dart';

final subscriptionApiProvider = Provider(
  (ref) => SubscriptionApi(dio: ref.watch(apiClientProvider).dio),
);

/// The single source of truth for the signed-in user's trial/plan state. Seeds
/// from the cached snapshot (so the countdown survives a cold start / offline),
/// then best-effort refreshes from the backend. Every fresh snapshot is also
/// pushed to the native forwarder so an expired plan stops all USSD activity.
final planControllerProvider =
    AsyncNotifierProvider<PlanController, PlanSnapshot?>(PlanController.new);

class PlanController extends AsyncNotifier<PlanSnapshot?> {
  /// How often we re-pull the session (device validity + plan) from the backend while the app is
  /// open, so an admin action (expire plan, reset device) takes effect in near-real-time — within a
  /// few seconds, without the user logging out and back in.
  static const _pollInterval = Duration(seconds: 3);

  /// One-shot timer that fires exactly when the current plan/trial window ends, so the app moves
  /// the user to the activation screen the instant access lapses — no logout, no waiting for a poll.
  Timer? _expiryTimer;

  /// Periodic backend poll (see [_pollInterval]) — the authoritative real-time source of truth.
  Timer? _pollTimer;

  /// Re-checks the backend the moment the app returns to the foreground.
  AppLifecycleListener? _lifecycle;

  void _stopWatchers() {
    _expiryTimer?.cancel();
    _pollTimer?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  @override
  Future<PlanSnapshot?> build() async {
    // A rebuild (e.g. the signed-in user changed) supersedes any pending timers/listeners.
    _stopWatchers();
    ref.onDispose(_stopWatchers);

    final user = ref.watch(authControllerProvider).value;
    if (user == null) return null;

    PlanSnapshot? snapshot;
    // 1. Seed from the cached snapshot so we have something immediately.
    final cached = await ref.read(sessionStorageProvider).readPlan();
    if (cached != null) {
      try {
        snapshot = PlanSnapshot.fromCache(cached);
      } catch (_) {
        // Corrupt cache — ignore and rely on the network refresh below.
      }
    }
    // 2. Best-effort refresh from the backend (keeps the timestamps authoritative). Uses the session
    //    check so a device reset that happened while the app was closed signs the user out on open.
    try {
      final device = await DeviceIdentity.resolve();
      final result = await ref.read(subscriptionApiProvider).session(device.id);
      if (!result.valid) {
        await ref.read(authControllerProvider.notifier).signOut();
        return null;
      }
      snapshot = result.plan;
      await ref.read(sessionStorageProvider).savePlan(result.plan.toJson());
    } catch (_) {
      // Offline / backend down: fall back to the cached snapshot.
    }

    if (snapshot != null) {
      await _applyToNative(snapshot);
      _scheduleExpiry(snapshot);
    }

    // 3. Keep it live: poll the backend on an interval and whenever the app resumes, so expiry is
    //    detected in real time — the same fresh-status read a login would do, minus the login.
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refreshFromBackend());
    _lifecycle = AppLifecycleListener(onResume: _refreshFromBackend);

    return snapshot;
  }

  /// Polls the backend session (device validity + plan). If the admin reset this device's binding the
  /// session is no longer valid → sign out immediately so the account can re-bind on the next login
  /// from any device. Otherwise, if the plan differs from what we hold, emit it (a real state change
  /// that makes the router re-gate an expired user to the activation screen). Silent on failure — the
  /// offline path is covered by the local expiry timer.
  Future<void> _refreshFromBackend() async {
    final current = state.value;
    try {
      final device = await DeviceIdentity.resolve();
      final result = await ref.read(subscriptionApiProvider).session(device.id);

      // Device was reset/rebound elsewhere → end this session now (real-time sign-out).
      if (!result.valid) {
        await ref.read(authControllerProvider.notifier).signOut();
        return;
      }

      final fresh = result.plan;
      await ref.read(sessionStorageProvider).savePlan(fresh.toJson());

      final changed = current == null ||
          fresh.status != current.status ||
          fresh.planPaidUntilUtc != current.planPaidUntilUtc ||
          fresh.trialEndsAtUtc != current.trialEndsAtUtc;
      if (changed) {
        state = AsyncData(fresh);
        await _applyToNative(fresh);
      }
      _scheduleExpiry(fresh);
    } catch (_) {
      // Leave the current snapshot in place; the local expiry timer still fires at its boundary.
    }
  }

  /// Schedules (or reschedules) the one-shot expiry fire. When the active window still has time
  /// left, the timer fires at that boundary; when already expired there's nothing to schedule (and
  /// scheduling a zero-length timer would loop). Anchored to the drift-corrected remaining time.
  void _scheduleExpiry(PlanSnapshot snapshot) {
    _expiryTimer?.cancel();
    if (snapshot.status == PlanStatus.expired) return;

    // +1s buffer so we fire just *past* the boundary, where status() reads as expired.
    final fireIn = snapshot.remaining + const Duration(seconds: 1);
    _expiryTimer = Timer(fireIn, _onWindowEnded);
  }

  /// Fired when the current window should have ended. Re-checks the backend (the user may have
  /// renewed elsewhere), then emits a fresh snapshot — a real state change that makes the router
  /// re-evaluate and gate an expired user to the activation screen immediately.
  Future<void> _onWindowEnded() async {
    final current = state.value;
    if (current == null) return;

    PlanSnapshot next;
    try {
      next = await ref.read(subscriptionApiProvider).status();
      await ref.read(sessionStorageProvider).savePlan(next.toJson());
    } catch (_) {
      // Offline: re-anchor the existing window to now so its status flips to expired locally.
      next = current.reanchored();
    }

    state = AsyncData(next);
    await _applyToNative(next);
    // If they renewed (now Pro/Trial again), arm the timer for the new boundary; if still expired,
    // _scheduleExpiry is a no-op, so this never busy-loops.
    _scheduleExpiry(next);
  }

  /// Re-pulls the plan status from the backend.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Redeems an activation code, flipping the user back to an active (Pro) plan.
  /// Throws [SubscriptionException] with a user-facing message on failure.
  Future<PlanSnapshot> redeem(String code) async {
    final fresh = await ref.read(subscriptionApiProvider).redeem(code);
    await ref.read(sessionStorageProvider).savePlan(fresh.toJson());
    state = AsyncData(fresh);
    await _applyToNative(fresh);
    // Arm the expiry fire for the newly-opened Pro window so it, too, auto-gates when it lapses.
    _scheduleExpiry(fresh);
    return fresh;
  }

  /// Pushes the plan window to the native forwarder: when active, the instant it
  /// stays valid through; when expired, a hard stop so no USSD / SMS-check runs.
  Future<void> _applyToNative(PlanSnapshot snapshot) async {
    if (!Platform.isAndroid) return;
    const channel = ForwardingChannel();
    try {
      if (snapshot.status == PlanStatus.expired) {
        // Stand the forwarder down entirely (disables the enabled flag + tears
        // down the poller/SMS path), then mark the plan inactive natively.
        await channel.stopForwarding();
        await channel.setPlanActive(active: false, activeUntilEpochMs: 0);
      } else {
        final until = snapshot.activeUntilUtc?.millisecondsSinceEpoch ?? 0;
        await channel.setPlanActive(active: true, activeUntilEpochMs: until);
      }
    } on PlatformException {
      // Best-effort — a native hiccup must never break the plan flow.
    } on MissingPluginException {
      // Channel unavailable (e.g. tests) — ignore.
    }
  }
}
