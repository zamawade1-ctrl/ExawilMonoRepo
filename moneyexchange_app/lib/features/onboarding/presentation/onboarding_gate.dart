import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accessibility/presentation/accessibility_guide_dialog.dart';
import '../../accessibility/presentation/overlay_guide_dialog.dart';
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
/// The accessibility (auto-type PIN) service can't be granted by a runtime
/// dialog — Android only exposes it through Settings — so right after the
/// runtime prompts, if it isn't on yet, this shows the [AccessibilityGuideDialog]
/// asking the user to enable it (and, on accept, opens the Accessibility
/// settings). This runs on every entry to the home shell, so a user who hasn't
/// enabled the service yet is re-asked via the same dialog next launch — there
/// is no standalone Accessibility page anymore. iOS has no on-device forwarder,
/// so nothing is requested there.
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
  /// A returning user who's already granted everything is never prompted.
  /// Best-effort: any failure is swallowed; the same dialogs are re-shown on the
  /// next entry to the home shell while a permission is still off.
  Future<void> _runFirstRunSetup() async {
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
      // Ignore — the guide dialogs are re-shown on the next entry to the home
      // shell while a permission is still off.
    }
  }

  @override
  Widget build(BuildContext context) => const HomeShell();
}
