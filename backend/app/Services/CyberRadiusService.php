<?php

namespace App\Services;

use App\Models\CyberRadiusEvent;
use App\Models\CyberSession;
use App\Models\CyberSubscription;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * CyberNet RADIUS bridge (CYB-04).
 *
 * - ingestEvents(): accepts the engine's at-least-once ledger batch,
 *   dedupes on (source_file, source_offset), maintains
 *   cyber_active_sessions and accumulates consumed_bytes.
 * - authorize(): translates the stored subscription into the live
 *   RADIUS reply (Mikrotik-Rate-Limit + remaining data/time).
 * - disconnectDue(): the cut-off sweep — marks exhausted/expired
 *   subscriptions and sends CoA Disconnect to each session's NAS.
 *
 * CoA transport: HTTPS POST to the engine when
 * cyber.radius.engine_url is configured (forward channel), else a
 * raw RFC 5176 Disconnect-Request UDP packet to nas_ip:3799.
 */
class CyberRadiusService
{
    private const COA_MAX_ATTEMPTS = 5;

    public function __construct(
        private readonly CyberBillingService $billing,
    ) {}

    /**
     * Ingest a batch of engine events.
     *
     * @return array{accepted: int, duplicates: int}
     */
    public function ingestEvents(array $events): array
    {
        $accepted = $duplicates = 0;

        foreach ($events as $event) {
            $sourceFile = (string) ($event['source']['file'] ?? 'unknown');
            $sourceOffset = (int) ($event['source']['offset'] ?? 0);
            $type = (string) ($event['type'] ?? 'other');
            $simNo = $event['subscriber'] ?? null;
            $sessionId = $event['session_id'] ?? null;

            try {
                $record = CyberRadiusEvent::create([
                    'source_file' => $sourceFile,
                    'source_offset' => $sourceOffset,
                    'type' => $type,
                    'sim_no' => $simNo,
                    'session_id' => $sessionId,
                    'payload' => $event,
                    'processed_at' => now(),
                ]);
            } catch (QueryException $e) {
                $duplicates++;

                continue;
            }

            $accepted++;
            $this->process($record);
        }

        return ['accepted' => $accepted, 'duplicates' => $duplicates];
    }

    /**
     * Live authorize answer for RADIUS: the stored reply translated
     * into remaining data/time. Null when nothing is active — the
     * caller turns that into Access-Reject.
     *
     * @return array<string, int|string>|null
     */
    public function authorize(string $simNo): ?array
    {
        try {
            $subscriber = $this->billing->subscriberBySim($simNo);
        } catch (CyberBillingException $e) {
            return null;
        }

        if (in_array($subscriber->status ?? 'active', ['suspended', 'rejected'], true)) {
            return null;
        }

        $subscription = $this->billing->activeSubscription((int) $subscriber->id);
        if (! $subscription || $subscription->is_due) {
            return null;
        }

        $stored = $subscription->radius_reply ?? [];
        $reply = [
            'Mikrotik-Rate-Limit' => $stored['Mikrotik-Rate-Limit']
                ?? $subscription->package?->rate_limit
                ?? CyberBillingService::DEFAULT_RATE_LIMIT,
            'Session-Timeout' => max(0, now()->diffInSeconds($subscription->ends_at, false)),
        ];
        if ($subscription->data_limit_bytes !== null) {
            $reply['Mikrotik-Total-Limit'] = max(
                0,
                $subscription->data_limit_bytes - $subscription->consumed_bytes
            );
        }

        return $reply;
    }

    /**
     * The cut-off engine. Marks due subscriptions ended and sends CoA
     * Disconnect for their live sessions; also retries sessions left
     * open after their subscription ended.
     *
     * @return array{ended: int, coa_sent: int, coa_failed: int}
     */
    public function disconnectDue(): array
    {
        $stats = ['ended' => 0, 'coa_sent' => 0, 'coa_failed' => 0];

        $due = CyberSubscription::where('status', CyberSubscription::STATUS_ACTIVE)
            ->where(function ($q) {
                $q->where('ends_at', '<=', now())
                    ->orWhere(function ($q2) {
                        $q2->whereNotNull('data_limit_bytes')
                            ->whereColumn('consumed_bytes', '>=', 'data_limit_bytes');
                    });
            })
            ->get();

        foreach ($due as $subscription) {
            $this->endSubscription($subscription);
            $stats['ended']++;
        }

        // Every session hanging off an ended subscription gets CoA.
        $sessions = CyberSession::where('status', 'active')
            ->where('coa_attempts', '<', self::COA_MAX_ATTEMPTS)
            ->whereHas('subscription', function ($q) {
                $q->where('status', '!=', CyberSubscription::STATUS_ACTIVE);
            })
            ->get();

        foreach ($sessions as $session) {
            $this->disconnectSession($session)
                ? $stats['coa_sent']++
                : $stats['coa_failed']++;
        }

        return $stats;
    }

