import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

enum LegalInfoType { aboutUs, termsOfService, privacyPolicy }

class LegalInfoScreen extends StatelessWidget {
  final LegalInfoType type;

  const LegalInfoScreen({super.key, required this.type});

  String get _title => switch (type) {
        LegalInfoType.aboutUs => 'من نحن',
        LegalInfoType.termsOfService => 'شروط الخدمة',
        LegalInfoType.privacyPolicy => 'سياسة الخصوصية',
      };

  IconData get _icon => switch (type) {
        LegalInfoType.aboutUs => Icons.info_outline,
        LegalInfoType.termsOfService => Icons.article_outlined,
        LegalInfoType.privacyPolicy => Icons.privacy_tip_outlined,
      };

  List<_LegalSection> get _sections => switch (type) {
        LegalInfoType.aboutUs => const [
            _LegalSection('مرحباً بك في سايبر واي فاي', 'سايبر واي فاي منصة رقمية متكاملة لإدارة شبكات الإنترنت الموزعة عبر تقنية مايكروتك. نعمل على تقديم تجربة سهلة وآمنة لأصحاب الشبكات والوكلاء والعملاء، مع أدوات موثوقة لإدارة الخدمات والعمليات اليومية.'),
            _LegalSection('من نحن؟', 'نساعد أصحاب الشبكات على إدارة شبكاتهم وخدماتهم بمرونة، ونمكّن الوكلاء والعملاء من شحن الرصيد وشراء كروت الإنترنت بسهولة. نطوّر خدمات رقمية عملية ترفع جودة تجربة الإنترنت وتبسّط الوصول إليها.'),
            _LegalSection('مهمتنا', 'تقديم حلول تقنية مبتكرة لإدارة شبكات الإنترنت، تساعد المشغلين على تحسين جودة خدماتهم، وتمنح المستخدمين تجربة آمنة وموثوقة لشحن الرصيد وشراء الكروت.'),
            _LegalSection('رؤيتنا', 'أن نكون المنصة الرائدة لإدارة شبكات الإنترنت في المنطقة، من خلال تقنيات متطورة تلبي احتياجات العملاء والمشغلين بكفاءة ووضوح.'),
            _LegalSection('ما الذي نقدمه؟', '• أدوات لإدارة الشبكات ومتابعة المستخدمين والخدمات.\n• حلول مرنة لشحن الرصيد وشراء كروت الإنترنت.\n• إدارة مبيعات الكروت وطلبات السحب لأصحاب الشبكات.\n• عرض الشبكات المتاحة لتسهيل الوصول إلى الخدمة.'),
            _LegalSection('تواصل معنا', 'للاستفسارات أو الاقتراحات، تواصل معنا عبر البريد الإلكتروني:\ninfo@saiberwifi.net\n\nشكراً لاختيارك سايبر واي فاي؛ نجعل إدارة الإنترنت أسهل وأذكى.'),
          ],
        LegalInfoType.termsOfService => const [
            _LegalSection('قبول الشروط', 'باستخدام تطبيق سايبر واي فاي أو إنشاء حساب فيه، فإنك توافق على هذه الشروط وعلى سياسة الخصوصية. إذا لم توافق عليها، يرجى عدم استخدام التطبيق أو خدماته.'),
            _LegalSection('الحساب والمسؤولية', 'يلتزم المستخدم بتقديم بيانات دقيقة والمحافظة على سرية بيانات الدخول وعدم مشاركتها. يتحمل صاحب الحساب مسؤولية جميع الأنشطة التي تتم من خلاله، وعليه إبلاغنا فوراً عند الاشتباه بأي استخدام غير مصرح به.'),
            _LegalSection('الخدمات والمعاملات', 'يتيح التطبيق إدارة الشبكات وشراء وبيع كروت الإنترنت وشحن الرصيد وطلبات السحب وفق الصلاحيات المتاحة لكل نوع حساب. تخضع الأسعار والعمولات والأرصدة وحالات المعاملات للبيانات المعروضة داخل التطبيق وقت تنفيذ العملية.'),
            _LegalSection('طلبات السحب', 'تخضع طلبات السحب للمراجعة والتحقق قبل اعتمادها أو صرفها. قد تُطبق العمولات أو الحدود أو المتطلبات التشغيلية المعلنة في التطبيق. يلتزم صاحب الشبكة بتقديم بيانات الاستلام الصحيحة وتأكيد الاستلام عند الطلب.'),
            _LegalSection('الاستخدام المقبول', 'يُمنع استخدام الخدمة في أي نشاط مخالف للقانون، أو محاولة الوصول غير المصرح به إلى الحسابات أو الأنظمة، أو إدخال بيانات أو أكواد مضللة، أو تعطيل الخدمة أو الإضرار بالمستخدمين الآخرين.'),
            _LegalSection('التوفر والتحديثات', 'نبذل جهداً معقولاً للحفاظ على استمرارية الخدمة وأمنها، مع إمكانية إجراء صيانة أو تحديثات أو تعليق بعض الميزات عند الحاجة. قد نحدّث هذه الشروط، ويُعد استمرار الاستخدام بعد نشر التحديث قبولاً لها.'),
            _LegalSection('التواصل', 'لأي سؤال متعلق بالخدمة أو هذه الشروط، تواصل معنا عبر:\ninfo@saiberwifi.net'),
          ],
        LegalInfoType.privacyPolicy => const [
            _LegalSection('التزامنا بخصوصيتك', 'تحترم سايبر واي فاي خصوصية مستخدميها وتلتزم بحماية البيانات الشخصية التي تعالجها عند استخدام التطبيق. تشرح هذه السياسة أنواع البيانات التي نجمعها وكيف نستخدمها ونحميها.'),
            _LegalSection('البيانات التي نعالجها', 'قد تشمل بيانات الحساب مثل الاسم ورقم الهاتف والبريد الإلكتروني والصورة الشخصية، وبيانات الشبكات والفئات والكروت التي يديرها صاحب الشبكة، وبيانات المعاملات والأرصدة وطلبات السحب، وسجل استخدام الخدمة والبيانات الفنية اللازمة للتشغيل.'),
            _LegalSection('الغرض من استخدام البيانات', 'نستخدم البيانات لإنشاء الحساب وإدارته، وتقديم خدمات الشبكات والبطاقات والمدفوعات، والتحقق من العمليات ومنع الاستخدام غير المصرح به، وتحسين الخدمة، والرد على الاستفسارات، وإرسال الإشعارات المرتبطة بالحساب عند تفعيلها.'),
            _LegalSection('الإشعارات', 'قد يستخدم التطبيق خدمات الإشعارات لإرسال تحديثات مهمة مثل حالة طلب السحب أو الرسائل أو العمليات المرتبطة بالحساب. يمكنك إدارة أذونات الإشعارات من إعدادات جهازك.'),
            _LegalSection('مشاركة البيانات', 'لا نبيع بياناتك الشخصية. قد نشارك الحد الأدنى من البيانات مع مزودي الخدمات الفنيين أو الجهات المختصة عندما يكون ذلك ضرورياً لتشغيل الخدمة أو للامتثال للالتزامات القانونية أو لحماية الحقوق والأمان.'),
            _LegalSection('حماية البيانات والاحتفاظ بها', 'نطبق إجراءات تنظيمية وفنية معقولة لحماية البيانات من الوصول أو التعديل أو الإفصاح غير المصرح به. نحتفظ بالبيانات للمدة اللازمة لتقديم الخدمة والوفاء بالالتزامات القانونية وحل النزاعات ومنع الاحتيال.'),
            _LegalSection('خياراتك وحقوقك', 'يمكنك مراجعة بيانات حسابك وتعديلها من التطبيق. لطلب المساعدة المتعلقة ببياناتك أو للاستفسار عن هذه السياسة، تواصل معنا عبر البريد الإلكتروني أدناه. قد يتطلب تنفيذ بعض الطلبات الاحتفاظ ببيانات محددة إذا كان ذلك لازماً قانوناً أو تشغيلياً.'),
            _LegalSection('تحديثات السياسة والتواصل', 'قد نحدّث هذه السياسة عند تطوير الخدمة أو تغير المتطلبات. سننشر النسخة المحدثة داخل التطبيق. للاستفسارات المتعلقة بالخصوصية:\ninfo@saiberwifi.net'),
          ],
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Container(
        color: AppColors.inputBg,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary, Color(0xFF30479F)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                    child: Icon(_icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(_title, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('سايبر واي فاي', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ..._sections.map((section) => _SectionCard(section: section)),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('آخر تحديث: 22 يوليو 2026', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textGray, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalSection {
  final String title;
  final String body;

  const _LegalSection(this.title, this.body);
}

class _SectionCard extends StatelessWidget {
  final _LegalSection section;

  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 9),
          Text(section.body, style: const TextStyle(fontSize: 13, height: 1.85, color: AppColors.textDark)),
        ],
      ),
    );
  }
}
