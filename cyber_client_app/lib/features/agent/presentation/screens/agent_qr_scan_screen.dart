import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/cyber_qr.dart';

/// QR reader for the agent flow. Recognises `CYBER:74XXXXXXX` (the
/// payload the subscriber app will render) and bare 74XXXXXXX codes;
/// pops with the SIM number on the first valid hit.
class AgentQrScanScreen extends StatefulWidget {
  const AgentQrScanScreen({super.key});

  @override
  State<AgentQrScanScreen> createState() => _AgentQrScanScreenState();
}

class _AgentQrScanScreenState extends State<AgentQrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _hint;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final sim = CyberQr.parseSim(raw);
      if (sim != null) {
        _handled = true;
        _controller.stop();
        Navigator.of(context).pop(sim);
        return;
      }
      if (mounted && _hint == null) {
        setState(() => _hint = 'الرمز غير تابع لسايبر نت — المتوقع CYBER:74XXXXXXX');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('مسح رمز المشترك')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Text(
                _hint ?? 'وجّه الكاميرا نحو رمز QR الخاص بالمشترك',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
          if (_hint != null)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Chip(
                  backgroundColor: AppColors.error,
                  label: Text(_hint!, style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
