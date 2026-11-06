import 'dart:math';

import 'package:router_os_client/router_os_client.dart';

import 'router_model.dart';

/// Thin wrapper around RouterOSClient exposing the operations the
/// owner app needs. A single instance represents one live session —
/// create per screen, always call [close] when done.
class RouterOsService {
  RouterOsService._(this._client);

  final RouterOSClient _client;

  static const _timeout = Duration(seconds: 12);

  /// Opens a socket + logs in. Throws on failure.
  static Future<RouterOsService> connect(MikrotikRouterConfig cfg) async {
    final client = RouterOSClient(
      address: cfg.host,
      user: cfg.username,
      password: cfg.password,
      port: cfg.port,
      useSsl: cfg.useSsl,
      timeout: _timeout,
    );
    final ok = await client.login();
    if (!ok) {
      client.close();
      throw LoginError('فشل تسجيل الدخول — تحقق من بيانات الاعتماد');
    }
    return RouterOsService._(client);
  }

  /// Test connectivity + credentials. Returns router identity name.
  static Future<String> testConnection(MikrotikRouterConfig cfg) async {
    final svc = await connect(cfg);
    try {
      final res = await svc._client.talk(['/system/identity/print']);
      return res.isNotEmpty
          ? (res.first['name'] ?? 'RouterOS')
          : 'RouterOS';
    } finally {
      svc.close();
    }
  }

  void close() => _client.close();

  // ── System info ────────────────────────────────────────────────

  Future<Map<String, String>> systemResource() async {
    final res = await _client.talk(['/system/resource/print']);
    return res.isNotEmpty ? res.first : {};
  }

  Future<String> identity() async {
    final res = await _client.talk(['/system/identity/print']);
    return res.isNotEmpty ? (res.first['name'] ?? '') : '';
  }

  Future<List<Map<String, String>>> interfaces() =>
      _client.talk(['/interface/print']);

  // ── Hotspot ────────────────────────────────────────────────────

  Future<List<Map<String, String>>> hotspotUsers() =>
      _client.talk(['/ip/hotspot/user/print']);

  Future<List<Map<String, String>>> hotspotActive() =>
      _client.talk(['/ip/hotspot/active/print']);

  Future<List<Map<String, String>>> hotspotProfiles() =>
      _client.talk(['/ip/hotspot/user/profile/print']);

  /// Creates one hotspot user (a voucher code) on the router.
  ///
  /// [limitBytesTotal] maps to `limit-bytes-total` (download+upload
  /// quota). [validityDays] and [price] are recorded inside the
  /// comment as `v:Nd` / `p:N` so the data survives on the router
  /// and stays parseable for later sync — RouterOS has no native
  /// account-validity-days field for hotspot users.
  Future<void> addHotspotUser({
    required String name,
    String? password,
    String? profile,
    String? comment,
    String? limitUptime,
    int? limitBytesTotal,
    String? rateLimit,
    int? validityDays,
    int? price,
  }) async {
    final params = <String, String>{'name': name};
    if (password != null && password.isNotEmpty) {
      params['password'] = password;
    }
    if (profile != null && profile.isNotEmpty) params['profile'] = profile;
    if (rateLimit != null && rateLimit.isNotEmpty) {
      params['rate-limit'] = rateLimit;
    }
    final meta = <String>[
      if (comment != null && comment.isNotEmpty) comment,
      if (validityDays != null && validityDays > 0) 'v:${validityDays}d',
      if (price != null && price > 0) 'p:$price',
    ];
    if (meta.isNotEmpty) params['comment'] = meta.join(' ');
    if (limitUptime != null && limitUptime.isNotEmpty) {
      params['limit-uptime'] = limitUptime;
    }
    if (limitBytesTotal != null && limitBytesTotal > 0) {
      params['limit-bytes-total'] = '$limitBytesTotal';
    }
    await _client.talk(['/ip/hotspot/user/add'], params);
  }

  Future<void> removeHotspotUser(String id) =>
      _client.talk(['/ip/hotspot/user/remove'], {'numbers': id});

  /// Deletes several users in one call (numbers accepts "id1,id2,...").
  Future<void> removeHotspotUsers(List<String> ids) =>
      _client.talk(['/ip/hotspot/user/remove'], {'numbers': ids.join(',')});

