<?php
$base = 'https://staging.saiberwifi.net/api';

function req($method, $url, $body = null, $token = null) {
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => array_filter([
            'Accept: application/json',
            $body ? 'Content-Type: application/json' : null,
            $token ? "Authorization: Bearer $token" : null,
        ]),
        CURLOPT_POSTFIELDS => $body ? json_encode($body) : null,
        CURLOPT_TIMEOUT => 30,
        CURLOPT_SSL_VERIFYPEER => false,
    ]);
    $res = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return [$code, $res];
}

[$c, $j] = req('POST', "$base/auth/login",
    ['phone' => '700000002', 'password' => '123456']);
$d = json_decode($j, true);
$token = $d['data']['token'] ?? $d['token'] ?? null;
echo "login=$c token=" . ($token ? 'OK' : 'FAIL ' . substr($j,0,200)) . "\n";
if (!$token) exit(1);

foreach (['/network-owner/accounting/me',
          '/network-owner/accounting/billing/entitlements'] as $p) {
    [$c, $j] = req('GET', "$base$p", null, $token);
    echo "GET $p => $c\n" . substr($j, 0, 700) . "\n\n";
}