    /**
     * Mark a subscription ended with the right terminal status and
     * disconnect its sessions. Idempotent — a no-op when already ended.
     */
    public function endSubscription(CyberSubscription $subscription): void
    {
        if ($subscription->status !== CyberSubscription::STATUS_ACTIVE) {
            return;
        }

        $reason = $subscription->ends_at !== null && $subscription->ends_at->isPast()
            ? CyberSubscription::STATUS_EXPIRED
            : CyberSubscription::STATUS_EXHAUSTED;

        $subscription->update([
            'status' => $reason,
            'ended_at' => now(),
        ]);

        foreach ($subscription->sessions()->where('status', 'active')->get() as $session) {
            $this->disconnectSession($session);
        }
    }

    /**
     * Send CoA Disconnect for one session and close it. Returns
     * whether a disconnect was dispatched (the session is closed
     * either way — the NAS may already have dropped it).
     */
    public function disconnectSession(CyberSession $session): bool
    {
        $sent = $this->sendCoaDisconnect($session);

        $session->update([
            'status' => 'closed',
            'close_reason' => $sent ? 'coa_disconnect' : 'coa_unavailable',
            'coa_attempts' => $session->coa_attempts + 1,
            'closed_at' => now(),
        ]);

        return $sent;
    }

    private function process(CyberRadiusEvent $event): void
    {
        try {
            match ($event->type) {
                'acct.start' => $this->onAcctStart($event),
                'acct.interim', 'acct.stop' => $this->onAcctUsage($event),
                default => null,
            };
        } catch (\Throwable $e) {
            Log::warning("CyberNet radius event {$event->type} failed: ".$e->getMessage());
        }
    }

    private function onAcctStart(CyberRadiusEvent $event): void
    {
        if (! $event->session_id) {
            return;
        }

        $payload = $event->payload;
        $subscriberId = $this->subscriberIdFor($event->sim_no);
        $subscription = $subscriberId !== null
            ? $this->billing->activeSubscription($subscriberId)
            : null;

        CyberSession::updateOrCreate(
            [
                'nas_identifier' => (string) ($payload['nas'] ?? ''),
                'session_id' => $event->session_id,
            ],
            [
                'subscriber_id' => $subscriberId,
                'subscription_id' => $subscription?->id,
                'sim_no' => $event->sim_no,
                'nas_ip' => $payload['nas_ip'] ?? null,
                'started_at' => $this->eventTime($event),
                'last_seen_at' => $this->eventTime($event),
                'status' => 'active',
            ]
        );
    }

    /**
     * Interim/stop records carry cumulative octets for the session;
     * the delta since the last record is what hits consumed_bytes.
     */
    private function onAcctUsage(CyberRadiusEvent $event): void
    {
        if (! $event->session_id) {
            return;
        }

        $attrs = $event->payload['attributes'] ?? [];
        $input = $this->octets($attrs, 'Acct-Input-Octets', 'Acct-Input-Gigawords');
        $output = $this->octets($attrs, 'Acct-Output-Octets', 'Acct-Output-Gigawords');

        $session = CyberSession::where('session_id', $event->session_id)
            ->where('nas_identifier', (string) ($event->payload['nas'] ?? ''))
            ->first()
            ?? CyberSession::where('session_id', $event->session_id)->first();

        if (! $session) {
            // Interim without a start (backend joined mid-flight) —
            // open the shell so the delta anchors somewhere.
            $session = CyberSession::create([
                'nas_identifier' => (string) ($event->payload['nas'] ?? ''),
                'session_id' => $event->session_id,
                'sim_no' => $event->sim_no,
                'nas_ip' => $event->payload['nas_ip'] ?? null,
                'subscriber_id' => $this->subscriberIdFor($event->sim_no),
                'status' => 'active',
                'last_seen_at' => $this->eventTime($event),
            ]);
        }

        $previousTotal = $session->total_octets;
        $newTotal = $input + $output;

        $session->update([
            'input_octets' => $input,
            'output_octets' => $output,
            'last_seen_at' => $this->eventTime($event),
            'status' => $event->type === 'acct.stop' ? 'closed' : 'active',
            'closed_at' => $event->type === 'acct.stop' ? $this->eventTime($event) : $session->closed_at,
            'close_reason' => $event->type === 'acct.stop' ? 'acct_stop' : $session->close_reason,
        ]);

        if ($newTotal <= $previousTotal) {
            return;
        }

        $subscription = $session->subscription_id
            ? CyberSubscription::find($session->subscription_id)
            : null;
        if (! $subscription && $session->subscriber_id) {
            $subscription = $this->billing->activeSubscription((int) $session->subscriber_id);
            if ($subscription) {
                $session->update(['subscription_id' => $subscription->id]);
            }
        }

        if (! $subscription || $subscription->status !== CyberSubscription::STATUS_ACTIVE) {
            return;
        }

        $subscription->increment('consumed_bytes', $newTotal - $previousTotal);
        $subscription->refresh();

        if ($subscription->is_due) {
            $this->endSubscription($subscription);
        }
    }

