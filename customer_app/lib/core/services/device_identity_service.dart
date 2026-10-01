import 'package:flutter/services.dart';

class DeviceIdentityService {
  static const _channel = MethodChannel('com.saiberwifi.customerapp/device');

  static Future<String> getId() async {
    final id = await _channel.invokeMethod<String>('getDeviceId');
    if (id == null || id.isEmpty) {
      throw StateError('تعذر التحقق من هوية الجهاز');
    }
    return id;
  }
}
