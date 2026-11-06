<?php

namespace App\Services;

use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Support\Facades\DB;

/**
 * ACC-08 — the isolation-contract guard (PLAN §0.3 rule 3).
 *
 * While armed, EVERY statement executed on the default connection is
 * inspected; any write/DDL targeting a protected platform table throws
 * AccPlatformException before the caller can proceed. Combined with the
 * per-sale DB::transaction in AccPlatformSalesService, the offending
 * statement is rolled back — the ban is enforced, not just documented.
 *
 * The listener registers once per process and only inspects while
 * $depth > 0, so nothing outside a guarded section pays the cost.
 */
class AccPlatformReadOnly
{
    /** Platform tables the accounting track may read but never write. */
    public const PROTECTED_TABLES = [
        'transactions', 'transaction_cards', 'cards', 'card_categories',
        'wallet_logs', 'networks', 'users', 'wallets',
    ];

    /**
     * Dispatchers already wired — keyed by spl_object_id because the
     * app (and its dispatcher) is rebuilt between tests/workers; a
     * plain boolean would orphan the listener on rebuild.
     *
     * @var array<int,true>
     */
    private static array $registeredOn = [];

    private static int $depth = 0;

    /**
     * Run $fn under the guard. Nested calls share the guard — the
     * guard lifts only when the outermost section returns.
     */
    public static function run(callable $fn): mixed
    {
        self::register();
        self::$depth++;
        try {
            return $fn();
        } finally {
            self::$depth--;
        }
    }

    public static function armed(): bool
    {
        return self::$depth > 0;
    }

    private static function register(): void
    {
        $dispatcher = DB::getEventDispatcher();
        $key = spl_object_id($dispatcher);
        if (isset(self::$registeredOn[$key])) {
            return;
        }
        self::$registeredOn[$key] = true;

        $dispatcher->listen(QueryExecuted::class, function (QueryExecuted $q): void {
            if (! self::armed()) {
                return;
            }
            if (self::isProtectedWrite($q->sql)) {
                throw new AccPlatformException(
                    'خدمة المحاسبة قراءة-فقط على جداول المنصة — كتابة مرفوضة على «'
                        . $q->sql . '»',
                    500
                );
            }
        });
    }

    /**
     * True when $sql is a mutating statement whose target table is
     * protected. Matches the leading verb + quoted/unquoted identifier
     * so prose inside string literals can never false-positive.
     */
    private static function isProtectedWrite(string $sql): bool
    {
        if (! preg_match(
            '/^\s*(?:insert\s+into|replace\s+into|update|delete\s+from|truncate\s+table|alter\s+table|drop\s+table|create\s+table)\s+[`"\[]?([A-Za-z0-9_]+)/i',
            $sql,
            $m
        )) {
            return false;
        }

        return in_array(strtolower($m[1]), self::PROTECTED_TABLES, true);
    }
}
