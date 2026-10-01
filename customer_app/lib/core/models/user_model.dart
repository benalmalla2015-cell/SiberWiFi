import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 1)
class UserModel extends HiveObject {
  @HiveField(0) final int    id;
  @HiveField(1) final String name;
  @HiveField(2) final String phone;
  @HiveField(3) final String? email;
  @HiveField(4) final String role;
  @HiveField(5) final String? avatar;
  @HiveField(6) final double balance;
  @HiveField(7) final bool   isActive;
  @HiveField(8) final int? regionId;
  @HiveField(9) final int? directorateId;
  @HiveField(10) final String? regionName;
  @HiveField(11) final String? directorateName;
  @HiveField(12) final int?    subDirectorateId;
  @HiveField(13) final String? subDirectorateName;
  @HiveField(14) final bool    isEligibleForAdvance;
  @HiveField(15) final double  advanceBalance;
  @HiveField(16) final String? currencyLabel;
  @HiveField(17) final String? regionType;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    this.avatar,
    this.balance = 0,
    this.isActive = true,
    this.regionId,
    this.directorateId,
    this.regionName,
    this.directorateName,
    this.subDirectorateId,
    this.subDirectorateName,
    this.isEligibleForAdvance = false,
    this.advanceBalance = 0,
    this.currencyLabel,
    this.regionType,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id:       (j['id'] as num?)?.toInt() ?? 0,
        name:     j['name']?.toString() ?? '',
        phone:    j['phone']?.toString() ?? '',
        email:    j['email']?.toString(),
        role:     j['type']?.toString() ?? 'customer',
        avatar:   j['avatar_url']?.toString(),
        balance:  (j['balance'] ?? 0).toDouble(),
        isActive: j['is_active'] ?? true,
        regionId: (j['region_id'] as num?)?.toInt(),
        directorateId: (j['directorate_id'] as num?)?.toInt(),
        regionName: j['region_name']?.toString(),
        directorateName: j['directorate_name']?.toString(),
        subDirectorateId: (j['sub_directorate_id'] as num?)?.toInt(),
        subDirectorateName: j['sub_directorate_name']?.toString(),
        isEligibleForAdvance: j['is_eligible_for_advance'] ?? false,
        advanceBalance: (j['advance_balance'] ?? 0).toDouble(),
        currencyLabel: j['currency_label']?.toString(),
        regionType: j['region_type']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id':        id,
        'name':      name,
        'phone':     phone,
        'email':     email,
        'type':      role,
        'avatar_url': avatar,
        'balance':   balance,
        'is_active': isActive,
        'region_id': regionId,
        'directorate_id': directorateId,
        'region_name': regionName,
        'directorate_name': directorateName,
        'sub_directorate_id': subDirectorateId,
        'sub_directorate_name': subDirectorateName,
        'is_eligible_for_advance': isEligibleForAdvance,
        'advance_balance': advanceBalance,
        'currency_label': currencyLabel,
        'region_type': regionType,
      };

  UserModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? role,
    String? avatar,
    double? balance,
    bool? isActive,
    int? regionId,
    int? directorateId,
    String? regionName,
    String? directorateName,
    int? subDirectorateId,
    String? subDirectorateName,
    bool? isEligibleForAdvance,
    double? advanceBalance,
    String? currencyLabel,
    String? regionType,
  }) => UserModel(
    id: id ?? this.id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    role: role ?? this.role,
    avatar: avatar ?? this.avatar,
    balance: balance ?? this.balance,
    isActive: isActive ?? this.isActive,
    regionId: regionId ?? this.regionId,
    directorateId: directorateId ?? this.directorateId,
    regionName: regionName ?? this.regionName,
    directorateName: directorateName ?? this.directorateName,
    subDirectorateId: subDirectorateId ?? this.subDirectorateId,
    subDirectorateName: subDirectorateName ?? this.subDirectorateName,
    isEligibleForAdvance: isEligibleForAdvance ?? this.isEligibleForAdvance,
    advanceBalance: advanceBalance ?? this.advanceBalance,
    currencyLabel: currencyLabel ?? this.currencyLabel,
    regionType: regionType ?? this.regionType,
  );
}
