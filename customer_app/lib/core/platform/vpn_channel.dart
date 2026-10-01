import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/vpn_state.dart';

const _methodChannel = MethodChannel('com.saiberwifi.customerapp/vpn');
const _eventChannel = EventChannel('com.saiberwifi.customerapp/vpn_stats');

/// Bridge to the native "محرك تسريع الشبكة" (network booster) VPN engine,
/// ported from the aden_data app. Mirrors its MethodChannel/EventChannel API.
class VpnChannel {
  const VpnChannel._();

  static Future<bool> startVpn({
    required List<String> allowedPackages,
    required String profile,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('startVpn', {
        'allowedPackages': allowedPackages,
        'profile': profile,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> stopVpn() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopVpn');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<List<AppInfo>> getInstalledApps() async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
      );
      return (result ?? []).map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return AppInfo.fromMap(map);
      }).toList();
    } on PlatformException {
      return [];
    }
  }

  static Stream<VpnStats> get liveStats {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return VpnStats.fromMap(map);
    });
  }
}

class AppInfo {
  final String packageName;
  final String appName;
  final String? iconBase64;

  const AppInfo({
    required this.packageName,
    required this.appName,
    this.iconBase64,
  });

  factory AppInfo.fromMap(Map<String, dynamic> map) => AppInfo(
    packageName: map['pkg'] as String,
    appName: map['name'] as String,
    iconBase64: map['icon'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is AppInfo && other.packageName == packageName;

  @override
  int get hashCode => packageName.hashCode;
}

final vpnChannelProvider = Provider<VpnChannel>((_) => const VpnChannel._());
