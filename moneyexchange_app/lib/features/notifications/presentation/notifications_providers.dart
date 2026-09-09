import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../forwarding/data/forwarding_channel.dart';
import '../domain/destination_change.dart';

/// The deep-link route the native side emits when the destination-change
/// notification is tapped. Matches `DestinationChangeNotifications.ROUTE_*`.
const String kDestinationChangeRoute = 'destination_change';

/// Deep-link route events from the native side (e.g. a tapped notification). A
/// route that arrived before this is listened is buffered natively and delivered
/// on first subscription, so a notification tapped while the app was closed still
/// reaches the app once it starts. Empty off Android.
final navigationEventProvider = StreamProvider<String>((ref) {
  return const ForwardingChannel().navigationEvents();
});

/// The on-device destination-change audit trail, newest first. This is a SEPARATE
/// store from the money ledger (it reads the native change log, not
/// TransactionStore), so it never affects dashboard Received/Forwarded totals.
final destinationChangeLogProvider =
    AsyncNotifierProvider<DestinationChangeLogController, List<DestinationChange>>(
      DestinationChangeLogController.new,
    );

class DestinationChangeLogController
    extends AsyncNotifier<List<DestinationChange>> {
  static const _channel = ForwardingChannel();

  @override
  Future<List<DestinationChange>> build() => _load();

  Future<List<DestinationChange>> _load() async {
    if (!Platform.isAndroid) return const [];
    final raw = await _channel.getDestinationChangeLog();
    final list = raw.map(DestinationChange.fromMap).toList()
      // Native stores oldest-first; show newest-first.
      ..sort((a, b) => b.atMs.compareTo(a.atMs));
    return list;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}
