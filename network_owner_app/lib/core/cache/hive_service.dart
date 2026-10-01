import 'package:hive_flutter/hive_flutter.dart';
import '../config/app_config.dart';
import '../models/user_model.dart';

class HiveService {
  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(UserModelAdapter());

    await Hive.openBox<UserModel>(AppConfig.hiveAuthBox);
    await Hive.openBox(AppConfig.hiveDashboardBox);
    await Hive.openBox(AppConfig.hiveNetworksBox);
    await Hive.openBox(AppConfig.hiveTransactionsBox);
    await Hive.openBox(AppConfig.hivePayoutsBox);
    await Hive.openBox(AppConfig.hiveNotificationsBox);
    await Hive.openBox(AppConfig.hiveMaintenanceBox);
  }

  static Box<UserModel> get authBox =>
      Hive.box<UserModel>(AppConfig.hiveAuthBox);

  static Box get dashboardBox =>
      Hive.box(AppConfig.hiveDashboardBox);

  static Box get networksBox =>
      Hive.box(AppConfig.hiveNetworksBox);

  static Box get transactionsBox =>
      Hive.box(AppConfig.hiveTransactionsBox);

  static Box get payoutsBox =>
      Hive.box(AppConfig.hivePayoutsBox);

  static Box get notificationsBox =>
      Hive.box(AppConfig.hiveNotificationsBox);

  static Box get maintenanceBox =>
      Hive.box(AppConfig.hiveMaintenanceBox);

  static UserModel? getUser() => authBox.get('current_user');

  static Future<void> saveUser(UserModel user) =>
      authBox.put('current_user', user);

  static Future<void> clearUser() => authBox.clear();

  static Future<void> clearAll() async {
    await authBox.clear();
    await dashboardBox.clear();
    await networksBox.clear();
    await transactionsBox.clear();
    await payoutsBox.clear();
    await notificationsBox.clear();
    await maintenanceBox.clear();
  }

  static Map<String, dynamic>? getPayoutDetails() {
    final box = Hive.box(AppConfig.hiveAuthBox);
    return box.get('payout_details');
  }

  static Future<void> savePayoutDetails(Map<String, dynamic> data) async {
    final box = Hive.box(AppConfig.hiveAuthBox);
    await box.put('payout_details', data);
  }
}
