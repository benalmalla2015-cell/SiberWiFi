import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/cache/hive_service.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/home/presentation/providers/home_provider.dart';
import 'features/maintenance/presentation/providers/maintenance_mode_provider.dart';
import 'features/networks/presentation/providers/networks_provider.dart';
import 'features/maintenance/presentation/screens/account_suspended_screen.dart';
import 'features/maintenance/presentation/screens/maintenance_mode_screen.dart';
import 'features/notifications/presentation/screens/notifications_screen.dart';
import 'features/profile/presentation/screens/services_screen.dart';
import 'features/profile/presentation/screens/support_tickets_screen.dart';
import 'features/wallet/presentation/providers/wallet_provider.dart';
import 'core/api/api_client.dart';
import 'core/config/app_config.dart';
import 'core/config/router.dart';
import 'core/services/local_notification_service.dart';
import 'core/theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

void main() {
  runZonedGuarded(_bootstrap, (error, stack) {
    debugPrint('[ZoneError] $error');
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  ErrorWidget.builder = (details) => Material(
    color: Colors.white,
    child: SafeArea(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 16),
                const Text(
                  'حدث خطأ غير متوقع',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  kDebugMode
                      ? details.exceptionAsString()
                      : 'يرجى إعادة تشغيل التطبيق',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: AppColors.textGray,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text(
                    'إغلاق التطبيق',
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  await HiveService.init();
  await LocalNotificationService.initialize();

  bool firebaseOk = false;
  try {
    await Firebase.initializeApp();
    firebaseOk = true;
  } catch (e) {
    debugPrint('[Firebase] init failed: $e');
  }

  if (firebaseOk) {
    try {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
      // Foreground FCM handling moved to CustomerApp so it can access Riverpod providers.
    } catch (e) {
      debugPrint('[FCM] setup failed: $e');
    }
  }

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[ZoneError] $error');
    return true;
  };

  runApp(const ProviderScope(child: CustomerApp()));
}

class CustomerApp extends ConsumerStatefulWidget {
  const CustomerApp({super.key});

  @override
  ConsumerState<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends ConsumerState<CustomerApp>
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
    // Guarded: staging build may run without a registered Firebase app,
    // in which case FirebaseMessaging throws on access.
    try {
      _setupFcmListeners();
      _checkInitialMessage();
    } catch (e) {
      debugPrint('[FCM] listeners skipped: $e');
    }
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

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
      newToken,
    ) async {
      try {
        await ref
            .read(apiClientProvider)
            .post('/auth/fcm-token', data: {'fcm_token': newToken});
      } catch (e) {
        debugPrint('[FCM] token refresh sync failed: $e');
      }
    });
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
    if (type == 'support_ticket' || type == 'support_ticket_reply') {
      route = '/support';
    } else if (type.startsWith('topup_') ||
        type.startsWith('wallet_') ||
        type == 'purchase_complete' ||
        type == 'purchase' ||
        type == 'credit' ||
        type == 'debit' ||
        type == 'cashback' ||
        type.startsWith('referral')) {
      route = '/wallet';
    } else if (type == 'network_approved' ||
        type == 'network_rejected' ||
        type == 'new_rating' ||
        type == 'new_report') {
      route = '/networks';
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
      ref.read(authProvider.notifier).refreshProfile();
      return;
    }

    // Maintenance mode toggle
    if (type == 'maintenance_mode') {
      ref.read(maintenanceModeProvider.notifier).fetch();
      return;
    }

    if (type == 'daily_offer') {
      ref.invalidate(dailyOffersProvider);
      ref.invalidate(networkCardsProvider);
    }

    // Wallet / balance related events
    if (type.startsWith('topup_') ||
        type.startsWith('wallet_') ||
        type == 'credit' ||
        type == 'debit' ||
        type == 'purchase' ||
        type == 'purchase_complete' ||
        type == 'cashback' ||
        type == 'balance_charged' ||
        type == 'balance_deducted') {
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletTransactionsProvider);
      ref.invalidate(purchaseHistoryProvider);
      ref.read(authProvider.notifier).refreshProfile();
    }

    // Referral / earnings events
    if (type == 'referral_commission' ||
        type == 'referral' ||
        type.startsWith('referral_')) {
      ref.invalidate(referralProvider);
      ref.invalidate(walletBalanceProvider);
      ref.read(authProvider.notifier).refreshProfile();
    }

    if (type == 'support_ticket' || type == 'support_ticket_reply') {
      ref.invalidate(supportTicketsProvider);
    }

    // Chat, report, support ticket, rating — refresh profile
    if (type == 'chat_message' ||
        type == 'report_reply' ||
        type == 'support_ticket_reply' ||
        type == 'rating_reply' ||
        type == 'network_approved' ||
        type == 'network_rejected') {
      ref.read(authProvider.notifier).refreshProfile();
    }

    // For any unrecognized type, still refresh profile to catch all cases
    if (type.isEmpty) {
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(referralProvider);
      ref.read(authProvider.notifier).refreshProfile();
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
      // Refresh all live data when the user returns to the app so that
      // approvals/rejections done in the admin panel are reflected immediately.
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(dailyOffersProvider);
      ref.invalidate(networkCardsProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(referralProvider);
      ref.invalidate(supportTicketsProvider);
      ref.read(authProvider.notifier).refreshProfile();
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
        final mq = MediaQuery.of(context);
        Widget body = MediaQuery(
          data: mq.copyWith(platformBrightness: Brightness.light),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const LoginScreen(),
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
