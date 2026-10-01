import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_owner_app/features/maintenance/presentation/providers/maintenance_mode_provider.dart';
import 'package:network_owner_app/features/maintenance/presentation/screens/maintenance_mode_screen.dart';

void main() {
  test('parses maintenance API state', () {
    final state = MaintenanceModeState.fromJson({
      'is_active': true,
      'title': 'صيانة مجدولة',
      'description': 'سنعود قريباً',
      'image': 'https://example.com/maintenance.png',
    });

    expect(state.isActive, isTrue);
    expect(state.title, 'صيانة مجدولة');
    expect(state.description, 'سنعود قريباً');
    expect(state.image, 'https://example.com/maintenance.png');
  });

  testWidgets('renders dynamic maintenance content', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MaintenanceModeScreen(
        title: 'صيانة مجدولة',
        description: 'سنعود قريباً',
      ),
    ));

    expect(find.text('صيانة مجدولة'), findsOneWidget);
    expect(find.text('سنعود قريباً'), findsOneWidget);
    expect(find.byIcon(Icons.construction), findsOneWidget);
    expect(find.text('إغلاق التطبيق'), findsOneWidget);
  });
}
