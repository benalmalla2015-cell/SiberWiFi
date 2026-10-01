import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/cache/hive_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/api/api_client.dart';
import 'core/config/app_config.dart';
import 'core/config/router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/dashboard/presentation/providers/dashboard_provider.dart';
import 'features/maintenance/presentation/providers/maintenance_mode_provider.dart';
import 'features/maintenance/presentation/screens/account_suspended_screen.dart';
import 'features/maintenance/presentation/screens/maintenance_mode_screen.dart';
import 'features/networks/presentation/providers/networks_provider.dart';
import 'features/notifications/presentation/screens/notifications_screen.dart';
import 'features/payouts/presentation/screens/payouts_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try { await Firebase.initializeApp(); } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    // Suppress known framework assertion about _dependents during disposal
    final msg = details.exceptionAsString();
    if (msg.contains('_dependents.isEmpty')) return;
    debugPrint('[FlutterError] $msg');
  };

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // App is light-only — prevent Android Force Dark / system dark mode
  // from graying white form surfaces (login fields, cards, etc.).
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  await HiveService.init();
  await LocalNotificationService.initialize();

  // Firebase — non-fatal, app works without it
  bool firebaseOk = false;
  try {
    await Firebase.initializeApp();
    firebaseOk = true;
  } catch (e) {
    debugPrint('[Firebase] init failed: $e');
  }

  if (firebaseOk) {
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );
      // Foreground FCM handling moved to SaiberWifiApp so it can access Riverpod providers.
    } catch (e) {
      debugPrint('[FCM] setup failed: $e');
    }
  }

  runApp(const ProviderScope(child: SaiberWifiApp()));
}

class SaiberWifiApp extends ConsumerStatefulWidget {
  const SaiberWifiApp({super.key});

  @override
  ConsumerState<SaiberWifiApp> createState() => _SaiberWifiAppState();
}

