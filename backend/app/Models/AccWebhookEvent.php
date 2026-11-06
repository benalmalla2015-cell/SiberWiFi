<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * WhatsApp notification template for an accounting event
 * (PLAN §2.5, ACC-10). `{placeholder}` tokens inside
 * template_body are rendered by AccWebhookService at dispatch
 * time — the row itself is pure config.
 */
class AccWebhookEvent extends Model
{
    protected $table = 'acc_webhook_events';

    protected $fillable = [
        'network_owner_id', 'event', 'channel',
        'template_body', 'is_active',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    public const CHANNEL_WHATSAPP = 'whatsapp';

    public const CHANNELS = [self::CHANNEL_WHATSAPP];

    public const EVENTS = [
        'sale.created', 'sale.updated', 'sale.deleted',
        'collection.created', 'debt.due',
    ];

    /** Arabic labels for the known events (API/UI display). */
    public static function eventLabel(string $event): string
    {
        return [
            'sale.created' => 'بيع جديد',
            'sale.updated' => 'تعديل بيع',
            'sale.deleted' => 'حذف بيع',
            'collection.created' => 'تحصيل جديد',
            'debt.due' => 'دين مستحق',
        ][$event] ?? $event;
    }

    /** The {placeholder} tokens this template actually uses. */
    public function placeholders(): array
    {
        preg_match_all('/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/', $this->template_body ?? '', $m);

        return array_values(array_unique($m[1]));
    }
}
