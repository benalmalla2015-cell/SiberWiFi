// Verifies the patched router_os_client against the simulator.
// Run: dart run tool/legacy_login_check.dart
import 'package:router_os_client/router_os_client.dart';

Future<RouterOSClient> _mk(String password) => Future.value(RouterOSClient(
      address: '127.0.0.1',
      user: 'dev',
      password: password,
      port: 8728,
      timeout: const Duration(seconds: 8),
    ));

Future<void> main() async {
  final client = await _mk('dev123');
  print('login: ${await client.login()}');
  final id = await client.talk(['/system/identity/print']);
  print('identity: $id');
  final res = await client.talk(['/system/resource/print']);
  print('version: ${res.first['version']}');
  client.close();

  final bad = await _mk('WRONG');
  print('wrong-password login: ${await bad.login()}');
  bad.close();
}
