<?php

namespace App\Services;

use App\Models\CyberSubscriber;
use Illuminate\Database\UniqueConstraintViolationException;

/**
 * CyberNet SIM number issuance (CYB-03) — generates 9-digit numbers
 * under the configured prefix (74XXXXXXX) and reserves them atomically.
 *
 * Reservation model: the unique index on cyber_subscribers.sim_no IS the
 * reservation. Callers run their insert inside withUniqueSim(); on a
 * concurrent-collision the unique violation is caught and retried with a
 * fresh candidate, so two parallel registrations can never share a number.
 */
class CyberSimService
{
    /**
     * Generate a candidate SIM number not currently present in the table.
     * (The uniqueness guarantee still lives in the DB index — this check
     * only avoids obvious retries.)
     */
    public function candidate(): string
    {
        $prefix = (string) config('cyber.sim_prefix', '74');
        $suffixLength = max(1, (int) config('cyber.sim_length', 9) - strlen($prefix));
        $max = (10 ** $suffixLength) - 1;

        do {
            $simNo = $prefix.str_pad((string) random_int(0, $max), $suffixLength, '0', STR_PAD_LEFT);
        } while (! $this->isAvailable($simNo));

        return $simNo;
    }

    public function isAvailable(string $simNo): bool
    {
        return ! CyberSubscriber::where('sim_no', $simNo)->exists();
    }

    /**
     * Run $callback with a freshly generated SIM number, retrying on
     * unique-constraint collisions up to $maxAttempts times.
     *
     * @template T
     *
     * @param  callable(string $simNo): T  $callback
     * @return T
     */
    public function withUniqueSim(callable $callback, int $maxAttempts = 5): mixed
    {
        for ($attempt = 1; ; $attempt++) {
            try {
                return $callback($this->candidate());
            } catch (UniqueConstraintViolationException $e) {
                if ($attempt >= $maxAttempts || ! str_contains($e->getMessage(), 'sim_no')) {
                    throw $e;
                }
            }
        }
    }
}
