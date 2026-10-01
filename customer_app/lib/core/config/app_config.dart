class AppConfig {
  static const String baseUrl = 'https://staging.saiberwifi.net/api';
  static const String appName = 'سايبر WiFi تجريبي';
  static const String appType = 'customer_app';
  static const String appVersion = '2.0.0-staging';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static const String tokenKey = 'auth_token';
  static const String userKey  = 'auth_user';

  static const String hiveAuthBox          = 'c_auth_box';
  static const String hiveDashboardBox     = 'c_dashboard_box';
  static const String hiveNetworksBox      = 'c_networks_box';
  static const String hiveWalletBox        = 'c_wallet_box';
  static const String hiveTransactionsBox  = 'c_transactions_box';
  static const String hiveNotificationsBox = 'c_notifications_box';
  static const String hiveCardsBox         = 'c_cards_box';
  static const String hiveMessagesBox      = 'c_messages_box';
  static const String hiveMaintenanceBox   = 'c_maintenance_box';
}
