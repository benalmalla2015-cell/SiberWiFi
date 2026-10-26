import 'package:shared_preferences/shared_preferences.dart';

import 'card_template.dart';

/// Per-router card-template gallery, persisted locally.
/// Templates are design assets (colors/text/image) — nothing here
/// touches the router or the platform.
class CardTemplateStore {
  CardTemplateStore._();

  static String _key(String routerId) =>
      'mikrotik_card_templates_v1:$routerId';

  static Future<List<CardTemplate>> load(String routerId) async {
    final prefs = await SharedPreferences.getInstance();
    return CardTemplate.decodeList(prefs.getString(_key(routerId)) ?? '');
  }

  static Future<void> upsert(String routerId, CardTemplate t) async {
    final list = await load(routerId);
    final i = list.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      list[i] = t;
    } else {
      list.add(t);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(routerId), CardTemplate.encodeList(list));
  }

  static Future<void> delete(String routerId, String id) async {
    final list = await load(routerId)
      ..removeWhere((e) => e.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(routerId), CardTemplate.encodeList(list));
  }
}
