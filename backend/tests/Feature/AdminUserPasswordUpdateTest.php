<?php

namespace Tests\Feature;

use App\Filament\Resources\UserResource\Pages\EditUser;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class AdminUserPasswordUpdateTest extends TestCase
{
    use RefreshDatabase;

    public static function mobileUserTypes(): array
    {
        return [
            'client' => ['client'],
            'network owner' => ['network_owner'],
        ];
    }

    #[DataProvider('mobileUserTypes')]
    public function test_admin_password_update_is_accepted_by_mobile_login(string $type): void
    {
        $admin = User::factory()->create(['type' => 'admin']);
        $user = User::factory()->create([
            'phone' => $type === 'client' ? '711111111' : '722222222',
            'password' => 'old-password',
            'type' => $type,
            'is_active' => true,
        ]);
        $user->createToken('mobile_app');

        $this->actingAs($admin);

        Livewire::test(EditUser::class, ['record' => $user->getRouteKey()])
            ->fillForm(['password' => 'new-password'])
            ->call('save')
            ->assertHasNoFormErrors();

        $user->refresh();

        $this->assertTrue(Hash::check('new-password', $user->password));
        $this->assertFalse(Hash::check('old-password', $user->password));
        $this->assertSame(0, $user->tokens()->count());

        $headers = $type === 'network_owner' ? ['X-App-Type' => 'network_owner_app'] : [];

        $this->withHeaders($headers)->postJson('/api/auth/login', [
            'phone' => $user->phone,
            'password' => 'new-password',
        ])->assertOk()->assertJsonPath('success', true);
    }
}
