<?php

namespace App\Services;

use App\Models\AccAgent;
use App\Models\AccAuditLog;
use App\Models\AccDebt;
use App\Models\AccPosPoint;
use App\Models\AccWebhookEvent;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\Schema;

/**
 * ACC-10 — event notification engine (PLAN §2.5).
 *
 * acc_webhook_events rows map accounting events to WhatsApp
 * message templates. dispatch() renders every active template of
 * the event with the document's variables ({pos_name}, {total}…),
 * returns the messages for the API response — each carries a
 * wa.me deep link the app opens to hand the text to WhatsApp —
 * audit-logs the dispatch, and pushes a best-effort in-app
 * notification to a recipient that resolves to a real user (a
 * POS's bound agent, a distributor agent).
 *
 * Delivery is deliberately out-of-band (wa.me + push): there is
 * no server-side WhatsApp channel, and a failed/unreachable
 * recipient must never roll back a posted document — dispatch is
 * called after the document transaction commits.
 */
class AccWebhookService
{
    public function __construct(private NotificationService $notifications) {}

    /**
     * A recipient descriptor for a POS point: its registered phone
     * plus the bound agent's user (when the point is operated by a
     * pos-role account) so the event also lands as an in-app push.
     */
    public function posRecipient(AccPosPoint $pos): array
    {
        return [
            'name' => $pos->name,
            'phone' => $pos->phone,
            'user' => $pos->agent?->user,
        ];
    }

    /** A recipient descriptor for an agent (distributor/admin). */
    public function agentRecipient(AccAgent $agent): array
    {
        return [
            'name' => $agent->display_name,
            'phone' => $agent->phone,
            'user' => $agent->user,
        ];
    }

    /** A free-form recipient (named party without an account). */
    public function partyRecipient(?string $name, ?string $phone): array
    {
        return ['name' => $name, 'phone' => $phone, 'user' => null];
    }

    /** `{placeholder}` substitution — unknown tokens render empty. */
    public function render(string $body, array $vars): string
    {
        return (string) preg_replace_callback(
            '/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/',
            fn ($m) => isset($vars[$m[1]]) ? (string) $vars[$m[1]] : '',
            $body
        );
    }

    /** The active templates bound to an event, oldest first. */
    public function templatesFor(int $ownerId, string $event)
    {
        if (! Schema::hasTable('acc_webhook_events')) {
            return collect();
        }

        return AccWebhookEvent::where('network_owner_id', $ownerId)
            ->where('event', $event)
            ->where('is_active', true)
            ->oldest('id')
            ->get();
    }

    /**
     * Render + audit + push for an event. Returns the rendered
     * messages (one per template × recipient) — never throws, so a
     * broken template or missing recipient can't hurt the caller.
     *
     * @param  array<int, array{name: ?string, phone: ?string, user: ?User}>  $recipients
     * @return array<int, array<string, mixed>>
     */
    public function dispatch(
        int $ownerId,
        ?int $agentId,
        string $event,
        array $vars,
        array $recipients
    ): array {
        try {
            $templates = $this->templatesFor($ownerId, $event);
            if ($templates->isEmpty() || $recipients === []) {
                return [];
            }

            $messages = [];
            foreach ($templates as $template) {
                $body = $this->render($template->template_body, $vars);
                foreach ($recipients as $recipient) {
                    $phone = $this->normalizePhone($recipient['phone'] ?? null);
                    $messages[] = [
                        'event' => $event,
                        'event_label' => AccWebhookEvent::eventLabel($event),
                        'channel' => $template->channel,
                        'template_id' => $template->id,
                        'to_name' => $recipient['name'] ?? null,
                        'to_phone' => $phone,
                        'body' => $body,
                        'wa_url' => $phone !== null
                            ? 'https://wa.me/' . $phone . '?text=' . rawurlencode($body)
                            : null,
                        'pushed' => $this->push(
                            $recipient['user'] ?? null, $event, $body
                        ),
                    ];

                    $this->audit($ownerId, $agentId, $template, $recipient, $body);
                }
            }

            return $messages;
        } catch (\Throwable) {
            // Notifications are best-effort — never break the flow.
            return [];
        }
    }

