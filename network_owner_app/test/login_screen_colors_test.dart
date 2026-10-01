import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_owner_app/core/theme/app_theme.dart';
import 'package:network_owner_app/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen renders with opaque white surfaces (not gray)',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          themeMode: ThemeMode.light,
          home: LoginScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('رقم الهاتف'), findsOneWidget);
    expect(find.text('كلمة المرور'), findsOneWidget);
    expect(find.text('دخول'), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.primary);

    // The body's opaque background Container must be pure white (not grey).
    final containers = tester.widgetList<Container>(find.byType(Container));
    expect(
      containers.any((c) => c.color == Colors.white),
      isTrue,
      reason: 'Login body Container must be pure white',
    );

    // No ClipRRect / BoxShadow / Material-elevation card wrapper anymore.
    expect(find.byType(ClipRRect), findsNothing);

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.length, greaterThanOrEqualTo(2));
    for (final f in fields) {
      expect(f.decoration?.fillColor, Colors.white);
      expect(f.decoration?.filled, isTrue);
    }
  });
}
