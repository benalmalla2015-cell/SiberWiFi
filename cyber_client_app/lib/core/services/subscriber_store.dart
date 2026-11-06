import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence of the issued SIM identity. The subscriber has no
/// account — what lives here is all the app needs to act as the device.
class SubscriberStore {
  static const _kSimNo = 'sim_no';
  static const _kFullName = 'full_name';
  static const _kDeviceId = 'device_id';
  static const _kWifiSuggested = 'wifi_suggested';

  static Future<void> write(String key, String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
  }

  static Future<String?> read(String key) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(key);
  }

  static Future<void> saveSubscriber({
    required String simNo,
    required String fullName,
    required String deviceId,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSimNo, simNo);
    await p.setString(_kFullName, fullName);
    await p.setString(_kDeviceId, deviceId);
  }

  static Future<String?> simNo() async => read(_kSimNo);
  static Future<String?> fullName() async => read(_kFullName);
  static Future<String?> deviceId() async => read(_kDeviceId);

  static Future<bool> wifiSuggested() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kWifiSuggested) ?? false;
  }

  static Future<void> setWifiSuggested(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWifiSuggested, v);
  }

  /// For manual re-enrolment (testing / device change by ops).
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSimNo);
    await p.remove(_kFullName);
    await p.remove(_kDeviceId);
    await p.remove(_kWifiSuggested);
  }
}
