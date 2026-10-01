// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserModelAdapter extends TypeAdapter<UserModel> {
  @override
  final int typeId = 0;

  @override
  UserModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserModel(
      id:                      fields[0] as int,
      name:                    fields[1] as String,
      phone:                   fields[2] as String,
      email:                   fields[3] as String?,
      role:                    fields[4] as String,
      avatar:                  fields[5] as String?,
      availableBalance:        fields[6] as double,
      frozenBalance:           fields[7] as double,
      totalEarnings:           fields[8] as double,
      accountNumber:           fields[9] as String?,
      isActive:                fields[10] as bool,
      isNetworkOwner:          fields[11] as bool? ?? false,
      networkOwnerApproved:    fields[12] as bool? ?? false,
      networkStatus:           fields[13] as String?,
      networkId:               fields[14] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, UserModel obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.phone)
      ..writeByte(3)
      ..write(obj.email)
      ..writeByte(4)
      ..write(obj.role)
      ..writeByte(5)
      ..write(obj.avatar)
      ..writeByte(6)
      ..write(obj.availableBalance)
      ..writeByte(7)
      ..write(obj.frozenBalance)
      ..writeByte(8)
      ..write(obj.totalEarnings)
      ..writeByte(9)
      ..write(obj.accountNumber)
      ..writeByte(10)
      ..write(obj.isActive)
      ..writeByte(11)
      ..write(obj.isNetworkOwner)
      ..writeByte(12)
      ..write(obj.networkOwnerApproved)
      ..writeByte(13)
      ..write(obj.networkStatus)
      ..writeByte(14)
      ..write(obj.networkId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