  /// Updates arbitrary attributes of one user (password/profile/comment/
  /// limit-uptime...). Keys are RouterOS attribute names.
  Future<void> setHotspotUser(String id, Map<String, String> attrs) =>
      _client.talk(['/ip/hotspot/user/set'], {'numbers': id, ...attrs});

  Future<void> enableHotspotUsers(List<String> ids) =>
      _client.talk(['/ip/hotspot/user/enable'], {'numbers': ids.join(',')});

  Future<void> disableHotspotUsers(List<String> ids) =>
      _client.talk(['/ip/hotspot/user/disable'], {'numbers': ids.join(',')});

  /// Kicks an active hotspot session (forces re-login or drop).
  Future<void> disconnectHotspotActive(String id) =>
      _client.talk(['/ip/hotspot/active/remove'], {'numbers': id});

  // ── Hotspot profiles (packages) ────────────────────────────────

  Future<void> addHotspotProfile({
    required String name,
    String? rateLimit,
    String? sharedUsers,
    String? sessionTimeout,
    String? onLogin,
    String? onLogout,
    String? comment,
  }) async {
    final p = <String, String>{'name': name};
    void opt(String k, String? v) {
      if (v != null && v.isNotEmpty) p[k] = v;
    }

    opt('rate-limit', rateLimit);
    opt('shared-users', sharedUsers);
    opt('session-timeout', sessionTimeout);
    opt('on-login', onLogin);
    opt('on-logout', onLogout);
    opt('comment', comment);
    await _client.talk(['/ip/hotspot/user/profile/add'], p);
  }

  Future<void> setHotspotProfile(String id, Map<String, String> attrs) =>
      _client.talk(['/ip/hotspot/user/profile/set'],
          {'numbers': id, ...attrs});

  Future<void> removeHotspotProfile(String id) =>
      _client.talk(['/ip/hotspot/user/profile/remove'], {'numbers': id});

  // ── PPP (PPPoE / Broadband) ────────────────────────────────────

  Future<List<Map<String, String>>> pppSecrets() =>
      _client.talk(['/ppp/secret/print']);

  Future<List<Map<String, String>>> pppActive() =>
      _client.talk(['/ppp/active/print']);

  Future<List<Map<String, String>>> pppProfiles() =>
      _client.talk(['/ppp/profile/print']);

  Future<void> addPppSecret({
    required String name,
    required String password,
    String? service,
    String? profile,
    String? remoteAddress,
    String? routes,
    String? comment,
    bool disabled = false,
  }) async {
    final p = <String, String>{'name': name, 'password': password};
    void opt(String k, String? v) {
      if (v != null && v.isNotEmpty) p[k] = v;
    }

    opt('service', service);
    opt('profile', profile);
    opt('remote-address', remoteAddress);
    opt('routes', routes);
    opt('comment', comment);
    if (disabled) p['disabled'] = 'yes';
    await _client.talk(['/ppp/secret/add'], p);
  }

  Future<void> setPppSecret(String id, Map<String, String> attrs) =>
      _client.talk(['/ppp/secret/set'], {'numbers': id, ...attrs});

  Future<void> removePppSecrets(List<String> ids) =>
      _client.talk(['/ppp/secret/remove'], {'numbers': ids.join(',')});

  Future<void> enablePppSecrets(List<String> ids) =>
      _client.talk(['/ppp/secret/enable'], {'numbers': ids.join(',')});

  Future<void> disablePppSecrets(List<String> ids) =>
      _client.talk(['/ppp/secret/disable'], {'numbers': ids.join(',')});

  /// Kicks an active PPP session.
  Future<void> disconnectPppActive(String id) =>
      _client.talk(['/ppp/active/remove'], {'numbers': id});

  // ── User Manager ───────────────────────────────────────────────
  // RouterOS v7 exposes User Manager at /user-manager; on v6 the same
  // package lives under /tool/user-manager. The first UM call probes the
  // v7 path and, on a "no such command" trap, permanently switches this
  // session to the v6 path so every later call goes direct.

  String _umBase = '/user-manager';
  bool _umProbed = false;

