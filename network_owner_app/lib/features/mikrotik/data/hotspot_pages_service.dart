import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

/// One catalog entry from GET /network-owner/mikrotik/page-templates.
class PageTemplate {
  const PageTemplate({
    required this.id,
    required this.name,
    required this.description,
    this.colorPrimary = '#1a3a6b',
    this.colorAccent = '#c8102e',
    this.welcomeMsg = '',
  });

  final String id;
  final String name;
  final String description;
  final String colorPrimary;
  final String colorAccent;
  final String welcomeMsg;

  factory PageTemplate.fromJson(Map<String, dynamic> j) {
    final d = j['defaults'] is Map ? j['defaults'] as Map : const {};
    return PageTemplate(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      colorPrimary: d['color_primary']?.toString() ?? '#1a3a6b',
      colorAccent: d['color_accent']?.toString() ?? '#c8102e',
      welcomeMsg: d['welcome_msg']?.toString() ?? '',
    );
  }
}

/// Result of POST …/render — the files the router should fetch.
class RenderedPages {
  const RenderedPages({
    required this.renderId,
    required this.files,
    required this.previewUrl,
  });

  final String renderId;

  /// name → absolute URL the router downloads.
  final Map<String, String> files;
  final String previewUrl;

  factory RenderedPages.fromJson(Map<String, dynamic> j) {
    final d = j['data'] is Map ? j['data'] as Map : const {};
    final files = <String, String>{};
    for (final f in (d['files'] as List? ?? const [])) {
      if (f is Map && f['name'] != null && f['url'] != null) {
        files[f['name'].toString()] = f['url'].toString();
      }
    }
    return RenderedPages(
      renderId: d['render_id']?.toString() ?? '',
      files: files,
      previewUrl: d['preview_url']?.toString() ?? '',
    );
  }
}

/// Client for the hosted hotspot-page template store.
class HotspotPagesService {
  HotspotPagesService._();

  static const _base = '/network-owner/mikrotik';

  static Map<String, dynamic>? _data(Response res) =>
      res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;

  static Future<List<PageTemplate>> templates(ApiClient api) async {
    final res = await api.get('$_base/page-templates');
    final list = _data(res)?['data'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => PageTemplate.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// Renders a template with the owner's customization. [logoPath] is a
  /// local file picked on the phone (embedded as data-URI server-side).
  static Future<RenderedPages> render(
    ApiClient api, {
    required String templateId,
    String? networkName,
    String? welcomeMsg,
    String? whatsapp,
    String? colorPrimary,
    String? colorAccent,
    String? logoPath,
  }) async {
    final res = await api.post(
      '$_base/page-templates/render',
      data: {
        'template_id': templateId,
        'network_name': ?networkName,
        'welcome_msg': ?welcomeMsg,
        'whatsapp': ?whatsapp,
        'color_primary': ?colorPrimary,
        'color_accent': ?colorAccent,
        if (logoPath != null)
          'logo': await MultipartFile.fromFile(logoPath),
      },
    );
    final j = _data(res);
    if (j?['success'] == true) return RenderedPages.fromJson(j!);
    throw Exception(j?['message']?.toString() ?? 'تعذر تجهيز القالب');
  }
}
