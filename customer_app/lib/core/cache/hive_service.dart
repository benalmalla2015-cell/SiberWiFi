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
    await Hive.openBox(AppConfig.hiveWalletBox);
    await Hive.openBox(AppConfig.hiveTransactionsBox);
    await Hive.openBox(AppConfig.hiveNotificationsBox);
    await Hive.openBox(AppConfig.hiveCardsBox);
    await Hive.openBox(AppConfig.hiveMessagesBox);
    await Hive.openBox(AppConfig.hiveMaintenanceBox);
  }

  static Box<UserModel> get authBox         => Hive.box<UserModel>(AppConfig.hiveAuthBox);
  static Box            get dashboardBox    => Hive.box(AppConfig.hiveDashboardBox);
  static Box            get networksBox     => Hive.box(AppConfig.hiveNetworksBox);
  static Box            get walletBox       => Hive.box(AppConfig.hiveWalletBox);
  static Box            get transactionsBox => Hive.box(AppConfig.hiveTransactionsBox);
  static Box            get notificationsBox=> Hive.box(AppConfig.hiveNotificationsBox);
  static Box            get cardsBox        => Hive.box(AppConfig.hiveCardsBox);
  static Box            get messagesBox     => Hive.box(AppConfig.hiveMessagesBox);
  static Box            get maintenanceBox  => Hive.box(AppConfig.hiveMaintenanceBox);

  static UserModel? getUser()                     => authBox.get('current_user');
  static Future<void> saveUser(UserModel u)        => authBox.put('current_user', u);
  static Future<void> clearUser()                  => authBox.clear();

  static Future<void> clearAll() async {
    await authBox.clear();
    await dashboardBox.clear();
    await networksBox.clear();
    await walletBox.clear();
    await transactionsBox.clear();
    await notificationsBox.clear();
    await cardsBox.clear();
    await messagesBox.clear();
    await maintenanceBox.clear();
  }
}
