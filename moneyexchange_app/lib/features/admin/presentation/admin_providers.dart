import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/admin_api.dart';
import '../domain/admin_models.dart';

final adminApiProvider = Provider(
  (ref) => AdminApi(dio: ref.watch(apiClientProvider).dio),
);

/// The list of all users + their plans for the admin dashboard. Re-fetch with `ref.invalidate`.
final adminUsersProvider = FutureProvider<List<AdminUser>>(
  (ref) => ref.watch(adminApiProvider).listUsers(),
);
