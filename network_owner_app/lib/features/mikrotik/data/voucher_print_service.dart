import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'card_template.dart';

/// Builds printable A4 sheets of voucher cards and hands them to the
/// system print dialog (covers WiFi/BT printers via Android print
/// services) or shares the PDF.
///
/// Cards are laid out 3 columns × 4 rows per page — a standard
/// voucher-sheet density readable when cut.
class VoucherPrintService {
  VoucherPrintService._();

  static const _cols = 3;
  static const _rows = 4;
  static const _perPage = _cols * _rows;

  static Future<pw.Document> buildPdf(
    List<String> codes,
    CardTemplate t,
  ) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.cairoBold();
    final fontReg = await PdfGoogleFonts.cairoRegular();
    final c1 = PdfColor.fromInt(t.color1);
    final c2 = PdfColor.fromInt(t.color2);

    for (var p = 0; p < codes.length; p += _perPage) {
      final chunk = codes.sublist(
          p, (p + _perPage).clamp(0, codes.length));
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => pw.GridView(
            crossAxisCount: _cols,
            childAspectRatio: 1.55,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              for (final code in chunk)
                _pdfCard(code, t, c1, c2, font, fontReg),
            ],
          ),
        ),
      );
    }
    return doc;
  }

  static pw.Widget _pdfCard(
    String code,
    CardTemplate t,
    PdfColor c1,
    PdfColor c2,
    pw.Font bold,
    pw.Font regular,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(colors: [c1, c2]),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      padding: const pw.EdgeInsets.all(10),
      // RTL directionality is required for the PDF engine to shape
      // Arabic glyphs correctly (otherwise letters print disjointed).
      child: pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
          pw.Text(
            t.networkName.isEmpty ? 'WiFi' : t.networkName,
            style: pw.TextStyle(
                font: bold, fontSize: 9, color: PdfColors.white),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              code,
              style: pw.TextStyle(
                font: bold,
                fontSize: t.fontSize * 0.8,
                color: PdfColors.white,
                letterSpacing: 1.5,
              ),
            ),
          ),
          pw.Spacer(),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (t.packageLabel.isNotEmpty)
                      pw.Text(t.packageLabel,
                          style: pw.TextStyle(
                              font: regular,
                              fontSize: 8,
                              color: PdfColors.white)),
                    if (t.price > 0)
                      pw.Text('${t.price}',
                          style: pw.TextStyle(
                              font: bold,
                              fontSize: 10,
                              color: PdfColors.white)),
                    if (t.contact.isNotEmpty)
                      pw.Text(t.contact,
                          style: pw.TextStyle(
                              font: regular,
                              fontSize: 7,
                              color: PdfColors.white)),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: t.qrPayload(code),
                  width: 34,
                  height: 34,
                ),
              ),
            ],
          ),
          ],
        ),
      ),
    );
  }

  /// Open the system print dialog with the generated sheet.
  static Future<void> print(List<String> codes, CardTemplate t) async {
    final doc = await buildPdf(codes, t);
    await Printing.layoutPdf(
      name: 'vouchers_${DateTime.now().millisecondsSinceEpoch}',
      onLayout: (_) => doc.save(),
    );
  }

  /// Share the sheet as a PDF file (Telegram/WhatsApp/drive...).
  static Future<void> sharePdf(
      List<String> codes, CardTemplate t) async {
    final doc = await buildPdf(codes, t);
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'vouchers_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}
