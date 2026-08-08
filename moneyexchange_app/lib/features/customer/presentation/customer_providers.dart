import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/customer_api.dart';
import '../domain/customer_profile.dart';

final customerApiProvider = Provider(
  (ref) => CustomerApi(dio: ref.watch(apiClientProvider).dio),
);

/// The signed-in user's forwarding profile - null means they haven't set one up yet.
final customerProfileControllerProvider =
    AsyncNotifierProvider<CustomerProfileController, CustomerProfile?>(
      CustomerProfileController.new,
    );

class CustomerProfileController extends AsyncNotifier<CustomerProfile?> {
  @override
  Future<CustomerProfile?> build() {
    return ref.read(customerApiProvider).getMyProfile();
  }

  /// Saves the profile and, on success, updates the held value in place.
  ///
  /// Crucially this does NOT flip [state] to loading/error around the call:
  /// the widget tree gates the whole card on this provider's state, so a
  /// transient save failure must not replace the form with the "couldn't load"
  /// card. It throws instead, letting the caller show a snackbar while the form
  /// (and everything the user just typed) stays on screen.
  Future<CustomerProfile> save(ForwardingProfileInput input) async {
    final saved = await ref.read(customerApiProvider).saveMyProfile(input);
    state = AsyncData(saved);
    return saved;
  }

  /// Re-fetches the profile from the backend (for pull-to-refresh).
  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(customerApiProvider).getMyProfile(),
    );
  }
}