    /**
     * Open/partial debts at or past their due_date, each with the
     * rendered `debt.due` message — the app's reminder launcher
     * (GET /notifications/debt-due).
     */
    public function dueDebts(int $ownerId): array
    {
        $template = $this->templatesFor($ownerId, 'debt.due')->first();
        if ($template === null) {
            return [];
        }

        return AccDebt::where('network_owner_id', $ownerId)
            ->whereIn('status', [AccDebt::STATUS_OPEN, AccDebt::STATUS_PARTIAL])
            ->whereNotNull('due_date')
            ->whereDate('due_date', '<=', Carbon::today())
            ->orderBy('due_date')
            ->limit(50)
            ->get()
            ->map(function (AccDebt $debt) use ($template) {
                $body = $this->render($template->template_body, [
                    'party_name' => $debt->party_name,
                    'amount_due' => (float) $debt->amount_due,
                    'amount_paid' => (float) $debt->amount_paid,
                    'remaining' => $debt->remaining(),
                    'due_date' => $debt->due_date?->toDateString(),
                    'phone' => $debt->phone,
                ]);
                $phone = $this->normalizePhone($debt->phone);

                return [
                    'debt_id' => $debt->id,
                    'party_type' => $debt->party_type,
                    'party_id' => $debt->party_id,
                    'party_name' => $debt->party_name,
                    'remaining' => $debt->remaining(),
                    'currency' => $debt->currency,
                    'due_date' => $debt->due_date?->toDateString(),
                    'body' => $body,
                    'wa_url' => $phone !== null
                        ? 'https://wa.me/' . $phone . '?text=' . rawurlencode($body)
                        : null,
                ];
            })
            ->values()
            ->all();
    }

    /** Sample render for the template preview endpoint. */
    public function preview(AccWebhookEvent $template, array $vars): string
    {
        return $this->render(
            $template->template_body,
            $vars === [] ? $this->sampleVars() : $vars
        );
    }

    /** Variables used when a preview supplies none of its own. */
    public function sampleVars(): array
    {
        return [
            'pos_name' => 'نقطة بيع تجريبية',
            'party_name' => 'نقطة بيع تجريبية',
            'sale_no' => 'SA-20261029-000001',
            'order_no' => 'PO-20261029-000001',
            'total' => 10000,
            'paid' => 6000,
            'amount' => 4000,
            'remaining' => 4000,
            'currency' => 'ريال',
            'date' => Carbon::today()->toDateString(),
            'due_date' => Carbon::today()->addWeek()->toDateString(),
        ];
    }

    // ── Internals ────────────────────────────────────────────────

    /** In-app push to the recipient's user — best effort. */
    private function push(?User $user, string $event, string $body): bool
    {
        if ($user === null) {
            return false;
        }

        try {
            $this->notifications->send(
                $user,
                AccWebhookEvent::eventLabel($event),
                $body,
                ['type' => 'acc_event', 'event' => $event]
            );

            return true;
        } catch (\Throwable) {
            return false;
        }
    }

    /**
     * Yemen-centric phone normalization for wa.me: local mobiles
     * are 9 digits starting with 7 → prefixed with the 967 country
     * code; anything already international passes through as-is.
     */
    public function normalizePhone(?string $phone): ?string
    {
        $digits = preg_replace('/\D+/', '', (string) $phone);
        if ($digits === '') {
            return null;
        }
        if (strlen($digits) === 9 && str_starts_with($digits, '7')) {
            return '967' . $digits;
        }

        return $digits;
    }

    private function audit(
        int $ownerId,
        ?int $agentId,
        AccWebhookEvent $template,
        array $recipient,
        string $body
    ): void {
        try {
            AccAuditLog::create([
                'network_owner_id' => $ownerId,
                'agent_id' => $agentId,
                'action' => 'webhook.dispatch',
                'entity' => 'acc_webhook_events',
                'entity_id' => $template->id,
                'meta' => [
                    'event' => $template->event,
                    'to_name' => $recipient['name'] ?? null,
                    'to_phone' => $recipient['phone'] ?? null,
                    'body_hash' => substr(sha1($body), 0, 16),
                ],
                'created_at' => now(),
            ]);
        } catch (\Throwable) {
            // The audit trail must never break a dispatch.
        }
    }
}
