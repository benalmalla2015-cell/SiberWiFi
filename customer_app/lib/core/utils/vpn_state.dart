import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/vpn_channel.dart';

/// Bandwidth-focus profile for the "محرك تسريع الشبكة" feature.
enum VpnProfile { cellular, weakWifi }

extension VpnProfileX on VpnProfile {
  String get id {
    switch (this) {
      case VpnProfile.cellular:
        return 'CELLULAR';
      case VpnProfile.weakWifi:
        return 'WEAK_WIFI';
    }
  }

  String get label {
    switch (this) {
      case VpnProfile.cellular:
        return 'بيانات محدودة';
      case VpnProfile.weakWifi:
        return 'واي فاي ضعيف';
    }
  }

  String get description {
    switch (this) {
      case VpnProfile.cellular:
        return 'يركّز النطاق الترددي المتاح على التطبيق المختار عبر بيانات الجوال';
      case VpnProfile.weakWifi:
        return 'يثبّت اتصال التطبيق المختار عند ضعف إشارة الواي فاي';
    }
  }
}

class VpnStats {
  final double downKbps;
  final double upKbps;
  final int latencyMs;

  const VpnStats({this.downKbps = 0, this.upKbps = 0, this.latencyMs = 0});

  factory VpnStats.fromMap(Map<String, dynamic> map) => VpnStats(
    downKbps: (map['down_kbps'] as num?)?.toDouble() ?? 0,
    upKbps: (map['up_kbps'] as num?)?.toDouble() ?? 0,
    latencyMs: (map['latency'] as num?)?.toInt() ?? 0,
  );
}

class VpnState {
  final bool isActive;
  final VpnProfile activeProfile;
  final AppInfo? targetApp;
  final bool isLoading;

  const VpnState({
    this.isActive = false,
    this.activeProfile = VpnProfile.cellular,
    this.targetApp,
    this.isLoading = false,
  });

  VpnState copyWith({
    bool? isActive,
    VpnProfile? activeProfile,
    AppInfo? targetApp,
    bool? isLoading,
    bool clearTarget = false,
  }) => VpnState(
    isActive: isActive ?? this.isActive,
    activeProfile: activeProfile ?? this.activeProfile,
    targetApp: clearTarget ? null : (targetApp ?? this.targetApp),
    isLoading: isLoading ?? this.isLoading,
  );
}

class VpnNotifier extends StateNotifier<VpnState> {
  VpnNotifier() : super(const VpnState());

  Future<String?> toggle() async {
    if (state.isLoading) return null;
    if (!state.isActive && state.targetApp == null) {
      return 'اختر التطبيق المستهدف أولاً';
    }
    state = state.copyWith(isLoading: true);

    if (state.isActive) {
      await VpnChannel.stopVpn();
      state = state.copyWith(isActive: false, isLoading: false);
      return null;
    }

    final ok = await VpnChannel.startVpn(
      allowedPackages: [state.targetApp!.packageName],
      profile: state.activeProfile.id,
    );
    state = state.copyWith(isActive: ok, isLoading: false);
    return ok ? null : 'تعذّر تشغيل المحرك — قد تحتاج للموافقة على إذن VPN';
  }

  void setProfile(VpnProfile profile) {
    state = state.copyWith(activeProfile: profile);
  }

  void setTargetApp(AppInfo app) {
    state = state.copyWith(targetApp: app);
  }
}

final vpnProvider = StateNotifierProvider<VpnNotifier, VpnState>(
  (_) => VpnNotifier(),
);

final liveVpnStatsProvider = StreamProvider.autoDispose<VpnStats>(
  (_) => VpnChannel.liveStats,
);
