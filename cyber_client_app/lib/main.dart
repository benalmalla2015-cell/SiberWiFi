import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/config/app_config.dart';
import 'core/services/security_service.dart';
import 'core/services/subscriber_store.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/register_screen.dart';

/// CyberNet client (CYB-05) — digital-SIM app for the saiberwifi pilot.
/// Registration issues the permanent 74XXXXXXX number; the enrolled
/// device (ANDROID_ID) is the billing credential; «تفعيل» installs the
/// CyberNet Wi-Fi profile so the phone auto-joins any CyberNet AP.
void main() {
  runZonedGuarded(_bootstrap, (e, s) => debugPrint('[ZoneError] $e'));
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final tamperReason = await SecurityService.gate(); // CYB-14 integrity gate
  await _initFirebase();
  runApp(tamperReason == null
      ? const CyberApp()
      : TamperedApp(reason: tamperReason));
}

/// The cyber package is not in google-services.json — initialise the
/// shared project manually (credentials in AppConfig). Fully guarded:
/// the app works, and identity/bind degrades to a null fcm_token, where
/// Firebase is unreachable.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseAppId,
        messagingSenderId: AppConfig.firebaseSenderId,
        projectId: AppConfig.firebaseProjectId,
      ),
    );
    await FirebaseMessaging.instance.requestPermission();
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  } catch (e) {
    debugPrint('[Firebase] init skipped: $e');
  }
}

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseAppId,
        messagingSenderId: AppConfig.firebaseSenderId,
        projectId: AppConfig.firebaseProjectId,
      ),
    );
  } catch (_) {}
}

class CyberApp extends StatelessWidget {
  const CyberApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: CyberTheme.theme,
      locale: const Locale('ar', 'YE'),
      supportedLocales: const [Locale('ar', 'YE'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _Gate(),
    );
  }
}

/// Shown when the CYB-14 integrity gate fails (re-signed APK, root,
/// or hooking tools). No navigation — the app cannot proceed.
class TamperedApp extends StatelessWidget {
  const TamperedApp({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 72, color: Colors.red),
                  const SizedBox(height: 24),
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Routes to registration or home depending on a stored SIM number.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: SubscriberStore.simNo(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return (snap.data == null) ? const RegisterScreen() : const HomeScreen();
      },
    );
  }
}
