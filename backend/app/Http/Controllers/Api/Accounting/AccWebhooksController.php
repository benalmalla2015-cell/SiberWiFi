<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccWebhookEvent;
use App\Services\AccContext;
use App\Services\AccWebhookService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * WhatsApp event templates (ACC-10, PLAN §2.5). Management CRUD +
 * a render preview + the debt.due reminder list the app launches
 * wa.me deep links from. Dispatch itself happens inside the
 * document write endpoints (sale/approve/collect) which append a
 * `notifications` payload to their responses.
 */
class AccWebhooksController extends Controller
{
    public function __construct(private AccWebhookService $webhooks) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $events = AccWebhookEvent::where('network_owner_id', $ctx->ownerId)
            ->orderBy('event')->orderBy('id')
            ->get()
            ->map(fn (AccWebhookEvent $e) => $this->serialize($e));

        return response()->json(['success' => true, 'data' => $events]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $this->rules($request);

        $event = AccWebhookEvent::create([
            'network_owner_id' => $ctx->ownerId,
            ...$data,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'تمت إضافة قالب الإشعار',
            'data' => $this->serialize($event),
        ], 201);
    }

    public function update(Request $request, int $event): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccWebhookEvent::where('network_owner_id', $ctx->ownerId)->find($event);
        if ($model === null) {
            return response()->json(['success' => false, 'message' => 'القالب غير موجود'], 404);
        }

        $model->update($this->rules($request, partial: true));

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث القالب',
            'data' => $this->serialize($model),
        ]);
    }

    public function destroy(Request $request, int $event): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccWebhookEvent::where('network_owner_id', $ctx->ownerId)->find($event);
        if ($model === null) {
            return response()->json(['success' => false, 'message' => 'القالب غير موجود'], 404);
        }

        $model->delete();

        return response()->json(['success' => true, 'message' => 'تم حذف القالب']);
    }

    /** Render a template against caller vars (or sample data). */
    public function preview(Request $request, int $event): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = AccWebhookEvent::where('network_owner_id', $ctx->ownerId)->find($event);
        if ($model === null) {
            return response()->json(['success' => false, 'message' => 'القالب غير موجود'], 404);
        }

        $data = $request->validate(['vars' => 'nullable|array']);
        $body = $this->webhooks->preview($model, $data['vars'] ?? []);

        return response()->json([
            'success' => true,
            'data' => [
                'body' => $body,
                'placeholders' => $model->placeholders(),
            ],
        ]);
    }

    /**
     * Open debts at/past due_date, each with its rendered debt.due
     * message + wa.me link — the app's due-reminder launcher.
     */
    public function dueDebts(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        return response()->json([
            'success' => true,
            'data' => $this->webhooks->dueDebts($ctx->ownerId),
        ]);
    }

    private function rules(Request $request, bool $partial = false): array
    {
        $req = $partial ? 'sometimes' : 'required';
        $channels = implode(',', AccWebhookEvent::CHANNELS);

        return $request->validate([
            'event' => "$req|string|max:40",
            'channel' => "sometimes|string|in:$channels",
            'template_body' => "$req|string|max:2000",
            'is_active' => 'sometimes|boolean',
        ]);
    }

    private function serialize(AccWebhookEvent $e): array
    {
        return [
            'id' => $e->id,
            'event' => $e->event,
            'event_label' => AccWebhookEvent::eventLabel($e->event),
            'channel' => $e->channel,
            'template_body' => $e->template_body,
            'placeholders' => $e->placeholders(),
            'is_active' => $e->is_active,
            'created_at' => $e->created_at?->toISOString(),
        ];
    }
}
