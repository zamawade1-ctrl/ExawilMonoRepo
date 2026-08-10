import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moneyexchange_app/app.dart';

void main() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'read':
          return store[call.arguments['key']];
        case 'write':
          store[call.arguments['key'] as String] = call.arguments['value'] as String;
          return null;
        case 'delete':
          store.remove(call.arguments['key']);
          return null;
        case 'readAll':
          return store;
        default:
          return null;
      }
    });
  });

  testWidgets('shows the sign-in / sign-up form when signed out', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MoneyExchangeApp()));
    await tester.pumpAndSettle();

    // The mode toggle and the primary action button are both present.
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Sign up'), findsWidgets);
    expect(find.byType(TextFormField), findsWidgets);
  });
}
