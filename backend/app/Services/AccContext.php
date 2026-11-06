<?php

namespace App\Services;

use App\Models\AccAgent;
use App\Models\User;
use Illuminate\Http\Request;

/**
 * Per-request accounting context (PLAN §1 + §4).
 *
 * Every accounting endpoint resolves the *tenant* it operates on:
 * - a network owner → their own tenant, role `owner` (full access);
 * - an enrolled acc_agents row → the owner's tenant, role from the row.
 *
 * The role then gates each route through `acc:{permission}` strings
 * (ROLE_PERMISSIONS below) — later sprints add grants, never new
 * auth tables.
 */
class AccContext
{
    public const REQUEST_KEY = 'acc_context';

    public const ROLE_OWNER = 'owner';

    /**
     * Grant lists. `*` = all; `prefix.*` = namespace grant; anything
     * else is an exact match. Checked by can().
     */
    public const ROLE_PERMISSIONS = [
        self::ROLE_OWNER => ['*'],
        'admin' => ['*'],
        'distributor' => [
            'pos.read',
            'pos-orders.read', 'pos-orders.decide',
            'dist.*',
            'collections.*', 'debts.*',
            'reports.own',
            'sync.push',
        ],
        'pos' => ['posapp.*', 'sync.push'],
    ];

    public function __construct(
        public readonly int $ownerId,
        public readonly string $role,
        public readonly ?AccAgent $agent,
        public readonly User $user,
    ) {}

    /**
     * Resolve the tenant context for an authenticated user, or null
     * when the account is neither an owner nor an active agent.
     */
    public static function forUser(User $user): ?self
    {
        // Owner identity wins — an owner's own tenant is always theirs.
        $isOwner = $user->type === 'network_owner'
            || $user->networks()->exists()
            || $user->networkOwnerProfile()->exists();

        if ($isOwner) {
            // Still surface their agent row when one exists under their
            // own tenant (e.g. an admin persona they created for self).
            $selfAgent = AccAgent::where('user_id', $user->id)
                ->where('network_owner_id', $user->id)
                ->where('status', AccAgent::STATUS_ACTIVE)
                ->first();

            return new self($user->id, self::ROLE_OWNER, $selfAgent, $user);
        }

        $agent = AccAgent::where('user_id', $user->id)
            ->where('status', AccAgent::STATUS_ACTIVE)
            ->first();

        if ($agent === null) {
            return null;
        }

        return new self($agent->network_owner_id, $agent->role, $agent, $user);
    }

    public static function fromRequest(Request $request): ?self
    {
        $ctx = $request->attributes->get(self::REQUEST_KEY);
        if ($ctx instanceof self) {
            return $ctx;
        }
        $user = $request->user();
        if ($user === null) {
            return null;
        }
        $ctx = self::forUser($user);
        if ($ctx !== null) {
            $request->attributes->set(self::REQUEST_KEY, $ctx);
        }

        return $ctx;
    }

    public function can(string $permission): bool
    {
        foreach ($this->permissions() as $grant) {
            if ($grant === '*' || $grant === $permission) {
                return true;
            }
            if (str_ends_with($grant, '.*')
                && str_starts_with($permission, substr($grant, 0, -1))) {
                return true;
            }
        }

        return false;
    }

    /** @return list<string> */
    public function permissions(): array
    {
        return self::ROLE_PERMISSIONS[$this->role] ?? [];
    }

    /** The acc_agents.id of the acting user — null for the owner. */
    public function agentId(): ?int
    {
        return $this->agent?->id;
    }
}