  Future<List<Map<String, String>>> _um(String tail,
      [Map<String, String>? params]) async {
    try {
      final rows = await _client.talk(['$_umBase$tail'], params);
      _umProbed = true;
      return rows;
    } on RouterOSTrapError catch (e) {
      if (!_umProbed &&
          _umBase == '/user-manager' &&
          e.message.contains('no such command')) {
        _umProbed = true;
        _umBase = '/tool/user-manager';
        return _client.talk(['$_umBase$tail'], params);
      }
      rethrow;
    }
  }

  /// Write ops translate attribute names differently per userman
  /// generation, so the base path must be resolved before building
  /// the attribute map.
  Future<void> _ensureUmProbed() async {
    if (!_umProbed) await umUsers();
  }

  /// v6 legacy userman rows expose the login as `username` instead of
  /// `name` — normalize to `name` so the UI works on both generations.
  void _normalizeUmRows(List<Map<String, String>> rows) {
    if (_umBase != '/tool/user-manager') return;
    for (final r in rows) {
      if ((r['name'] ?? '').isEmpty && (r['username'] ?? '').isNotEmpty) {
        r['name'] = r['username']!;
      }
    }
  }

  /// Translates attribute maps for the v6 legacy userman (`name` →
  /// `username`).
  Map<String, String> _umAttrs(Map<String, String> attrs) {
    if (_umBase != '/tool/user-manager') return attrs;
    final out = Map<String, String>.of(attrs);
    if (out.containsKey('name')) {
      out['username'] = out.remove('name')!;
    }
    return out;
  }

  Future<List<Map<String, String>>> umUsers() async {
    final rows = await _um('/user/print');
    _normalizeUmRows(rows);
    return rows;
  }

  Future<List<Map<String, String>>> umProfiles() async {
    final rows = await _um('/profile/print');
    _normalizeUmRows(rows);
    return rows;
  }

  Future<void> addUmUser({
    required String name,
    required String password,
    String? sharedUsers,
    String? comment,
    bool disabled = false,
  }) async {
    await _ensureUmProbed();
    final p = _umAttrs(<String, String>{'name': name, 'password': password});
    // Legacy (v6) userman requires every user to belong to a customer.
    if (_umBase == '/tool/user-manager') p.putIfAbsent('customer', () => 'admin');
    if (sharedUsers != null && sharedUsers.isNotEmpty) {
      p['shared-users'] = sharedUsers;
    }
    if (comment != null && comment.isNotEmpty) p['comment'] = comment;
    if (disabled) p['disabled'] = 'yes';
    await _um('/user/add', p);
  }

  Future<void> setUmUser(String id, Map<String, String> attrs) async {
    await _ensureUmProbed();
    await _um('/user/set', {'numbers': id, ..._umAttrs(attrs)});
  }

  Future<void> removeUmUsers(List<String> ids) =>
      _um('/user/remove', {'numbers': ids.join(',')});

  /// User-Manager package/profile (name/price/validity/shared-users...).
  Future<void> addUmProfile(Map<String, String> attrs) async {
    await _ensureUmProbed();
    await _um('/profile/add', _umAttrs(attrs));
  }

  Future<void> setUmProfile(String id, Map<String, String> attrs) async {
    await _ensureUmProbed();
    await _um('/profile/set', {'numbers': id, ..._umAttrs(attrs)});
  }

  Future<void> removeUmProfile(String id) =>
      _um('/profile/remove', {'numbers': id});

  // ── Monitoring & diagnostics ───────────────────────────────────

  /// One traffic sample for an interface (rx/tx bits-per-second).
  /// Poll this for a live-speed chart — `monitor-traffic` with `once`
  /// returns immediately instead of streaming, so it plays nicely
  /// with the request/response client.
  Future<Map<String, String>> interfaceMonitorOnce(String name) async {
    final res = await _client.talk(
      ['/interface/monitor-traffic'],
      {'numbers': name, 'once': ''},
    );
    return res.isNotEmpty ? res.first : {};
  }

  /// Interface list with running state + type (for pickers/counters).
  Future<List<Map<String, String>>> interfaceDetails() =>
      _client.talk(['/interface/print']);

