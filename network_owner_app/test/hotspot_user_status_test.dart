import 'package:flutter_test/flutter_test.dart';
import 'package:network_owner_app/features/mikrotik/data/hotspot_user_status.dart';

void main() {
  group('rosDurationToSeconds', () {
    test('parses compound and simple durations', () {
      expect(rosDurationToSeconds('2h15m'), 8100);
      expect(rosDurationToSeconds('35m'), 2100);
      expect(rosDurationToSeconds('45s'), 45);
      expect(rosDurationToSeconds('1d'), 86400);
      expect(rosDurationToSeconds('1w2d3h4m5s'), 788645);
      expect(rosDurationToSeconds('3d4h12m33s'), 274353);
    });
    test('empty / null → 0', () {
      expect(rosDurationToSeconds(''), 0);
      expect(rosDurationToSeconds(null), 0);
    });
  });

  group('classifyHotspotUser', () {
    const active = {'GUEST01'};

    test('disabled → معطّل', () {
      expect(
        classifyHotspotUser({'name': 'X', 'disabled': 'true'}, active),
        HotspotUserStatus.disabled,
      );
    });
    test('uptime >= limit-uptime → منتهي', () {
      expect(
        classifyHotspotUser(
          {'name': 'Y', 'disabled': 'false', 'uptime': '2h',
           'limit-uptime': '1h'},
          active,
        ),
        HotspotUserStatus.expired,
      );
    });
    test('in active set → متصل', () {
      expect(
        classifyHotspotUser(
          {'name': 'GUEST01', 'disabled': 'false', 'uptime': '10m'},
          active,
        ),
        HotspotUserStatus.active,
      );
    });
    test('default → غير نشط', () {
      expect(
        classifyHotspotUser(
          {'name': 'Z', 'disabled': 'false'},
          active,
        ),
        HotspotUserStatus.idle,
      );
    });
  });

  group('hotspotUsageLabel', () {
    test('sums and formats bytes', () {
      expect(hotspotUsageLabel({'bytes-in': '0', 'bytes-out': '0'}), '0 B');
      expect(
        hotspotUsageLabel({'bytes-in': '1048576', 'bytes-out': '5242880'}),
        '6.0 MB',
      );
    });
  });
}
