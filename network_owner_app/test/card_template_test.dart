import 'package:flutter_test/flutter_test.dart';
import 'package:network_owner_app/features/mikrotik/data/card_template.dart';

void main() {
  group('CardTemplate', () {
    test('defaults are a complete manual template', () {
      const t = CardTemplate(id: 't1', name: 'افتراضي');
      expect(t.isImage, false);
      expect(t.fontSize, greaterThan(0));
      expect(t.color1, 0xFF1E2D7D); // brand navy
    });

    test('round-trips through JSON serialization', () {
      const t = CardTemplate(
        id: 't2',
        name: 'قالب تجريبي',
        isImage: true,
        color1: 0xFF123456,
        price: 500,
        contact: '77xxxx',
        imagePath: '/tmp/bg.png',
        loginUrl: 'http://wifi/login?u={code}',
      );
      final t2 = CardTemplate.fromJson(t.toJson());
      expect(t2.id, t.id);
      expect(t2.name, t.name);
      expect(t2.isImage, true);
      expect(t2.color1, 0xFF123456);
      expect(t2.price, 500);
      expect(t2.contact, '77xxxx');
      expect(t2.imagePath, '/tmp/bg.png');
      expect(t2.loginUrl, 'http://wifi/login?u={code}');
    });

    test('qrPayload substitutes {code} into login URL', () {
      const t = CardTemplate(
          id: 't3',
          name: 'n',
          loginUrl: 'http://wifi/login?u={code}');
      expect(t.qrPayload('AB12CD'), 'http://wifi/login?u=AB12CD');
      // Without a URL (or no placeholder) the QR carries the raw code
      expect(const CardTemplate(id: 't4', name: 'n').qrPayload('X1'),
          'X1');
      expect(
          const CardTemplate(
                  id: 't5', name: 'n', loginUrl: 'http://wifi/')
              .qrPayload('X1'),
          'X1');
    });

    test('encodeList/decodeList survives a list of templates', () {
      const list = [
        CardTemplate(id: 'a', name: 'أول'),
        CardTemplate(id: 'b', name: 'ثانٍ', isImage: true),
      ];
      final out = CardTemplate.decodeList(
          CardTemplate.encodeList(list));
      expect(out.length, 2);
      expect(out[0].id, 'a');
      expect(out[1].isImage, true);
      // Corrupt payloads fail safe, not crash
      expect(CardTemplate.decodeList('not json'), isEmpty);
    });
  });
}
