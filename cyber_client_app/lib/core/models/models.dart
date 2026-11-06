/// API models for the CyberNet client app (CYB-05). All shapes mirror
/// the live contracts in backend routes/cyber/*.php + the shared
/// governorates endpoints consumed read-only from routes/api.php.
library;

class Governorate {
  const Governorate({required this.id, required this.name, this.region});
  final int id;
  final String name;
  final String? region;

  factory Governorate.fromJson(Map<String, dynamic> j) => Governorate(
        id: j['id'] as int,
        name: (j['name'] ?? '').toString(),
        region: j['region']?.toString(),
      );
}

class District {
  const District({required this.id, required this.name});
  final int id;
  final String name;

  factory District.fromJson(Map<String, dynamic> j) => District(
        id: j['id'] as int,
        name: (j['name'] ?? '').toString(),
      );
}

/// Response of POST /cyber/register — the issued SIM number.
class SimIssue {
  const SimIssue({required this.simNo, required this.fullName, required this.status});
  final String simNo;
  final String fullName;
  final String status;

  factory SimIssue.fromJson(Map<String, dynamic> j) {
    final d = j['data'] as Map<String, dynamic>;
    return SimIssue(
      simNo: d['sim_no'].toString(),
      fullName: (d['full_name'] ?? '').toString(),
      status: (d['status'] ?? '').toString(),
    );
  }
}

class CyberPackage {
  const CyberPackage({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.durationDays,
    required this.dataLimitGb,
    required this.price,
    this.rateLimit,
  });
  final int id;
  final String name;
  final String nameAr;
  final int durationDays;
  final double? dataLimitGb;
  final double price;
  final String? rateLimit;

  factory CyberPackage.fromJson(Map<String, dynamic> j) => CyberPackage(
        id: j['id'] as int,
        name: (j['name'] ?? '').toString(),
        nameAr: (j['name_ar'] ?? j['name'] ?? '').toString(),
        durationDays: j['duration_days'] as int? ?? 0,
        dataLimitGb: (j['data_limit_gb'] as num?)?.toDouble(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        rateLimit: j['rate_limit']?.toString(),
      );
}

/// Active subscription as returned by /cyber/subscriptions*.
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.id,
    required this.packageId,
    this.startsAt,
    this.endsAt,
    this.dataLimitBytes,
    required this.consumedBytes,
    required this.status,
    this.packageName,
    this.price,
  });
  final int id;
  final int packageId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? dataLimitBytes;
  final int consumedBytes;
  final String status;
  final String? packageName;
  final double? price;

  int? get remainingBytes =>
      dataLimitBytes == null ? null : (dataLimitBytes! - consumedBytes).clamp(0, dataLimitBytes!);

  double get usedFraction => (dataLimitBytes == null || dataLimitBytes == 0)
      ? 0
      : (consumedBytes / dataLimitBytes!).clamp(0.0, 1.0);

  int? get daysLeft =>
      endsAt?.difference(DateTime.now()).inDays.clamp(0, 9999);

  factory SubscriptionInfo.fromJson(Map<String, dynamic> j) => SubscriptionInfo(
        id: j['id'] as int? ?? 0,
        packageId: j['package_id'] as int? ?? 0,
        startsAt: DateTime.tryParse(j['starts_at']?.toString() ?? ''),
        endsAt: DateTime.tryParse(j['ends_at']?.toString() ?? ''),
        dataLimitBytes: (j['data_limit_bytes'] as num?)?.toInt(),
        consumedBytes: (j['consumed_bytes'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? '').toString(),
        packageName: j['package_name']?.toString(),
        price: (j['price'] as num?)?.toDouble(),
      );
}

/// Wallet + active subscription — GET /cyber/subscriptions/current.
class SubscriberStatus {
  const SubscriberStatus({required this.balance, this.subscription});
  final double balance;
  final SubscriptionInfo? subscription;
}

// ---------- activity log ----------

class TopupRecord {
  const TopupRecord({required this.amount, required this.status, this.at});
  final double amount;
  final String status;
  final DateTime? at;

  factory TopupRecord.fromJson(Map<String, dynamic> j) => TopupRecord(
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        status: (j['status'] ?? '').toString(),
        at: DateTime.tryParse(j['created_at']?.toString() ?? ''),
      );
}

class SessionRecord {
  const SessionRecord({
    this.host,
    this.startedAt,
    this.lastSeenAt,
    required this.totalOctets,
    required this.status,
  });
  final String? host;
  final DateTime? startedAt;
  final DateTime? lastSeenAt;
  final int totalOctets;
  final String status;

  factory SessionRecord.fromJson(Map<String, dynamic> j) => SessionRecord(
        host: j['nas_identifier']?.toString(),
        startedAt: DateTime.tryParse(j['started_at']?.toString() ?? ''),
        lastSeenAt: DateTime.tryParse(j['last_seen_at']?.toString() ?? ''),
        totalOctets: (j['total_octets'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? '').toString(),
      );
}

class ActivityData {
  const ActivityData({
    required this.topups,
    required this.subscriptions,
    required this.sessions,
  });
  final List<TopupRecord> topups;
  final List<SubscriptionInfo> subscriptions;
  final List<SessionRecord> sessions;

  factory ActivityData.fromJson(Map<String, dynamic> j) {
    final d = j['data'] as Map<String, dynamic>;
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((d[key] as List?) ?? [])
            .map((e) => f(Map<String, dynamic>.from(e as Map)))
            .toList();
    return ActivityData(
      topups: list('topups', TopupRecord.fromJson),
      subscriptions: list('subscriptions', SubscriptionInfo.fromJson),
      sessions: list('sessions', SessionRecord.fromJson),
    );
  }
}
