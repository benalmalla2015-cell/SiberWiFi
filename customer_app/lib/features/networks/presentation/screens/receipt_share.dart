import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/app_theme.dart';

/// Shown right after a successful purchase, with the data already in hand.
class ReceiptShareDialog extends StatefulWidget {
  final String networkName;
  final List<Map<String, dynamic>> cards;
  final double price;
  final double value;
  final String? transactionNumber;
  final bool isAdvance;
  final double discount;
  final double originalPrice;
  const ReceiptShareDialog({
    super.key,
    required this.networkName,
    required this.cards,
    required this.price,
    required this.value,
    this.transactionNumber,
    this.isAdvance = false,
    this.discount = 0,
    this.originalPrice = 0,
  });

  @override
  State<ReceiptShareDialog> createState() => _ReceiptShareDialogState();
}

class _ReceiptShareDialogState extends State<ReceiptShareDialog> {
  final _bodyKey = GlobalKey<ReceiptBodyState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: const Text(
        'تم الشراء بنجاح',
        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
      ),
      content: ReceiptBody(
        key: _bodyKey,
        networkName: widget.networkName,
        cards: widget.cards,
        price: widget.price,
        value: widget.value,
        transactionNumber: widget.transactionNumber,
        isAdvance: widget.isAdvance,
        discount: widget.discount,
        originalPrice: widget.originalPrice,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
        _ShareButton(bodyKey: _bodyKey),
      ],
    );
  }
}

class _ShareButton extends StatefulWidget {
  final GlobalKey<ReceiptBodyState> bodyKey;
  const _ShareButton({required this.bodyKey});

  @override
  State<_ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<_ShareButton> {
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    await widget.bodyKey.currentState?.share();
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _sharing ? null : _share,
      icon: _sharing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.share_rounded),
      label: const Text('مشاركة الفاتورة'),
    );
  }
}

/// The scrollable receipt body (network/price/date/card details). Reusable
/// both from the post-purchase [ReceiptShareDialog] (data already in hand)
/// and from the purchase-invoices list, which loads the data asynchronously.
class ReceiptBody extends StatefulWidget {
  final String networkName;
  final List<Map<String, dynamic>> cards;
  final double price;
  final double value;
  final String? transactionNumber;
  final bool isAdvance;
  final double discount;
  final double originalPrice;
  const ReceiptBody({
    super.key,
    required this.networkName,
    required this.cards,
    required this.price,
    required this.value,
    this.transactionNumber,
    this.isAdvance = false,
    this.discount = 0,
    this.originalPrice = 0,
  });

  @override
  State<ReceiptBody> createState() => ReceiptBodyState();
}

class ReceiptBodyState extends State<ReceiptBody> {
  final _receiptKey = GlobalKey();

  Future<void> share() async {
    try {
      final boundary = _receiptKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _showSnack('تعذر إنشاء الصورة، حاول مجدداً');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        _showSnack('تعذر إنشاء صورة الفاتورة');
        return;
      }
      final bytes = data.buffer.asUint8List();
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/saiber_receipt_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'فاتورة شراء كرت من سايبر WiFi',
      );
    } catch (e) {
      _showSnack('تعذر مشاركة الفاتورة: ${e.toString()}');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontFamily: 'Cairo'))),
    );
  }

  // Avoid DateFormat's locale-symbol lookup (requires initializeDateFormatting,
  // which this app never calls) by formatting manually instead.
  String _formatNow() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} - ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: RepaintBoundary(
        key: _receiptKey,
        child: Container(
          width: 340,
          color: Colors.white,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.primary,
                size: 42,
              ),
              const SizedBox(height: 8),
              const Text(
                'سايبر WiFi',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const Text(
                'فاتورة شراء',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: AppColors.textGray,
                ),
              ),
              const Divider(height: 28),
              _row('الشبكة', widget.networkName),
              _row(
                'الفئة',
                '${NumberFormat('#,##0', 'ar').format(widget.value)} ر.ي',
              ),
              if (widget.discount > 0 && widget.originalPrice > widget.price) ...[
                _row(
                  'السعر قبل الخصم',
                  '${NumberFormat('#,##0.00', 'ar').format(widget.originalPrice)} ر.ي',
                ),
                _row(
                  'خصم العرض',
                  '- ${NumberFormat('#,##0.00', 'ar').format(widget.discount)} ر.ي',
                ),
              ],
              _row(
                widget.isAdvance ? 'مبلغ السلفة' : 'المبلغ المدفوع',
                widget.isAdvance
                    ? '${NumberFormat('#,##0.00', 'ar').format(widget.price)} ر.ي (لم يتم السداد)'
                    : '${NumberFormat('#,##0.00', 'ar').format(widget.price)} ر.ي',
              ),
              if (widget.isAdvance)
                _row('حالة السلفة', 'غير مسددة - سيتم خصم قيمتها من الرصيد عند الشحن'),
              _row('التاريخ', _formatNow()),
              if (widget.transactionNumber?.isNotEmpty == true)
                _row('رقم العملية', widget.transactionNumber!),
              const Divider(height: 28),
              if (widget.cards.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'لا تتوفر بيانات كرت لهذه العملية',
                    style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray, fontSize: 13),
                  ),
                )
              else
                ...widget.cards.map((card) => _CardBlock(card: card)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: AppColors.textGray,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CardBlock extends StatelessWidget {
  final Map<String, dynamic> card;
  const _CardBlock({required this.card});

  @override
  Widget build(BuildContext context) {
    final code = card['code']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'رقم الكرت',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: AppColors.textGray,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.primary),
                onPressed: () {
                  if (code.isEmpty) return;
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الكرت', style: TextStyle(fontFamily: 'Cairo'))),
                  );
                },
              ),
            ],
          ),
          SelectableText(
            code,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            'التسلسلي: ${card['serial'] ?? ''}',
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: AppColors.textGray,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
