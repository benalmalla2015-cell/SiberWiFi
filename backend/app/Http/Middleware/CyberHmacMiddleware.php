<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * CYB-14 — request-signature gate for /api/cyber/*.
 *
 * The client (ApiGuard interceptor) sends:
 *   X-Cyber-Ts    unix seconds         — replay window ±300s
 *   X-Cyber-Nonce uuid per request      — log-rejected duplicates
 *   X-Cyber-Device enrolled device id   — bound into the signature
 *   X-Cyber-Sig   hex HMAC-SHA256(key,
 *                 "METHOD|/cyber/path|TS|NONCE|SHA256(body)|device")
 *
 * Activated only when CYBER_HMAC_ENABLED=true AND CYBER_HMAC_KEY is set;
 * local/dev stacks without the key keep working unchanged.
 */
class CyberHmacMiddleware
{
    private const MAX_SKEW = 300; // seconds

    public function handle(Request $request, Closure $next): Response
    {
        $key = (string) config('cyber.hmac.key', '');
        if ($key === '') {
            return $next($request); // dev mode — nothing configured
        }

        $ts = $request->header('X-Cyber-Ts');
        $nonce = $request->header('X-Cyber-Nonce');
        $device = (string) $request->header('X-Cyber-Device', '');
        $sig = (string) $request->header('X-Cyber-Sig', '');

        if (!$ts || !$nonce || $sig === '') {
            return $this->reject('unsigned request');
        }
        if (abs(time() - (int) $ts) > self::MAX_SKEW) {
            return $this->reject('stale timestamp');
        }

        // Multipart bodies are streams — the client signs the marker
        // 'multipart' instead; the signature still binds method/path/ts.
        $bodyHash = str_starts_with(
            (string) $request->header('Content-Type', ''), 'multipart/'
        )
            ? hash('sha256', 'multipart')
            : hash('sha256', $request->getContent());

        // options.path on the client is base-relative ('/cyber/...').
        $path = '/' . preg_replace('#^api/#', '', $request->path());

        $canonical = implode('|', [
            strtoupper($request->method()),
            $path,
            $ts,
            $nonce,
            $bodyHash,
            $device,
        ]);

        $expected = hash_hmac('sha256', $canonical, $key);
        if (!hash_equals($expected, $sig)) {
            return $this->reject('bad signature');
        }

        // Cross-check the device binding claim when the route carries
        // device_id — a signed request for another device still fails.
        $claimed = $request->input('device_id');
        if ($claimed !== null && $device !== '' && $claimed !== $device) {
            return $this->reject('device mismatch');
        }

        return $next($request);
    }

    private function reject(string $why): Response
    {
        return response()->json([
            'success' => false,
            'message' => 'طلب غير مصرّح — ' . $why,
        ], 403);
    }
}