  /// System health sensors (temperature, voltage, fan) — empty on
  /// boards without sensors; the UI shows "غير متوفر".
  Future<List<Map<String, String>>> systemHealth() =>
      _client.talk(['/system/health/print']);

  /// Discovered neighbor devices (MNDP/CDP).
  Future<List<Map<String, String>>> neighbors() =>
      _client.talk(['/ip/neighbor/print']);

  /// Currently attached hotspot hosts (connected devices count).
  Future<List<Map<String, String>>> hotspotHosts() =>
      _client.talk(['/ip/hotspot/host/print']);

  Future<List<Map<String, String>>> dhcpLeases() =>
      _client.talk(['/ip/dhcp-server/lease/print']);

  Future<List<Map<String, String>>> systemLogs() =>
      _client.talk(['/log/print']);

  /// Executes /ping — returns one row per reply (seq, time, size).
  Future<List<Map<String, String>>> ping(String host,
      {int count = 4}) {
    return _client.talk(
      ['/ping'],
      {'address': host, 'count': '$count'},
    );
  }

  /// HTTP(S) fetch from the router (download test / API calls).
  Future<List<Map<String, String>>> fetchUrl(
    String url, {
    String? method,
    String? httpHeaderField,
    String? httpData,
    bool keepResult = true,
  }) {
    final p = <String, String>{'url': url};
    if (method != null) p['http-method'] = method;
    if (httpHeaderField != null) p['http-header-field'] = httpHeaderField;
    if (httpData != null) p['http-data'] = httpData;
    p['keep-result'] = keepResult ? 'yes' : 'no';
    return _client.talk(['/tool/fetch'], p);
  }

  /// Downloads [url] and stores it on the router filesystem at
  /// [dstPath] (e.g. `saiber-pages/login.html`). RouterOS creates any
  /// missing intermediate directories. Used to pull rendered hotspot
  /// page templates — the pull-model replacement for FTP uploads.
  Future<List<Map<String, String>>> fetchToFile(
    String url,
    String dstPath, {
    bool checkCertificate = false,
  }) {
    return _client.talk([
      '/tool/fetch'
    ], {
      'url': url,
      'dst-path': dstPath,
      'check-certificate': checkCertificate ? 'yes' : 'no',
      if (url.startsWith('https')) 'mode': 'https',
    });
  }

  /// Deletes a file entry by id or name (`/file/remove`).
  Future<void> removeFile(String idOrName) =>
      _client.talk(['/file/remove'], {'numbers': idOrName});

  // ── Netwatch ───────────────────────────────────────────────────

  Future<List<Map<String, String>>> netwatch() =>
      _client.talk(['/tool/netwatch/print']);

  Future<void> addNetwatch({
    required String host,
    String? type,
    String? interval,
    String? timeout,
    String? comment,
  }) async {
    final p = <String, String>{'host': host};
    void opt(String k, String? v) {
      if (v != null && v.isNotEmpty) p[k] = v;
    }

    opt('type', type);
    opt('interval', interval);
    opt('timeout', timeout);
    opt('comment', comment);
    await _client.talk(['/tool/netwatch/add'], p);
  }

  Future<void> setNetwatch(String id, Map<String, String> attrs) =>
      _client.talk(['/tool/netwatch/set'], {'numbers': id, ...attrs});

  Future<void> removeNetwatch(String id) =>
      _client.talk(['/tool/netwatch/remove'], {'numbers': id});

  // ── Generic table operations (advanced-network sections) ───────
  // One API for every RouterOS menu: keeps 14+ admin tables behind a
  // single typed surface instead of bespoke methods per table.

  Future<List<Map<String, String>>> table(String path,
          {String? proplist, String? query}) =>
      _client.talk([
        '$path/print',
        if (proplist != null) '=.proplist=$proplist',
        ?query,
      ]);

  Future<void> tableAdd(String path, Map<String, String> attrs) =>
      _client.talk(['$path/add'], attrs);

  Future<void> tableSet(
          String path, String id, Map<String, String> attrs) =>
      _client.talk(['$path/set'], {'numbers': id, ...attrs});

  Future<void> tableRemove(String path, List<String> ids) =>
      _client.talk(['$path/remove'], {'numbers': ids.join(',')});

  Future<void> tableEnable(String path, List<String> ids) =>
      _client.talk(['$path/enable'], {'numbers': ids.join(',')});

