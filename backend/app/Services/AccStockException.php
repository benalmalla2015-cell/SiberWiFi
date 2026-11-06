<?php

namespace App\Services;

/**
 * User-facing stock/inventory failure (ACC-02) — same convention as
 * AccPostingException / AccOrderException: an Arabic message the API
 * returns verbatim, plus an HTTP status for the controllers.
 */
class AccStockException extends \Exception
{
    public function __construct(string $message, public readonly int $status = 422)
    {
        parent::__construct($message);
    }
}
