import 'package:flutter_test/flutter_test.dart';
import 'package:moneyexchange_app/features/security/presentation/require_app_pin.dart';

void main() {
  group('shouldRequireAppPin', () {
    test('no PIN anywhere → no gate', () {
      expect(
        shouldRequireAppPin(hasAppPin: false, hasLocalPin: false),
        isFalse,
      );
    });

    test('app-lock on (backend hasAppPin) → gate', () {
      expect(
        shouldRequireAppPin(hasAppPin: true, hasLocalPin: false),
        isTrue,
      );
    });

    test(
      'app-lock turned OFF but a local PIN copy remains → STILL gate '
      '(the whole point: forwarding stays protected after the lock is off)',
      () {
        expect(
          shouldRequireAppPin(hasAppPin: false, hasLocalPin: true),
          isTrue,
        );
      },
    );

    test('both present → gate', () {
      expect(
        shouldRequireAppPin(hasAppPin: true, hasLocalPin: true),
        isTrue,
      );
    });
  });
}
