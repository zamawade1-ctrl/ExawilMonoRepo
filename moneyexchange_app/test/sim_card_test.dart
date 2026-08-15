import 'package:flutter_test/flutter_test.dart';
import 'package:moneyexchange_app/features/forwarding/data/forwarding_channel.dart';

void main() {
  SimCard sim({
    String displayName = 'SIM 1',
    String carrierName = 'Telesom',
    String? number,
  }) => SimCard(
    subscriptionId: 1,
    slotIndex: 0,
    displayName: displayName,
    carrierName: carrierName,
    number: number,
  );

  group('SimCard.label', () {
    test('joins a distinct name and carrier', () {
      expect(sim(displayName: 'SIM 1', carrierName: 'Telesom').label,
          'SIM 1 · Telesom');
    });

    test('shows the carrier once when name equals carrier', () {
      expect(sim(displayName: 'Telesom', carrierName: 'Telesom').label, 'Telesom');
      expect(sim(displayName: 'telesom', carrierName: 'Telesom').label, 'telesom');
    });

    test('falls back to the carrier when the name is blank', () {
      expect(sim(displayName: '', carrierName: 'Somtel').label, 'Somtel');
    });

    test('shows the name alone when there is no carrier', () {
      expect(sim(displayName: 'SIM 2', carrierName: '').label, 'SIM 2');
    });
  });

  group('SimCard.fromMap', () {
    test('keeps a non-empty number and nulls a blank one', () {
      expect(
        SimCard.fromMap({'subscriptionId': 3, 'number': '+252634480003'}).number,
        '+252634480003',
      );
      expect(SimCard.fromMap({'subscriptionId': 3, 'number': ''}).number, isNull);
      expect(SimCard.fromMap({'subscriptionId': 3}).number, isNull);
    });
  });
}
