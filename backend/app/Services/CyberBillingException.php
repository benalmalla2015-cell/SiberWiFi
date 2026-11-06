<?php

namespace App\Services;

use DomainException;

/**
 * Domain failure inside CyberNet billing (CYB-04). Carries the HTTP
 * status the API layer should answer with.
 */
class CyberBillingException extends DomainException
{
    public function __construct(
        string $message,
        public readonly int $status = 422,
    ) {
        parent::__construct($message);
    }

    public static function subscriberNotFound(string $simNo): self
    {
        return new self("رقم الشريحة {$simNo} غير مسجّل في سايبر نت", 404);
    }

    public static function subscribersModuleMissing(): self
    {
        return new self('وحدة المشتركين (CYB-03) غير مركّبة بعد', 503);
    }

    public static function insufficientBalance(float $price, float $balance): self
    {
        return new self(
            'رصيدك غير كافٍ لتفعيل الباقة — السعر '.number_format($price).' والرصيد '.number_format($balance).' ريال',
            422
        );
    }

    // ── CYB-06 additions (transfer + «سلفني») — append-only ──────

    public static function selfTransfer(): self
    {
        return new self('لا يمكنك تحويل رصيد إلى رقمك نفسه', 422);
    }

    public static function insufficientFunds(float $needed, float $balance): self
    {
        return new self(
            'رصيدك غير كافٍ لإتمام التحويل — المطلوب '.number_format($needed).' والرصيد '.number_format($balance).' ريال',
            422
        );
    }

    public static function outstandingDebt(float $outstanding): self
    {
        return new self(
            'لديك سلفة قائمة بـ'.number_format($outstanding).' ريال — تُسدد تلقائياً من أول شحن أو تحويل وارد',
            422
        );
    }

    public static function creditLimitExceeded(float $limit, float $requested): self
    {
        return new self(
            'المبلغ '.number_format($requested).' ريال يتجاوز حد السلفة المتاح لك — الحد '.number_format($limit).' ريال',
            422
        );
    }
}
