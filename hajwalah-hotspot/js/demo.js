/* ============================================================
   شبكة هجولة — وضع المعاينة
   عند فتح الصفحات خارج الراوتر تبقى متغيرات $(...) حرفية،
   هذا الملف يستبدلها بقيم محلية ويخفي العناصر الفارغة
   حتى تظهر الصفحة سليمة أثناء المعاينة والاختبار.
   ============================================================ */
(function () {
  'use strict';

  var MAP = {
    '$(link-login)':       'login.html',
    '$(link-login-only)':  'login.html',
    '$(link-status)':      'status.html',
    '$(link-logout)':      'logout.html',
    '$(link-redirect)':    'status.html',
    '$(link-orig)':        '',
    '$(link-orig-esc)':    '',
    '$(advert-interval)':  '10'
  };

  function unres(v) { return typeof v === 'string' && v.indexOf('$(') !== -1; }
  function swap(v) {
    for (var k in MAP) if (v.indexOf(k) !== -1) v = v.split(k).join(MAP[k]);
    return v;
  }

  // 1) الروابط والنماذج ووسوم meta refresh
  var els = document.querySelectorAll('a[href], form[action]');
  for (var i = 0; i < els.length; i++) {
    var a = els[i], attr = a.tagName === 'FORM' ? 'action' : 'href';
    var v = a.getAttribute(attr);
    if (unres(v)) a.setAttribute(attr, swap(v));
  }
  var metas = document.querySelectorAll('meta[http-equiv="refresh"]');
  for (i = 0; i < metas.length; i++) {
    var c = metas[i].getAttribute('content');
    if (unres(c)) metas[i].setAttribute('content', swap(c));
  }

  // 2) إزالة عقد النصوص التي تحوي متغيرات غير مستبدلة (باستثناء script/style)
  if (document.body.innerHTML.indexOf('$(') !== -1) {
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    var dead = [];
    while (walker.nextNode()) {
      var n = walker.currentNode;
      if (n.nodeValue.indexOf('$(') !== -1 &&
          n.parentNode && n.parentNode.tagName !== 'SCRIPT' && n.parentNode.tagName !== 'STYLE') {
        dead.push(n);
      }
    }
    for (i = 0; i < dead.length; i++) dead[i].parentNode.removeChild(dead[i]);
  }

  // 3) إخفاء التنبيهات الفارغة (رسالة $(error) غير موجودة بالمعاينة)
  var alerts = document.querySelectorAll('.alert');
  for (i = 0; i < alerts.length; i++) {
    if (alerts[i].textContent.trim() === '') alerts[i].style.display = 'none';
  }
})();
