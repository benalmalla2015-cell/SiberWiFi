class AppConfig {
  static const String baseUrl = 'https://saiberwifi.net/api';
  static const String appName = 'سايبر WiFi';
  static const String appType = 'network_owner_app';
  static const String appVersion = '1.0.0+1';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static const String tokenKey = 'auth_token';
  static const String userKey  = 'auth_user';

  static const String hiveAuthBox        = 'auth_box';
  static const String hiveDashboardBox   = 'dashboard_box';
  static const String hiveNetworksBox    = 'networks_box';
  static const String hiveTransactionsBox = 'network_owner_transactions_box';
  static const String hivePayoutsBox     = 'payouts_box';
  static const String hiveNotificationsBox = 'notifications_box';
  static const String hiveMaintenanceBox = 'maintenance_box';
}