    /**
     * Prefer the engine HTTPS channel when configured; fall back to a
     * raw Disconnect-Request datagram to the NAS.
     */
    private function sendCoaDisconnect(CyberSession $session): bool
    {
        $engineUrl = rtrim((string) config('cyber.radius.engine_url'), '/');
        if ($engineUrl !== '') {
            try {
                $response = Http::withToken((string) config('cyber.radius.engine_token'))
                    ->timeout(10)
                    ->post($engineUrl.'/disconnect', [
                        'session_id' => $session->session_id,
                        'nas_ip' => $session->nas_ip,
                        'user_name' => $session->sim_no,
                    ]);
                if ($response->successful()) {
                    return true;
                }
                Log::warning('CyberNet engine disconnect HTTP '.$response->status());
            } catch (\Throwable $e) {
                Log::warning('CyberNet engine disconnect failed: '.$e->getMessage());
            }
        }

        return $this->sendRawCoa($session);
    }

    /**
     * RFC 5176 Disconnect-Request (code 40) to nas_ip:coa_port.
     * Request Authenticator = MD5(Code|ID|Len|16×0|Attrs|Secret).
     */
    private function sendRawCoa(CyberSession $session): bool
    {
        $nasIp = $session->nas_ip;
        $secret = (string) config('cyber.radius.secret', '');
        if (! $nasIp || $secret === '') {
            return false;
        }

        $attrs = $this->radiusAttr(1, (string) $session->sim_no)          // User-Name
            .$this->radiusAttr(44, $session->session_id)                  // Acct-Session-Id
            .$this->radiusAttr(4, inet_pton($nasIp));                     // NAS-IP-Address

        $id = random_int(0, 255);
        $length = 20 + strlen($attrs);
        $authenticator = md5(pack('CCN', 40, $id, $length).str_repeat("\0", 16).$attrs.$secret, true);
        $packet = pack('CCN', 40, $id, $length).$authenticator.$attrs;

        $socket = @fsockopen('udp://'.$nasIp, (int) config('cyber.radius.coa_port', 3799));
        if (! $socket) {
            Log::warning("CyberNet CoA: cannot open UDP socket to {$nasIp}");

            return false;
        }

        fwrite($socket, $packet);
        fclose($socket);

        return true;
    }

    private function radiusAttr(int $type, string $value): string
    {
        return pack('CC', $type, strlen($value) + 2).$value;
    }

    private function octets(array $attrs, string $octetsKey, string $gigawordsKey): int
    {
        $octets = (int) ($attrs[$octetsKey] ?? 0);
        $gigawords = (int) ($attrs[$gigawordsKey] ?? 0);

        return ($gigawords << 32) + $octets;
    }

    private function subscriberIdFor(?string $simNo): ?int
    {
        if (! $simNo || ! Schema::hasTable('cyber_subscribers')) {
            return null;
        }

        $id = DB::table('cyber_subscribers')->where('sim_no', $simNo)->value('id');

        return $id === null ? null : (int) $id;
    }

    private function eventTime(CyberRadiusEvent $event): \Illuminate\Support\Carbon
    {
        $loggedAt = $event->payload['logged_at'] ?? null;
        if ($loggedAt) {
            try {
                return \Illuminate\Support\Carbon::parse($loggedAt);
            } catch (\Throwable $e) {
                // fall through to now()
            }
        }

        return now();
    }
}
