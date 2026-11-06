<?php

namespace App\Services;

/**
 * Domain failure of the money-movement flow (ACC-05): insufficient
 * box funds, settled debts, unknown parties, invalid amounts.
 * Carries an HTTP status so the controller maps it without leaking
 * internals — 422 for business rules, 404 for missing documents.
 */
class AccMoneyException extends \RuntimeException
{
    public function __construct(
        string $message,
        public readonly int $status = 422,
    ) {
        parent::__construct($message);
    }
}
