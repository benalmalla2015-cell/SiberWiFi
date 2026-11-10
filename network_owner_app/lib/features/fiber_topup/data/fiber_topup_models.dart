// Models for the fixed-line (landline / ADSL / FTTH) top-up feature.
// The catalog is fully server-driven — `GET /topup/services` → service
// code `post` — so packages and prices can be edited from the admin
// panel without an app update.

class FiberFieldSpec {
  final String key;
  final String type; // number | amount | select | text
  final String label;
  final int len;

  const FiberFieldSpec({
    required this.key,
    required this.type,
    required this.label,
    this.len = 0,
  });

  factory FiberFieldSpec.fromJson(Map<String, dynamic> j) => FiberFieldSpec(
        key: j['key']?.toString() ?? '',
        type: j['type']?.toString() ?? 'text',
        label: j['label']?.toString() ?? '',
        len: int.tryParse('${j['len'] ?? 0}') ?? 0,
      );
}

class FiberPackage {
  final String name;
  final String code;
  final double price;
  final String note;
  final String group; // collapsible section (فايبر 10M / باقات ADSL …)
  final String network; // south | north | both — gateway filter
  final Map<String, dynamic> params; // e.g. {"type":"ftth"} — provider routing
  final String data;
  final String days;
  final String minutes;
  final String sms;

  const FiberPackage({
    required this.name,
    required this.code,
    required this.price,
    this.note = '',
    this.group = '',
    this.network = 'both',
    this.params = const {},
    this.data = '',
    this.days = '',
    this.minutes = '',
    this.sms = '',
  });

  /// Provider-side service type carried in `params` (ftth | adsl | line).
  /// Packages without an explicit type are treated as generic bill payments.
  String get serviceType => params['type']?.toString() ?? 'line';

  /// Spec chips shown under the package name (data · days · minutes · sms).
  List<String> get specs => [
        if (data.isNotEmpty) data,
        if (days.isNotEmpty) '$days أيام',
        if (minutes.isNotEmpty && minutes != '0') 'مكالمات: $minutes',
        if (sms.isNotEmpty) '$sms رسالة',
      ];

  factory FiberPackage.fromJson(Map<String, dynamic> j) {
    final rawParams = j['params'];
    return FiberPackage(
      name: j['name']?.toString() ?? '',
      code: j['code']?.toString() ?? '',
      price: double.tryParse('${j['price'] ?? 0}') ?? 0,
      note: j['note']?.toString() ?? '',
      group: j['group']?.toString() ?? '',
      network: j['network']?.toString() ?? 'both',
      params: rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : const {},
      data: j['data']?.toString() ?? '',
      days: j['days']?.toString() ?? '',
      minutes: j['minutes']?.toString() ?? '',
      sms: j['sms']?.toString() ?? '',
    );
  }
}

class FiberService {
  final String code;
  final String nameAr;
  final String feeType; // none | percent | fixed
  final double feeValue;
  final List<FiberFieldSpec> fields;
  final List<FiberPackage> packages;
  final String account; // 'south' | 'north' — default provider gateway

  const FiberService({
    required this.code,
    required this.nameAr,
    required this.feeType,
    required this.feeValue,
    required this.fields,
    required this.packages,
    required this.account,
  });

  factory FiberService.fromJson(Map<String, dynamic> j) {
    final meta = (j['meta'] as Map?)?.cast<String, dynamic>() ?? {};
    return FiberService(
      code: j['code']?.toString() ?? '',
      nameAr: j['name_ar']?.toString() ?? '',
      feeType: j['fee_type']?.toString() ?? 'none',
      feeValue: double.tryParse('${j['fee_value'] ?? 0}') ?? 0,
      fields: ((meta['fields'] as List?) ?? [])
          .map((f) => FiberFieldSpec.fromJson((f as Map).cast<String, dynamic>()))
          .toList(),
      packages: ((j['packages'] as List?) ?? [])
          .map((p) => FiberPackage.fromJson((p as Map).cast<String, dynamic>()))
          .toList(),
      account: j['account']?.toString() == 'north' ? 'north' : 'south',
    );
  }

  /// Packages of one provider type (ftth | adsl | line) that are available
  /// through the given gateway — grouped by section title in server order.
  Map<String, List<FiberPackage>> groupedByType(
    String type, {
    String? account,
  }) {
    final map = <String, List<FiberPackage>>{};
    for (final p in packages) {
      if (p.serviceType != type) continue;
      if (account != null && p.network != 'both' && p.network != account) {
        continue;
      }
      map.putIfAbsent(p.group.isEmpty ? 'الباقات' : p.group, () => []).add(p);
    }
    return map;
  }
}

class FiberOrder {
  final int id;
  final String target;
  final double amount;
  final double totalCharged;
  final String transid;
  final String status; // pending | done | failed | banned
  final String? resultDesc;
  final DateTime? createdAt;

  const FiberOrder({
    required this.id,
    required this.target,
    required this.amount,
    required this.totalCharged,
    required this.transid,
    required this.status,
    this.resultDesc,
    this.createdAt,
  });

  factory FiberOrder.fromJson(Map<String, dynamic> j) => FiberOrder(
        id: int.tryParse('${j['id'] ?? 0}') ?? 0,
        target: j['target']?.toString() ?? '',
        amount: double.tryParse('${j['amount'] ?? 0}') ?? 0,
        totalCharged: double.tryParse('${j['total_charged'] ?? 0}') ?? 0,
        transid: j['transid']?.toString() ?? '',
        status: j['status']?.toString() ?? 'pending',
        resultDesc: j['result_desc']?.toString(),
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
      );
}
