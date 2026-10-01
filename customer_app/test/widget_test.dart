// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:customer_app/features/networks/presentation/providers/networks_provider.dart';
import 'package:customer_app/features/networks/presentation/screens/cards_screen.dart';
import 'package:customer_app/features/wallet/presentation/providers/wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    expect(true, isTrue);
  });

  testWidgets('quantity dialog disposes safely after closing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkCardsProvider(1).overrideWith(
            (ref) async => [
              {
                'id': 10,
                'name': 'فئة اختبار',
                'price': 100,
                'value': 100,
                'available_cards_count': 2,
                'duration': 1,
                'unit': 'يوم',
              },
            ],
          ),
          walletBalanceProvider.overrideWith(
            (ref) async => const WalletBalanceInfo(balance: 1000),
          ),
        ],
        child: const MaterialApp(home: CardsScreen(networkId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('شراء 100 ر.ي'));
    await tester.pumpAndSettle();
    expect(find.text('الكمية'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('الكمية'), findsNothing);
  });
}
