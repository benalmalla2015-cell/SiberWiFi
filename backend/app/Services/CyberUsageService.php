<?php

namespace App\Services;

use App\Models\CyberRadiusEvent;
use App\Models\CyberSession;
use App\Models\CyberSubscriber;
use App\Models\CyberSubscription;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * CyberNet usage analytics (CYB-09).
 *
 * - sessionsFor(): the subscriber session log. Live rows and the
 *   finished archive both live in cyber_active_sessions — CYB-04 keeps
 *   closed rows permanently, so no separate archive table is needed
 *   for the pilot (a dedicated cyber_session_logs migration stays
 *   available if history ever needs richer detail).
 * - dailyUsage(): per-day consumption for the client-app chart. The
 *   acct.interim/stop ledger in cyber_radius_events carries cumulative
 *   octets, so each day's figure is the sum of positive deltas whose
 *   event timestamp falls on that day.
 * - reconcile(): trial accuracy check — Σ session octets linked to a
 *   subscription must equal what was debited from the package
 *   (consumed_bytes); session bytes billed to no package are reported
 *   as unattributed.
 */
class CyberUsageService
{
    private const BYTES_PER_GB = 1073741824;

    public function __construct(
        private readonly CyberBillingService $billing,
    ) {}

    /**
     * Sessions visible to a subscriber: matched on subscriber_id, with
     * sim_no as a fallback for rows ingested before the subscriber
     * link resolved (acct.start can land ahead of it).
     */
    public function sessionsQuery(int $subscriberId, ?string $simNo): Builder
    {
        return CyberSession::query()->where(function (Builder $q) use ($subscriberId, $simNo) {
            $q->where('subscriber_id', $subscriberId);
            if ($simNo !== null && $simNo !== '') {
                $q->orWhere('sim_no', $simNo);
            }
        });
    }

    /**
     * The session log, newest first — live (active) and archived
     * (closed) rows in one ordered feed.
     */
    public function sessionsFor(int $subscriberId, ?string $simNo, int $limit = 50): Collection
    {
        return $this->sessionsQuery($subscriberId, $simNo)
            ->orderByRaw('COALESCE(started_at, last_seen_at, created_at) DESC')
            ->orderByDesc('id')
            ->limit(max(1, min($limit, 500)))
            ->get();
    }

    /**
     * Per-day consumption for the app chart over the last $days days.
     * Every in-window day is present (zero-filled) so the chart never
     * has to guess; out-of-window deltas are dropped but still re-base
     * the cumulative counter.
     *
     * @return array{from: string, to: string, days: int, daily: array<int, array{date: string, bytes: int, gb: float}>, total_bytes: int, total_gb: float}
     */
    public function dailyUsage(int $subscriberId, ?string $simNo, int $days = 7): array
    {
        $days = max(1, $days);
        $to = now()->startOfDay();
        $from = $to->copy()->subDays($days - 1);

        $buckets = [];
        for ($d = $from->copy(); $d->lte($to); $d->addDay()) {
            $buckets[$d->toDateString()] = 0;
        }

        foreach ($this->sessionsQuery($subscriberId, $simNo)->get() as $session) {
            $events = $this->usageEvents($session);

            if ($events->isEmpty()) {
                // No interim/stop ledger rows (seeded data, or the
                // backend only ever saw the start) — anchor the
                // session's counters to its last activity day.
                $day = $this->dayOf($session->closed_at ?? $session->last_seen_at ?? $session->created_at);
                if ($day !== null && isset($buckets[$day]) && $session->total_octets > 0) {
                    $buckets[$day] += $session->total_octets;
                }
                continue;
            }

            $previous = 0;
            foreach ($events as $event) {
                $total = $this->payloadOctets($event);
                $delta = $total - $previous;
                $previous = $total; // counter reset re-bases the next delta
                if ($delta <= 0) {
                    continue;
                }
                $day = $this->dayOf($event->payload['logged_at'] ?? null) ?? $this->dayOf($event->created_at);
                if ($day !== null && isset($buckets[$day])) {
                    $buckets[$day] += $delta;
                }
            }
        }

        $daily = [];
        foreach ($buckets as $date => $bytes) {
            $daily[] = ['date' => $date, 'bytes' => $bytes, 'gb' => $this->toGb($bytes)];
        }

        return [
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'days' => $days,
            'daily' => $daily,
            'total_bytes' => array_sum($buckets),
            'total_gb' => $this->toGb(array_sum($buckets)),
        ];
    }

