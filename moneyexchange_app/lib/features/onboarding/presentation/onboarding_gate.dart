import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accessibility/presentation/accessibility_guide_dialog.dart';
import '../../accessibility/presentation/overlay_guide_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../forwarding/data/forwarding_channel.dart';
import '../../forwarding/presentation/forwarding_providers.dart';
import '../../home/presentation/home_shell.dart';

/// Thin wrapper that lands the signed-in user **straight on [HomeShell]** — there
/// is no full-screen permission-onboarding page anymore.
///
/// Instead, on the first launch on Android (when the runtime permissions aren't
/// yet granted), it fires the OS's own **"Allow / Don't allow" runtime-permission
/// dialogs** for SMS / phone / SIM — the native prompts — rather than a bespoke
/// checklist screen. The app is never blocked behind setup: the user can use it
/// immediately and grant (or decline) via the system dialogs.
///
/// The accessibility (auto-type PIN) service and the "display over other apps"
/// overlay can't be granted by a runtime dialog — Android only exposes them
/// through Settings — so right after the runtime prompts, if either is off, this
/// shows a guide dialog asking the user to enable it (and, on accept, opens the
/// relevant settings). This whole guided flow runs **once per install**, the
/// first time someone signs up and starts using the app (tracked via
/// [SessionStorage.hasShownFirstRunGuides]); it deliberately does NOT re-pop on
/// later launches. A still-missing permission is surfaced afterwards by the
/// Forwarding mode card's tappable banner instead, which opens the right settings
/// on tap. iOS has no on-device forwarder, so nothing is requested there.
class HomeGate extends ConsumerStatefulWidget {
  const HomeGate({super.key});

  @override
  ConsumerState<HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends ConsumerState<HomeGate> {
  static const _channel = ForwardingChannel();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      // Run the first-run permission flow once, after the first frame so the
      // Activity is attached and can host the system prompt / dialog.
      WidgetsBinding.instance.addPostFrameCallback((_) => _runFirstRunSetup());
    }
  }

  /// First-run permission flow, in order:
  ///   1. Fire the system "Allow / Don't allow" prompts for the SMS/phone/SIM
  ///      runtime permissions (only if any is still missing), and await the
  ///      user's response — the native side holds the call open until then.
  ///   2. Then, if the auto-type PIN accessibility service isn't on, ask the
  ///      user to enable it via the [AccessibilityGuideDialog] and open the
  ///      Accessibility settings on accept.
  ///   3. Finally, if the "display over other apps" overlay isn't granted (also
  ///      Settings-only — the forwarder draws the USSD auto-fill overlay on top
  ///      of the dialer), ask via the [OverlayGuideDialog] and open the overlay
  ///      settings on accept.
  /// Runs at most **once per install**: gated on [SessionStorage.hasShownFirstRunGuides]
  /// so the guided dialogs (and the system overlay/accessibility settings they
  /// open) never re-pop on later launches — the earlier behaviour of re-showing
  /// them on every home entry is what made "display over other apps" keep
  /// re-appearing. Afterwards, a still-missing permission is nudged via the
  /// Forwarding mode card's tappable banner. Best-effort: any failure is
  /// swallowed, and the one-shot flag is still set so we don't loop.
  Future<void> _runFirstRunSetup() async {
    final sessionStorage = ref.read(sessionStorageProvider);
    if (await sessionStorage.hasShownFirstRunGuides()) return;
    try {
      var status = await _channel.getStatus();
      final needsRuntime = !(status.hasSmsPermission &&
          status.hasCallPermission &&
          status.hasPhoneStatePermission);
      if (needsRuntime) {
        await _channel.requestPermissions(); // awaits the native dialogs now
        if (!mounted) return;
        await ref.read(nativeForwardingProvider.notifier).refresh();
        status = await _channel.getStatus();
      }

      // Ask for the auto-type PIN accessibility service (Settings-only, so no
      // runtime dialog exists for it) once the runtime prompts are dealt with.
      if (!status.accessibilityEnabled && mounted) {
        if (await showAccessibilityGuide(context)) {
          await _channel.openAccessibilitySettings();
        }
      }
      if (!mounted) return;

      // Then the "display over other apps" overlay — same Settings-only nature,
      // and just as required for the forwarder to run. Re-read the status first
      // so a user who just granted it isn't asked again.
      status = await _channel.getStatus();
      if (!status.overlayEnabled && mounted) {
        if (await showOverlayGuide(context)) {
          await _channel.openOverlaySettings();
        }
      }
    } on PlatformException {
      // Ignore — a permission still off after this is surfaced by the Forwarding
      // mode card's tappable banner, not by re-popping this flow.
    } finally {
      // One-shot: mark the guides shown even on an early/error exit so the flow
      // never loops or re-pops on later launches.
      await sessionStorage.markFirstRunGuidesShown();
    }
  }

  @override
  Widget build(BuildContext context) => const HomeShell();
}
