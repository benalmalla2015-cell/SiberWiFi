<?php

namespace App\Services;

/**
 * Domain failure of the distributor flow (ACC-06): daily-limit or
 * credit-limit breaches, missing POS/stock, disallowed payment
 * kinds, invalid amounts. Carries an HTTP status so the controller
 * maps it without leaking internals — 422 rules, 404 documents.
 */
class AccDistException extends \RuntimeException
{
    public function __construct(
        string $message,
        public readonly int $status = 422,
    ) {
        parent::__construct($message);
    }
}
