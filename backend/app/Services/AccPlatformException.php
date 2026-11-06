<?php

namespace App\Services;

/**
 * ACC-08 — domain exception for the platform-sales poster.
 * `status` mirrors the sibling *Exception convention (409 conflicts,
 * 422 validation, 500 guard violations).
 */
class AccPlatformException extends \RuntimeException
{
    public function __construct(
        string $message,
        public readonly int $status = 422,
    ) {
        parent::__construct($message);
    }
}
