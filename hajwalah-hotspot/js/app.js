/* ============================================================
   شبكة هجولة — HAJWALAH NETWORK
   منطق صفحة الدخول: كرت تلقائي + حساب + تشفير CHAP (MD5)
   يعتمد على كائن HS المعرف داخل login.html من متغيرات MikroTik
   ============================================================ */
(function () {
  'use strict';

  /* ---------- الإعدادات ---------- */
  var VOUCHER_LEN = 8;   // عدد خانات الكرت — عند اكتمالها يتم الدخول تلقائياً
  var AUTO_DELAY  = 350; // مهلة قصيرة قبل الإرسال التلقائي (مللي ثانية)

  /* ---------- أدوات مساعدة ---------- */
  function $(id) { return document.getElementById(id); }

  // هل قيمة ما زالت متغير قالب غير مستبدَل؟ (وضع المعاينة خارج الراوتر)
  function unresolved(v) {
    return typeof v !== 'string' || v === '' || v.indexOf('$(') !== -1;
  }

  var demo = unresolved(window.HS && HS.linkLogin);
  if (demo) {
    window.HS = {
      linkLogin: '#', linkOrig: '', chapId: '', chapCh: '',
      trial: 'no', linkStatus: 'status.html', linkLogout: 'logout.html'
    };
    var badge = $('demoBadge');
    if (badge) badge.classList.add('show');
  }

  var submitting = false;
  var autoTimer = null;

  /* ---------- إرسال الدخول (مع دعم CHAP) ---------- */
  function doLogin(username, password) {
    if (submitting || !username) return;
    submitting = true;

    var sendin = document.forms.sendin;

    if (sendin && HS.chapId && HS.chapId.indexOf('$(') === -1) {
      // http-chap: كلمة المرور = MD5(chap-id + password + chap-challenge)
      sendin.username.value = username;
      sendin.password.value = hexMD5(HS.chapId + password + HS.chapCh);
      sendin.submit();
    } else {
      // https / http-pap: إرسال مباشر بكلمة المرور
      var f = document.forms.login;
      f.username.value = username;
      f.password.value = password;
      f.action = HS.linkLogin;
      f.submit();
    }
    showAuto('جارٍ تسجيل الدخول…');
    disableButtons(true);
  }
  window.doLogin = doLogin;

  function disableButtons(state) {
    var btns = document.querySelectorAll('.btn');
    for (var i = 0; i < btns.length; i++) btns[i].disabled = state;
  }

  function showAuto(msg) {
    var n = $('autoNote');
    if (!n) return;
    n.querySelector('span').textContent = msg;
    n.classList.add('show');
  }

  /* ---------- التبويبات ---------- */
  function switchTab(name) {
    var tabs = document.querySelectorAll('.tab');
    var panes = document.querySelectorAll('.pane');
    for (var i = 0; i < tabs.length; i++)
      tabs[i].classList.toggle('active', tabs[i].getAttribute('data-tab') === name);
    for (i = 0; i < panes.length; i++)
      panes[i].classList.toggle('active', panes[i].id === 'pane-' + name);
    var target = name === 'voucher' ? $('voucher') : $('username');
    if (target) target.focus();
  }
  window.switchTab = switchTab;

  /* ---------- قائمة اختيار السرعة ---------- */
  var plan = $('plan');
  var planDesc = $('planDesc');

  function syncPlan() {
    if (!plan) return;
    var o = plan.options[plan.selectedIndex];
    if (planDesc && o) planDesc.textContent = o.getAttribute('data-desc') || '';
    // نسخ الباقة لنموذج CHAP المخفي حتى تُرسل مع بيانات الدخول
    var sendin = document.forms.sendin;
    if (sendin && sendin.plan) sendin.plan.value = plan.value;
    try { localStorage.setItem('hj-plan', plan.value); } catch (e) {}
  }

  if (plan) {
    try {
      var saved = localStorage.getItem('hj-plan');
      if (saved) plan.value = saved;
    } catch (e) {}
    plan.addEventListener('change', syncPlan);
    syncPlan();
  }

  /* ---------- إدخال الكرت: تنقية + دخول تلقائي ---------- */
  var voucher = $('voucher');
  var meter = $('voucherMeter');

  function sanitize(v) {
    return v.replace(/[^0-9a-zA-Z]/g, '').toUpperCase();
  }

  if (voucher) {
    voucher.addEventListener('input', function () {
      var clean = sanitize(voucher.value);
      if (voucher.value !== clean) voucher.value = clean;

      var pct = Math.min(100, Math.round((clean.length / VOUCHER_LEN) * 100));
      if (meter) meter.firstElementChild.style.width = pct + '%';
      voucher.classList.toggle('ready', clean.length >= VOUCHER_LEN);

      clearTimeout(autoTimer);
      if (clean.length >= VOUCHER_LEN) {
        showAuto('تم التعرف على الكرت — دخول تلقائي…');
        autoTimer = setTimeout(function () { doLogin(clean, clean); }, AUTO_DELAY);
      }
    });

    voucher.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        voucherGo();
      }
    });
  }

  // زر «دخول» أسفل حقل الكرت
  window.voucherGo = function () {
    if (!voucher) return;
    var clean = sanitize(voucher.value);
    if (clean.length > 0) doLogin(clean, clean);
    else voucher.focus();
  };

  /* ---------- نموذج الحساب ---------- */
  var loginForm = document.forms.login;
  if (loginForm) {
    loginForm.addEventListener('submit', function (e) {
      e.preventDefault();
      var u = $('username').value.trim();
      var p = $('password').value;
      if (!u) { $('username').focus(); return; }
      doLogin(u, p);
    });
  }

  /* ---------- إظهار/إخفاء كلمة المرور ---------- */
  var eye = $('eyeBtn');
  if (eye) {
    eye.addEventListener('click', function () {
      var p = $('password');
      var show = p.type === 'password';
      p.type = show ? 'text' : 'password';
      eye.classList.toggle('on', show);
      p.focus();
    });
  }

  /* ---------- كرت عبر الرابط ?v=CODE أو #CODE ---------- */
  function cardFromUrl() {
    var m = /[?&#](?:v|card|code)=([0-9a-zA-Z]+)/.exec(location.href);
    if (!m && location.hash) m = /^#([0-9a-zA-Z]{4,})$/.exec(location.hash);
    return m ? m[1].toUpperCase() : '';
  }
  var urlCard = cardFromUrl();
  if (urlCard && voucher) {
    switchTab('voucher');
    voucher.value = sanitize(urlCard);
    voucher.dispatchEvent(new Event('input'));
  }

  /* ---------- تجربة مجانية (Trial) ---------- */
  var trialBtn = $('trialBtn');
  if (trialBtn && HS.trial === 'yes' && !demo) {
    trialBtn.style.display = '';
    trialBtn.addEventListener('click', function () {
      location.href = HS.linkLogin + '?dst=' + encodeURIComponent(HS.linkOrig) +
                      '&username=T-' + (HS.macEsc || '');
    });
  }
})();
