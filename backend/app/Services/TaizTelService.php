<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;

/**
 * Thin client for the TaizTel (yemoney.net) instant top-up API.
 *
 * Token rule (verified against the live provider):
 *   hashPassword = md5(password)
 *   token        = md5(hashPassword . transid . username . mobile)
 *
 * Every request carries: userid, mobile (target number), transid, token.
 * Credentials are read from config/taiztel.php (.env) — never from the client.
 */
class TaizTelService
{
    private string $baseUrl;
    private int $timeout;

    public function __construct()
    {
        $this->baseUrl = rtrim(config('taiztel.base_url'), '/') . '/';
        $this->timeout = config('taiztel.timeout', 30);
    }

    /**
     * Call a provider endpoint.
     *
     * @param  string      $account  'south' | 'north'
     * @param  string      $endpoint e.g. 'yem', 'mtn', 'electwater'
     * @param  array       $params   extra query params (action, amount, num, ...)
     * @param  string      $mobile   target subscriber number (9 digits) — used in the token
     * @param  string|null $transid  unique transaction id (generated when null)
     * @param  array       $postBody optional form body sent as application/x-www-form-urlencoded
     * @return array{transid:string, ok:bool, data:array, http_error:?string}
     */
    public function call(string $account, string $endpoint, array $params, string $mobile, ?string $transid = null, array $postBody = []): array
    {
        $creds = config("taiztel.accounts.$account");
        if (!$creds || empty($creds['userid']) || empty($creds['password'])) {
            return ['transid' => $transid ?? '', 'ok' => false, 'data' => [], 'http_error' => 'provider account not configured'];
        }

        $transid = $transid ?? $this->newTransId();
        $token   = $this->token($creds['password'], $transid, $creds['username'], $mobile);

        $query = array_merge([
            'userid'  => $creds['userid'],
            'mobile'  => $mobile,
            'transid' => $transid,
            'token'   => $token,
        ], $params);

        try {
            $request = Http::timeout($this->timeout)->acceptJson();
            $url = $this->baseUrl . $endpoint;
            $response = $postBody
                ? $request->asForm()->post($url . '?' . http_build_query($query), $postBody)
                : $request->get($url, $query);

            $data = $response->json() ?? [];
            return ['transid' => $transid, 'ok' => $response->successful(), 'data' => is_array($data) ? $data : [], 'http_error' => null];
        } catch (\Throwable $e) {
            return ['transid' => $transid, 'ok' => false, 'data' => [], 'http_error' => $e->getMessage()];
        }
    }

    /** Query the status of a previously submitted operation. Token must be built on the original transid. */
    public function status(string $account, string $mobile, string $transid): array
    {
        return $this->call($account, 'info', ['action' => 'status'], $mobile, $transid);
    }

    /** Unique per-operation id (ms timestamp + random suffix). */
    public function newTransId(): string
    {
        return (int) (microtime(true) * 1000) . random_int(100, 999);
    }

    private function token(string $password, string $transid, string $username, string $mobile): string
    {
        return md5(md5($password) . $transid . $username . $mobile);
    }
}