class _SaiberWifiAppState extends ConsumerState<SaiberWifiApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _accountSuspended = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = ref.read(routerProvider);
    LocalNotificationService.onTap = _onNotificationTap;
    ApiClient.onSuspended = _showSuspendedScreen;
    ApiClient.onUnauthorized = _handleUnauthorized;
    _setupFcmListeners();
    _checkInitialMessage();
  }

  void _setupFcmListeners() {
    _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      final title = notification?.title ?? message.data['title']?.toString();
      final body = notification?.body ?? message.data['body']?.toString();
      if (title?.isNotEmpty == true || body?.isNotEmpty == true) {
        LocalNotificationService.show(
          title: title?.isNotEmpty == true ? title! : 'سايبر WiFi',
          body: body ?? '',
          imageUrl: message.data['image']?.toString(),
          payload: message.data,
        );
      }
      _onFcmDataReceived(message.data);
    });
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _onFcmDataReceived(message.data);
      _navigateForNotification(message.data);
    });

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (newToken) async {
        try {
          await ref.read(apiClientProvider).post('/auth/fcm-token', data: {'fcm_token': newToken});
        } catch (e) {
          debugPrint('[FCM] token refresh sync failed: $e');
        }
      },
    );
  }

  /// Handles a notification tap when the app was terminated.
  void _checkInitialMessage() {
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message == null) return;
      _onFcmDataReceived(message.data);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateForNotification(message.data);
      });
    });
  }

  void _onNotificationTap(Map<String, dynamic> data) {
    _onFcmDataReceived(data);
    _navigateForNotification(data);
  }

  void _navigateForNotification(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    String route = '/notifications';
    if (type.startsWith('payout_')) {
      route = '/payouts';
    } else if (type.startsWith('network_') ||
        type == 'low_stock' ||
        type == 'card_sold' ||
        type.startsWith('advance_')) {
      route = '/networks';
    } else if (type == 'chat_message') {
      route = '/conversations';
    } else if (type.startsWith('charging_point')) {
      route = '/charging-points';
    } else if (type == 'new_rating' || type == 'rating_reply') {
      route = '/reviews';
    } else if (type == 'new_report' || type == 'report_reply') {
      route = '/reports';
    }
    try {
      _router.go(route);
    } catch (_) {}
  }

  void _onFcmDataReceived(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';

    // Always refresh notifications list so the in-app screen stays current
    ref.invalidate(notificationsProvider);

    // Account suspension / activation (sent from the admin panel)
    if (type == 'account_suspended') {
      _showSuspendedScreen();
      return;
    }
    if (type == 'account_activated') {
      if (_accountSuspended && mounted) {
        setState(() => _accountSuspended = false);
      }
      ref.read(authProvider.notifier).refreshUser();
      return;
    }

    // Maintenance mode toggle
    if (type == 'maintenance_mode') {
      ref.read(maintenanceModeProvider.notifier).fetch();
      return;
    }

    // Balance / payout / earnings related events
    if (type == 'payout_approved' ||
        type == 'payout_paid' ||
        type == 'payout_rejected' ||
        type == 'purchase' ||
        type == 'credit' ||
        type == 'debit' ||
        type.startsWith('wallet_') ||
        type.startsWith('topup_')) {
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(payoutsProvider);
      ref.read(authProvider.notifier).refreshUser();
    }

    // Network approval / rejection
    if (type == 'network_approved' || type == 'network_rejected') {
      ref.read(authProvider.notifier).refreshUser();
      ref.invalidate(dashboardDataProvider);
    }

    // Chat, rating, report events
    if (type == 'chat_message' ||
        type == 'new_rating' ||
        type == 'new_report' ||
        type == 'report_reply') {
      ref.invalidate(dashboardDataProvider);
    }

    // Stock / sales / charging point / advance / support events
    if (type == 'low_stock' ||
        type == 'card_sold' ||
        type.startsWith('charging_point') ||
        type.startsWith('advance_') ||
        type == 'support_ticket' ||
        type == 'support_ticket_reply') {
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(networksProvider);
    }

    // For any unrecognized type, still refresh dashboard + profile
    if (type.isEmpty) {
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(payoutsProvider);
      ref.read(authProvider.notifier).refreshUser();
    }
  }

  void _showSuspendedScreen() {
    ref.read(authProvider.notifier).logout();
    if (mounted) {
      setState(() => _accountSuspended = true);
    }
  }

  /// The stored token was revoked (401) — e.g. the same account logged in on
  /// another device, which deletes all previous tokens. Drop the dead session
  /// and let the router send the user back to the login screen.
  void _handleUnauthorized() {
    if (_accountSuspended) return;
    if (ref.read(authProvider).status != AuthStatus.authenticated) return;
    ref.read(authProvider.notifier).logout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh all live data when the user returns to the app
      ref.invalidate(notificationsProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(payoutsProvider);
      ref.read(authProvider.notifier).refreshUser();
      ref.read(maintenanceModeProvider.notifier).fetch();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(LocalNotificationService.onTap, _onNotificationTap)) {
      LocalNotificationService.onTap = null;
    }
    if (identical(ApiClient.onSuspended, _showSuspendedScreen)) {
      ApiClient.onSuspended = null;
    }
    if (identical(ApiClient.onUnauthorized, _handleUnauthorized)) {
      ApiClient.onUnauthorized = null;
    }
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _tokenRefreshSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    final maintenance = ref.watch(maintenanceModeProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      theme: AppTheme.theme,
      themeMode: ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'YE'),
      supportedLocales: const [Locale('ar', 'YE'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // Force light MediaQuery so widgets never inherit dark platform brightness.
        final mq = MediaQuery.of(context);
        Widget body = MediaQuery(
          data: mq.copyWith(platformBrightness: Brightness.light),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        );
        if (_accountSuspended) {
          body = const AccountSuspendedScreen();
        } else if (maintenance.isActive) {
          body = MaintenanceModeScreen(
            title: maintenance.title,
            description: maintenance.description,
            image: maintenance.image,
            onRetry: () => ref.read(maintenanceModeProvider.notifier).fetch(),
          );
        }
        return body;
      },
    );
  }
}
