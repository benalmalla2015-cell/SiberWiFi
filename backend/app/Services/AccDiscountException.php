<?php

namespace App\Services;

use RuntimeException;

/** Domain exception for the ACC-10 discount/webhook surfaces. */
class AccDiscountException extends RuntimeException
{
    public function __construct(
        string $message,
        public readonly int $status = 422,
    ) {
        parent::__construct($message);
    }
}
