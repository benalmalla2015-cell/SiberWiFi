/// CyberNet QR payload contract (CYB-07):
/// the client app (CYB-05+) renders `CYBER:74XXXXXXX`; the agent's
/// scanner accepts that exact format and, as a convenience, a bare
/// 9-digit 74XXXXXXX number.
class CyberQr {
  static final RegExp _tagged = RegExp(r'^CYBER:(\d{9})$');
  static final RegExp _bare = RegExp(r'^(\d{9})$');

  /// Returns the SIM number embedded in [raw], or null when the
  /// payload is not a CyberNet code.
  static String? parseSim(String raw) {
    final text = raw.trim();
    final tagged = _tagged.firstMatch(text);
    if (tagged != null) return _valid(tagged.group(1)!);
    final bare = _bare.firstMatch(text);
    if (bare != null) return _valid(bare.group(1)!);
    return null;
  }

  static String? _valid(String digits) =>
      digits.startsWith('74') ? digits : null;
}