    /**
     * Trial reconcile: for every subscription, compare what billing
     * debited (consumed_bytes) against what RADIUS actually recorded
     * (Σ input+output octets on linked sessions). Also surfaces
     * sessions carrying traffic that no package ever absorbed.
     *
     * @return array{sim_no: ?string, generated_at: string, checked: int, matched: int, mismatched: int, subscriptions: array, unattributed: array, clean: bool}
     */
    public function reconcile(?string $simNo = null): array
    {
        $subscriptions = CyberSubscription::query()
            ->when($simNo, function (Builder $q) use ($simNo) {
                $q->whereIn('subscriber_id', function ($sub) use ($simNo) {
                    $sub->select('id')->from('cyber_subscribers')->where('sim_no', $simNo);
                });
            })
            ->orderBy('id')
            ->get();

        $sims = CyberSubscriber::whereIn('id', $subscriptions->pluck('subscriber_id')->unique()->all())
            ->pluck('sim_no', 'id');

        $rows = [];
        $mismatched = 0;
        foreach ($subscriptions as $sub) {
            $sessionBytes = (int) CyberSession::where('subscription_id', $sub->id)
                ->sum(DB::raw('input_octets + output_octets'));
            $diff = (int) $sub->consumed_bytes - $sessionBytes;
            if ($diff !== 0) {
                $mismatched++;
            }
            $rows[] = [
                'subscription_id' => $sub->id,
                'sim_no' => $sims[$sub->subscriber_id] ?? null,
                'status' => $sub->status,
                'consumed_bytes' => (int) $sub->consumed_bytes,
                'sessions_bytes' => $sessionBytes,
                'diff_bytes' => $diff,
                'result' => $diff === 0 ? 'ok' : 'diff',
            ];
        }

        $unattributedQuery = CyberSession::whereRaw('input_octets + output_octets > 0')
            ->where(function (Builder $q) {
                $q->whereNull('subscription_id')
                    ->orWhereNotIn('subscription_id', CyberSubscription::select('id'));
            });
        if ($simNo) {
            $unattributedQuery->where('sim_no', $simNo);
        }
        $unattributedSessions = $unattributedQuery
            ->orderByDesc('last_seen_at')
            ->get(['id', 'sim_no', 'session_id', 'nas_identifier', 'input_octets', 'output_octets']);

        $unattributedBytes = (int) $unattributedSessions->sum(
            fn (CyberSession $s) => $s->total_octets
        );

        return [
            'sim_no' => $simNo,
            'generated_at' => now()->toIso8601String(),
            'checked' => count($rows),
            'matched' => count($rows) - $mismatched,
            'mismatched' => $mismatched,
            'subscriptions' => $rows,
            'unattributed' => [
                'sessions' => $unattributedSessions->count(),
                'bytes' => $unattributedBytes,
                'list' => $unattributedSessions->take(20)->map(fn (CyberSession $s) => [
                    'id' => $s->id,
                    'sim_no' => $s->sim_no,
                    'session_id' => $s->session_id,
                    'host' => $s->nas_identifier,
                    'bytes' => $s->total_octets,
                ])->values()->all(),
            ],
            'clean' => $mismatched === 0 && $unattributedBytes === 0,
        ];
    }

    /**
     * The interim/stop ledger rows for one session, in ledger order.
     * Acct-Session-Id is only unique per NAS, so events reporting a
     * different nas are excluded — a same-named session elsewhere must
     * not bleed into this session's deltas.
     */
    private function usageEvents(CyberSession $session): Collection
    {
        $nas = (string) ($session->nas_identifier ?? '');

        return CyberRadiusEvent::where('session_id', $session->session_id)
            ->whereIn('type', ['acct.interim', 'acct.stop'])
            ->orderBy('source_file')
            ->orderBy('source_offset')
            ->get()
            ->filter(function (CyberRadiusEvent $event) use ($nas) {
                $eventNas = $event->payload['nas'] ?? null;

                return $eventNas === null || (string) $eventNas === $nas;
            })
            ->values();
    }

    /**
     * Cumulative octets reported by one accounting event, mirroring
     * CyberRadiusService's Gigawords handling.
     */
    private function payloadOctets(CyberRadiusEvent $event): int
    {
        $attrs = $event->payload['attributes'] ?? [];
        $input = ((int) ($attrs['Acct-Input-Gigawords'] ?? 0) << 32)
            + (int) ($attrs['Acct-Input-Octets'] ?? 0);
        $output = ((int) ($attrs['Acct-Output-Gigawords'] ?? 0) << 32)
            + (int) ($attrs['Acct-Output-Octets'] ?? 0);

        return $input + $output;
    }

    private function dayOf(mixed $value): ?string
    {
        if ($value === null) {
            return null;
        }

        try {
            return Carbon::parse($value)->toDateString();
        } catch (\Throwable $e) {
            return null;
        }
    }

    public function toGb(int $bytes): float
    {
        return round($bytes / self::BYTES_PER_GB, 3);
    }
}
