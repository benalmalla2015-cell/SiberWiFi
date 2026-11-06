import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'reports_api.dart';

/// ACC-09 — كشف التحصيل اليومي (PLAN §5: collections_screen PDF).
///
/// Builds an A4 RTL statement for one day's collections register:
/// header, per-row table (party/type/box/amount), totals, and a
/// journal-reconciliation line proving the printed figure ties to
/// the posted entries. Cairo font matches the app identity.
class CollectionsDailyPdf {
  CollectionsDailyPdf._();

  static Future<pw.Document> buildPdf(AccCollectionsDay day) async {
    final bold = await PdfGoogleFonts.cairoBold();
    final regular = await PdfGoogleFonts.cairoRegular();
    const navy = PdfColor.fromInt(0xFF1E2D7D);
    const red = PdfColor.fromInt(0xFFE31E24);

    pw.Widget cell(String text,
            {bool header = false,
            bool numeric = false,
            pw.Font? font}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 6, vertical: 5),
          child: pw.Text(
            text,
            textDirection: pw.TextDirection.rtl,
            textAlign:
                numeric ? pw.TextAlign.left : pw.TextAlign.right,
            style: pw.TextStyle(
              font: font ?? (header ? bold : regular),
              fontSize: header ? 8.5 : 8,
              color: header ? PdfColors.white : PdfColors.black,
            ),
          ),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: navy),
        children: [
          cell('المبلغ (بالأساس)', header: true, numeric: true),
          cell('العملة', header: true),
          cell('الصندوق', header: true),
          cell('النوع', header: true),
          cell('الطرف', header: true),
          cell('#', header: true),
        ],
      ),
      for (var i = 0; i < day.rows.length; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isOdd
                ? const PdfColor.fromInt(0xFFF8F9FC)
                : PdfColors.white,
          ),
          children: [
            cell(day.rows[i].baseAmount.toStringAsFixed(0),
                numeric: true, font: bold),
            cell(day.rows[i].currency == 'south' ? 'جنوب' : 'شمال'),
            cell(day.rows[i].boxName ?? 'الرئيسي'),
            cell(day.rows[i].partyLabel),
            cell(day.rows[i].partyName),
            cell('${day.rows[i].id}'),
          ],
        ),
    ];

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: navy,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('كشف التحصيل اليومي',
                      style: pw.TextStyle(
                          font: bold,
                          fontSize: 15,
                          color: PdfColors.white)),
                  pw.Text(day.date,
                      style: pw.TextStyle(
                          font: regular,
                          fontSize: 11,
                          color: PdfColors.white)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(
                  color: const PdfColor.fromInt(0xFFEBEFF8),
                  width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(70),
                1: pw.FixedColumnWidth(40),
                2: pw.FlexColumnWidth(2),
                3: pw.FixedColumnWidth(55),
                4: pw.FlexColumnWidth(3),
                5: pw.FixedColumnWidth(30),
              },
              children: rows,
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF8F9FC),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'الإجمالي: ${day.totalBase.toStringAsFixed(0)} (${day.count} تحصيلاً)',
                    style: pw.TextStyle(font: bold, fontSize: 11),
                  ),
                  pw.Text(
                    'مطابق للقيود: ${day.journalBase.toStringAsFixed(0)}',
                    style: pw.TextStyle(
                        font: regular, fontSize: 9, color: red),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            if (day.byBox.isNotEmpty) ...[
              pw.Text('حسب الصندوق',
                  style: pw.TextStyle(font: bold, fontSize: 10)),
              pw.SizedBox(height: 6),
              for (final b in day.byBox)
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment:
                        pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '${b['box_name']} — ${b['count']} تحصيلاً',
                        style: pw.TextStyle(
                            font: regular, fontSize: 8.5),
                      ),
                      pw.Text(
                        '${(b['total'] as num).toStringAsFixed(0)} ${b['currency'] == 'south' ? 'جنوب' : 'شمال'}',
                        style: pw.TextStyle(
                            font: bold, fontSize: 8.5),
                      ),
                    ],
                  ),
                ),
            ],
            pw.Spacer(),
            pw.Center(
              child: pw.Text(
                'سايبر WiFi — نظام محاسبة الشبكة',
                style: pw.TextStyle(
                    font: regular,
                    fontSize: 8,
                    color: PdfColors.grey600),
              ),
            ),
          ],
        ),
      ),
    );
    return doc;
  }

  /// Open the system print dialog with the built statement.
  static Future<void> print(AccCollectionsDay day) async {
    final doc = await buildPdf(day);
    await Printing.layoutPdf(
      name: 'collections_${day.date}',
      onLayout: (_) => doc.save(),
    );
  }

  /// Share the statement PDF (WhatsApp/Telegram/drive...).
  static Future<void> sharePdf(AccCollectionsDay day) async {
    final doc = await buildPdf(day);
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'collections_${day.date}.pdf',
    );
  }
}
