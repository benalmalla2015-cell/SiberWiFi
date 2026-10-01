import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final Dio _dio = Dio();

  /// Called when the user taps a heads-up notification shown by [show].
  /// Receives the decoded payload map that was passed as [payload].
  static void Function(Map<String, dynamic> data)? onTap;

  static Future<void> initialize() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            onTap?.call(decoded);
          } else if (decoded is Map) {
            onTap?.call(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'saiberwifi_general',
        'إشعارات سايبر WiFi',
        description: 'الإشعارات العامة للتطبيق',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    await android?.requestNotificationsPermission();
  }

  static Future<void> show({
    required String title,
    required String body,
    String? imageUrl,
    Map<String, dynamic>? payload,
  }) async {
    AndroidNotificationDetails? androidDetails;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final filePath = await _downloadImage(imageUrl);
        if (filePath != null) {
          androidDetails = AndroidNotificationDetails(
            'saiberwifi_general',
            'إشعارات سايبر WiFi',
            channelDescription: 'الإشعارات العامة للتطبيق',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            category: AndroidNotificationCategory.message,
            styleInformation: BigPictureStyleInformation(
              FilePathAndroidBitmap(filePath),
              largeIcon: FilePathAndroidBitmap(filePath),
              contentTitle: title,
              summaryText: body,
            ),
          );
        }
      } catch (_) {}
    }

    androidDetails ??= const AndroidNotificationDetails(
      'saiberwifi_general',
      'إشعارات سايبر WiFi',
      channelDescription: 'الإشعارات العامة للتطبيق',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
    );

    return _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload == null ? null : jsonEncode(payload),
    );
  }

  static Future<String?> _downloadImage(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(response.data ?? []);
      if (bytes.isEmpty) return null;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/notif_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
