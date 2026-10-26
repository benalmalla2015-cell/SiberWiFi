import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Telegram bot integration — credentials live in secure storage
/// (same store family as router credentials). The test-send goes
/// straight from the app to api.telegram.org — no server needed.
///
/// Router-side alerting (a /system/script that /tool/fetch's the bot
/// URL on a scheduler) lands as a follow-up once owners confirm the
/// flow; the wiring here already supports it.
class TelegramSettings {
  TelegramSettings._();

  static const _storage = FlutterSecureStorage();
  static const _kToken = 'mikrotik_tg_token';
  static const _kChatId = 'mikrotik_tg_chat';

  String _token = '';
  String _chatId = '';

  static final TelegramSettings instance = TelegramSettings._();

  bool get configured => _token.isNotEmpty && _chatId.isNotEmpty;
  String get token => _token;
  String get chatId => _chatId;

  Future<void> load() async {
    _token = await _storage.read(key: _kToken) ?? '';
    _chatId = await _storage.read(key: _kChatId) ?? '';
  }

  Future<void> save(String token, String chatId) async {
    _token = token.trim();
    _chatId = chatId.trim();
    await _storage.write(key: _kToken, value: _token);
    await _storage.write(key: _kChatId, value: _chatId);
  }

  /// Sends a message; returns null on success or the error text.
  Future<String?> sendMessage(String text) async {
    if (!configured) return 'أدخل Token و Chat ID أولاً';
    try {
      final dio = Dio();
      final res = await dio.get(
        'https://api.telegram.org/bot$_token/sendMessage',
        queryParameters: {'chat_id': _chatId, 'text': text},
      );
      return res.data?['ok'] == true ? null : 'فشل الإرسال';
    } on DioException catch (e) {
      return 'تعذّر الإرسال: ${e.response?.data?['description'] ?? e.message}';
    }
  }
}
