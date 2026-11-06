<?php

namespace App\Services;

/**
 * Domain failure of the POS-order flow (ACC-04): insufficient
 * points/stock, bad status transition, invalid payload. Carries an
 * HTTP status so the controller maps it without leaking internals —
 * 422 for validation/business rules, 409 for decided-order replays.
 */
class AccOrderException extends \RuntimeException
{
    public function __construct(
        string $message,
        public readonly int $status = 422,
    ) {
        parent::__construct($message);
    }
}
