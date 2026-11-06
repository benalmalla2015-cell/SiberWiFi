import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyber_client_app/main.dart';

void main() {
  testWidgets('app boots to the registration gate without a stored SIM',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CyberApp());
    await tester.pumpAndSettle();
    expect(find.text('سايبر نت'), findsWidgets);
  });
}
