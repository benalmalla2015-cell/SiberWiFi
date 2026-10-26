import 'dart:convert';

/// A saved voucher-card design for one router.
///
/// Two kinds — matching what network owners are used to:
/// - **يدوي** (`isImage == false`): colors + text fields + font size,
///   rendered by `VoucherCardView`.
/// - **صوري** (`isImage == true`): a background image picked from the
///   gallery; the code + QR are overlaid on top.
///
/// [loginUrl] is optional — when set it may contain `{code}` which is
/// replaced by the voucher code inside the QR payload (e.g. the
/// hotspot login URL). When empty the QR encodes the code itself.
class CardTemplate {
  final String id;
  final String name;
  final bool isImage;
  final String networkName;
  final String contact;
  final String packageLabel;
  final int price; // ر.ي — printed on the card; sale price lives in the platform category
  final int color1; // ARGB
  final int color2; // ARGB
  final double fontSize;
  final String? imagePath;
  final String? loginUrl;

  const CardTemplate({
    required this.id,
    required this.name,
    this.isImage = false,
    this.networkName = '',
    this.contact = '',
    this.packageLabel = '',
    this.price = 0,
    this.color1 = 0xFF1E2D7D, // AppColors.primary
    this.color2 = 0xFFE31E24, // AppColors.accent
    this.fontSize = 18,
    this.imagePath,
    this.loginUrl,
  });

  String qrPayload(String code) {
    final url = loginUrl;
    if (url != null && url.contains('{code}')) {
      return url.replaceAll('{code}', code);
    }
    return code;
  }

  CardTemplate copyWith({
    String? name,
    bool? isImage,
    String? networkName,
    String? contact,
    String? packageLabel,
    int? price,
    int? color1,
    int? color2,
    double? fontSize,
    String? imagePath,
    String? loginUrl,
    bool clearImage = false,
  }) {
    return CardTemplate(
      id: id,
      name: name ?? this.name,
      isImage: isImage ?? this.isImage,
      networkName: networkName ?? this.networkName,
      contact: contact ?? this.contact,
      packageLabel: packageLabel ?? this.packageLabel,
      price: price ?? this.price,
      color1: color1 ?? this.color1,
      color2: color2 ?? this.color2,
      fontSize: fontSize ?? this.fontSize,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      loginUrl: loginUrl ?? this.loginUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isImage': isImage,
        'networkName': networkName,
        'contact': contact,
        'packageLabel': packageLabel,
        'price': price,
        'color1': color1,
        'color2': color2,
        'fontSize': fontSize,
        'imagePath': imagePath,
        'loginUrl': loginUrl,
      };

  factory CardTemplate.fromJson(Map<String, dynamic> j) => CardTemplate(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'قالب',
        isImage: j['isImage'] == true,
        networkName: j['networkName']?.toString() ?? '',
        contact: j['contact']?.toString() ?? '',
        packageLabel: j['packageLabel']?.toString() ?? '',
        price: (j['price'] as num?)?.toInt() ?? 0,
        color1: (j['color1'] as num?)?.toInt() ?? 0xFF1E2D7D,
        color2: (j['color2'] as num?)?.toInt() ?? 0xFFE31E24,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 18,
        imagePath: j['imagePath']?.toString(),
        loginUrl: j['loginUrl']?.toString(),
      );

  static String encodeList(List<CardTemplate> list) =>
      jsonEncode(list.map((t) => t.toJson()).toList());

  static List<CardTemplate> decodeList(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => CardTemplate.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .where((t) => t.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
