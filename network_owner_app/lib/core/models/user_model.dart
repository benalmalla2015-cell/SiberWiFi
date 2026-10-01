import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class UserModel extends HiveObject {
  @HiveField(0) final int id;
  @HiveField(1) final String name;
  @HiveField(2) final String phone;
  @HiveField(3) final String? email;
  @HiveField(4) final String role;
  @HiveField(5) final String? avatar;
  @HiveField(6) final double availableBalance;
  @HiveField(7) final double frozenBalance;
  @HiveField(8) final double totalEarnings;
  @HiveField(9) final String? accountNumber;
  @HiveField(10) final bool isActive;
  @HiveField(11) final bool isNetworkOwner;
  @HiveField(12) final bool networkOwnerApproved;
  @HiveField(13) final String? networkStatus;
  @HiveField(14) final int? networkId;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    this.avatar,
    this.availableBalance = 0,
    this.frozenBalance = 0,
    this.totalEarnings = 0,
    this.accountNumber,
    this.isActive = true,
    this.isNetworkOwner = false,
    this.networkOwnerApproved = false,
    this.networkStatus,
    this.networkId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id:                      json['id'],
        name:                    json['name'] ?? '',
        phone:                   json['phone'] ?? '',
        email:                   json['email'],
        role:                    json['type'] ?? 'network_owner',
        avatar:                  json['avatar_url'],
        availableBalance:       (json['available_balance'] ?? 0).toDouble(),
        frozenBalance:          (json['frozen_balance'] ?? 0).toDouble(),
        totalEarnings:          (json['total_earnings'] ?? 0).toDouble(),
        accountNumber:          json['account_number'],
        isActive:               json['is_active'] ?? true,
        isNetworkOwner:         json['is_network_owner'] ?? false,
        networkOwnerApproved:   json['network_owner_approved'] ?? false,
        networkStatus:          json['network_status'],
        networkId:              json['network_id'],
      );

  Map<String, dynamic> toJson() => {
        'id':                      id,
        'name':                    name,
        'phone':                   phone,
        'email':                   email,
        'type':                    role,
        'avatar_url':              avatar,
        'available_balance':       availableBalance,
        'frozen_balance':          frozenBalance,
        'total_earnings':          totalEarnings,
        'account_number':          accountNumber,
        'is_active':               isActive,
        'is_network_owner':        isNetworkOwner,
        'network_owner_approved':  networkOwnerApproved,
        'network_status':          networkStatus,
        'network_id':              networkId,
      };

  bool get isPendingNetworkOwner => isNetworkOwner && !networkOwnerApproved;
}
