# SaiberWiFi — تشغيل بيئة اختبار MikroTik المحلية
# يشغّل محاكي RouterOS API + يوجه منفذ الهاتف إليه عبر ADB reverse
# الاستخدام: شغّل هذا الملف ثم في التطبيق استخدم host=127.0.0.1 port=8728 dev/dev123

$sim = "C:\Users\HP\Desktop\saiberwifi\routeros_sim.py"
$adb = "C:\Users\HP\AppData\Local\Android\Sdk\platform-tools\adb.exe"

# 1) شغّل المحاكي إن لم يكن يعمل
$listening = Test-NetConnection -ComputerName 127.0.0.1 -Port 8728 -InformationLevel Quiet -WarningAction SilentlyContinue
if (-not $listening) {
    Start-Process -FilePath "pyw" -ArgumentList "`"$sim`""
    Start-Sleep 2
    Write-Output "[+] RouterOS simulator started (port 8728)"
} else {
    Write-Output "[=] Simulator already running"
}

# 2) وجّه منفذ الهاتف إلى الكمبيوتر عبر USB
& $adb reverse tcp:8728 tcp:8728
Write-Output "[+] adb reverse active -> phone 127.0.0.1:8728 = this PC"
Write-Output ""
Write-Output "في التطبيق التجريبي -> أجهزة MikroTik -> إضافة راوتر:"
Write-Output "  Host: 127.0.0.1 | Port: 8728 | User: dev | Pass: dev123"
