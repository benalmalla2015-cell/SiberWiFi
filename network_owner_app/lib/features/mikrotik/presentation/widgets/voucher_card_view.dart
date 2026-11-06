import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/card_template.dart';

/// Live-rendered voucher card — the single source of truth for how a
/// card looks in the designer preview, the results grid, and as the
/// on-screen reference for PDF export.
class VoucherCardView extends StatelessWidget {
  final CardTemplate template;
  final String code;
  final double qrSize;

  const VoucherCardView({
    super.key,
    required this.template,
    required this.code,
    this.qrSize = 62,
  });

  @override
  Widget build(BuildContext context) {
    if (template.isImage && template.imagePath != null) {
      return _imageCard();
    }
    return _manualCard();
  }

  Widget _manualCard() {
    final c1 = Color(template.color1);
    final c2 = Color(template.color2);
    // The content is laid out at a fixed logical size inside a
    // FittedBox, so narrow grid cells scale it down instead of
    // overflowing (was the pixel-overflow error on print preview).
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c1, c2],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 300,
            height: 196,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.wifi,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          template.networkName.isEmpty
                              ? 'اسم الشبكة'
                              : template.networkName,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    code.isEmpty ? 'USER-PASS' : code,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                      fontSize: template.fontSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (template.packageLabel.isNotEmpty)
                              Text(
                                template.packageLabel,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (template.price > 0)
                              Text(
                                '${template.price} ريال',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (template.contact.isNotEmpty)
                              Text(
                                template.contact,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: Colors.white
                                      .withValues(alpha: 0.8),
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: QrImageView(
                          data: template.qrPayload(
                              code.isEmpty ? 'USER-PASS' : code),
                          size: qrSize,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Image.file(
            File(template.imagePath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: const Color(0xFF1E2D7D),
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined,
                  color: Colors.white54),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: QrImageView(
                data: template.qrPayload(code.isEmpty ? 'USER-PASS' : code),
                size: qrSize,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                code.isEmpty ? 'USER-PASS' : code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.white,
                  fontSize: template.fontSize * 0.8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
