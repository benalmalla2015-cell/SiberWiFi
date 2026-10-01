import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
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
      };
}
