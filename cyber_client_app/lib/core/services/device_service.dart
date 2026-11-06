import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'subscriber_store.dart';

/// Device identity for the CYB-04/05 binding contract: sim_no +
/// device_id IS the subscriber credential (cyber_identities).
///
/// Android: ANDROID_ID read through the app channel (stable per device,
/// survives reinstall — device_info_plus dropped it for Play policy).
/// iOS:     identifierForVendor.
/// Fallback: a UUID generated once and persisted.
class DeviceService {
  static const _uuid = Uuid();
  static const _channel = MethodChannel('cyber.net/wifi');

  static Future<String> deviceId() async {
    if (Platform.isAndroid) {
      try {
        final raw = await _channel.invokeMethod<String>('deviceId');
        if (raw != null && raw.isNotEmpty) return 'and-$raw';
      } catch (_) {/* fall through */}
    }
    try {
      if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        final raw = i.identifierForVendor ?? '';
        if (raw.isNotEmpty) return 'ios-$raw';
      }
    } catch (_) {/* fall through */}

    var id = await SubscriberStore.read('device_uuid');
    if (id == null || id.isEmpty) {
      id = 'dev-${_uuid.v4()}';
      await SubscriberStore.write('device_uuid', id);
    }
    return id;
  }

  /// FCM registration token — best-effort. null where Firebase is not
  /// available (unregistered package, no Play Services); the bind
  /// endpoint accepts a missing token.
  static Future<String?> fcmToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }
}