  Future<void> tableDisable(String path, List<String> ids) =>
      _client.talk(['$path/disable'], {'numbers': ids.join(',')});

  // ── Remote access (DDNS / API-SSL / certificates) ──────────────

  /// `/ip/cloud` — MikroTik cloud DDNS state (dns-name, public IP).
  Future<Map<String, String>> cloudStatus() async {
    final res = await _client.talk(['/ip/cloud/print']);
    return res.isNotEmpty ? res.first : {};
  }

  /// `/ip/cloud/set` — enable DDNS or adjust update-time.
  Future<void> setCloud(Map<String, String> attrs) =>
      _client.talk(['/ip/cloud/set'], attrs);

  /// `/ip/service` — api / api-ssl / winbox / ssh service rows.
  Future<List<Map<String, String>>> ipServices() => table('/ip/service');

  Future<void> setIpService(String id, Map<String, String> attrs) =>
      tableSet('/ip/service', id, attrs);

  Future<List<Map<String, String>>> certificates() =>
      table('/certificate');

  /// Creates a self-signed server cert request — must be followed by
  /// [signCertificate] before api-ssl can use it.
  Future<void> addCertificate(Map<String, String> attrs) =>
      _client.talk(['/certificate/add'], attrs);

  Future<void> signCertificate(String idOrName) =>
      _client.talk(['/certificate/sign'], {'numbers': idOrName});

  // ── System administration ──────────────────────────────────────

  Future<void> reboot() => _client.talk(['/system/reboot']);

  /// Creates a binary backup file on the router (no download —
  /// file transfer needs FTP; see ROADMAP note).
  Future<void> createBackup(String name) =>
      _client.talk(['/system/backup/save'], {'name': name});

  /// Restores a backup file — router reboots during load.
  Future<void> loadBackup(String name) =>
      _client.talk(['/system/backup/load'], {'name': name});

  /// Creates a text .rsc export script.
  Future<void> exportConfig({String? file}) =>
      _client.talk(['/export'], {'file': ?file});

  Future<List<Map<String, String>>> files() =>
      _client.talk(['/file/print']);

  /// Runs a script by name (e.g. /system/script/run).
  Future<void> runScript(String name) =>
      _client.talk(['/system/script/run'], {'number': name});

  Future<List<Map<String, String>>> systemUsers() =>
      _client.talk(['/user/print']);

  Future<void> addSystemUser({
    required String name,
    required String password,
    String group = 'read',
    String? comment,
  }) =>
      _client.talk([
        '/user/add'
      ], {
        'name': name,
        'password': password,
        'group': group,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      });

  Future<void> setSystemUser(String id, Map<String, String> attrs) =>
      _client.talk(['/user/set'], {'numbers': id, ...attrs});

  Future<void> removeSystemUser(String id) =>
      _client.talk(['/user/remove'], {'numbers': id});

  Future<List<Map<String, String>>> systemGroups() =>
      _client.talk(['/user/group/print']);

  Future<void> addSystemGroup({
    required String name,
    required List<String> policies,
    String? comment,
  }) =>
      _client.talk([
        '/user/group/add'
      ], {
        'name': name,
        'policy': policies.join(','),
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      });

  Future<void> setSystemGroup(String id, Map<String, String> attrs) =>
      _client.talk(['/user/group/set'], {'numbers': id, ...attrs});

  Future<void> removeSystemGroup(String id) =>
      _client.talk(['/user/group/remove'], {'numbers': id});

  // ── Hotspot server profiles (login-page settings) ──────────────

  Future<List<Map<String, String>>> hotspotServerProfiles() =>
      _client.talk(['/ip/hotspot/profile/print']);

  Future<void> setHotspotServerProfile(
          String id, Map<String, String> attrs) =>
      _client.talk(['/ip/hotspot/profile/set'],
          {'numbers': id, ...attrs});
}

/// Generates random voucher codes (uppercase letters + digits,
/// ambiguous chars excluded for readability when printed).
class VoucherGenerator {
  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final _rand = Random.secure();

  static String code({int length = 8}) =>
      List.generate(length, (_) => _chars[_rand.nextInt(_chars.length)])
          .join();
}
