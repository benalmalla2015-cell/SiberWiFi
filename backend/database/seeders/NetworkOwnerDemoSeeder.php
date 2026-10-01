<?php

namespace Database\Seeders;

use App\Models\Advertisement;
use App\Models\AppSetting;
use App\Models\Card;
use App\Models\CardCategory;
use App\Models\CashbackSetting;
use App\Models\ChargingPoint;
use App\Models\ChatMessage;
use App\Models\CommissionSetting;
use App\Models\DailyOffer;
use App\Models\Directorate;
use App\Models\Network;
use App\Models\NetworkOwner;
use App\Models\NetworkRating;
use App\Models\PayoutRequest;
use App\Models\Region;
use App\Models\Report;
use App\Models\Transaction;
use App\Models\User;
use App\Models\WalletLog;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class NetworkOwnerDemoSeeder extends Seeder
{
    public function run(): void
    {
        DB::transaction(function () {
            $admin = User::updateOrCreate(
                ['email' => 'admin-demo@saiberwifi.local'],
                [
                    'name' => 'مدير النظام التجريبي',
                    'phone' => '777500000',
                    'password' => Hash::make('12345678'),
                    'type' => 'admin',
                    'account_number' => 'ADM-DEMO-001',
                    'referral_code' => 'ADMINDEMO',
                    'balance' => 0,
                    'available_balance' => 0,
                    'frozen_balance' => 0,
                    'currency' => 'YER',
                    'is_active' => true,
                    'is_verified' => true,
                ],
            );

            $targetOwner = User::updateOrCreate(
                ['phone' => '777511122'],
                [
                    'name' => 'صاحب شبكة تجريبي',
                    'email' => 'owner-777511122@saiberwifi.local',
                    'password' => Hash::make('12345678'),
                    'type' => 'network_owner',
                    'region_type' => 'north',
                    'account_number' => 'OWN-DEMO-777511122',
                    'referral_code' => 'OWNER777',
                    'balance' => 98500,
                    'available_balance' => 78500,
                    'frozen_balance' => 20000,
                    'currency' => 'YER',
                    'is_active' => true,
                    'is_verified' => true,
                ],
            );

            $clients = collect([
                ['name' => 'أحمد علي', 'phone' => '777600001', 'email' => 'client-ahmed@saiberwifi.local'],
                ['name' => 'سارة محمد', 'phone' => '777600002', 'email' => 'client-sara@saiberwifi.local'],
                ['name' => 'خالد عبد الله', 'phone' => '777600003', 'email' => 'client-khaled@saiberwifi.local'],
            ])->map(function (array $client, int $index) {
                return User::updateOrCreate(
                    ['phone' => $client['phone']],
                    [
                        'name' => $client['name'],
                        'email' => $client['email'],
                        'password' => Hash::make('12345678'),
                        'type' => 'client',
                        'account_number' => 'CLI-DEMO-00' . ($index + 1),
                        'referral_code' => 'CLIENT' . ($index + 1),
                        'balance' => 50000,
                        'available_balance' => 50000,
                        'frozen_balance' => 0,
                        'currency' => 'YER',
                        'is_active' => true,
                        'is_verified' => true,
                    ],
                );
            })->values();

            $region = Region::updateOrCreate(
                ['name' => 'أمانة العاصمة'],
                ['type' => 'north', 'is_active' => true],
            );
            $directorate = Directorate::updateOrCreate(
                ['region_id' => $region->id, 'name' => 'التحرير'],
                ['name_en' => 'Al Tahrir', 'is_active' => true],
            );

            AppSetting::updateOrCreate(['key' => 'support_phone'], ['value' => '777511122', 'type' => 'string', 'group' => 'support']);
            AppSetting::updateOrCreate(['key' => 'app_name'], ['value' => 'سايبر واي فاي', 'type' => 'string', 'group' => 'general']);
            CommissionSetting::updateOrCreate(['is_active' => true], ['commission_percent' => 5]);
            CashbackSetting::updateOrCreate(['is_active' => true], ['min_amount' => 1000, 'cashback_percent' => 2]);
            Advertisement::updateOrCreate(
                ['title' => 'عرض الإنترنت السريع'],
                [
                    'image' => 'demo/advertisement-placeholder.png',
                    'url' => 'https://example.com/offers',
                    'position' => 'home',
                    'sort_order' => 1,
                    'starts_at' => now()->subDay(),
                    'ends_at' => now()->addMonth(),
                    'is_active' => true,
                ],
            );

            $ownerIds = User::query()
                ->where('type', 'network_owner')
                ->orWhereHas('networkOwnerProfile', fn ($query) => $query->where('is_approved', true))
                ->pluck('id')
                ->push($targetOwner->id)
                ->unique()
                ->values();

            foreach ($ownerIds as $ownerId) {
                $owner = User::findOrFail($ownerId);
                $owner->update([
                    'type' => 'network_owner',
                    'is_active' => true,
                    'is_verified' => true,
                    'currency' => 'YER',
                    'balance' => max((float) $owner->balance, 98500),
                    'available_balance' => max((float) $owner->available_balance, 78500),
                ]);

                NetworkOwner::updateOrCreate(
                    ['user_id' => $owner->id],
                    [
                        'business_name' => 'مؤسسة ' . $owner->name . ' للإنترنت',
                        'national_id' => 'DEMO-NID-' . str_pad((string) $owner->id, 5, '0', STR_PAD_LEFT),
                        'bank_name' => 'بنك اليمن الدولي',
                        'bank_account' => '1000' . str_pad((string) $owner->id, 6, '0', STR_PAD_LEFT),
                        'notes' => 'حساب تجريبي مكتمل لعرض تطبيق صاحب الشبكة.',
                        'is_approved' => true,
                        'approved_at' => now()->subMonths(2),
                        'approved_by' => $admin->id,
                    ],
                );

                foreach ([
                    ['name' => 'شبكة ' . $owner->name . ' الرئيسية', 'suffix' => 'main', 'featured' => true],
                    ['name' => 'شبكة ' . $owner->name . ' - الفرع الثاني', 'suffix' => 'branch', 'featured' => false],
                ] as $networkIndex => $networkData) {
                    $network = Network::updateOrCreate(
                        ['slug' => 'demo-owner-' . $owner->id . '-' . $networkData['suffix']],
                        [
                            'user_id' => $owner->id,
                            'region_id' => $region->id,
                            'directorate_id' => $directorate->id,
                            'name' => $networkData['name'],
                            'phone' => $owner->phone,
                            'url' => 'https://example.com/networks/' . $owner->id . '/' . $networkData['suffix'],
                            'description' => 'شبكة تجريبية متكاملة لعرض الكروت والمبيعات والرسائل والتقييمات.',
                            'commission_rate' => 5,
                            'supports_credit' => true,
                            'average_rating' => 4.7,
                            'ratings_count' => 3,
                            'sales_count' => 16,
                            'views_count' => 240 + ($networkIndex * 35),
                            'status' => 'active',
                            'is_featured' => $networkData['featured'],
                            'approved_at' => now()->subMonths(2),
                            'approved_by' => $admin->id,
                        ],
                    );

                    $categories = collect([
                        ['name' => 'باقة ساعتين', 'speed' => '5 Mbps', 'duration' => 2, 'unit' => 'hours', 'price' => 300, 'value' => 2],
                        ['name' => 'باقة يوم كامل', 'speed' => '10 Mbps', 'duration' => 24, 'unit' => 'hours', 'price' => 1200, 'value' => 24],
                        ['name' => 'باقة أسبوعية', 'speed' => '15 Mbps', 'duration' => 7, 'unit' => 'days', 'price' => 6500, 'value' => 7],
                    ])->map(function (array $categoryData) use ($network) {
                        return CardCategory::updateOrCreate(
                            ['network_id' => $network->id, 'name' => $categoryData['name']],
                            [
                                'speed' => $categoryData['speed'],
                                'duration' => $categoryData['duration'],
                                'duration_unit' => $categoryData['unit'],
                                'price' => $categoryData['price'],
                                'value' => $categoryData['value'],
                                'description' => 'فئة كروت تجريبية متاحة ضمن ' . $network->name,
                                'is_active' => true,
                            ],
                        );
                    })->values();

                    foreach ($categories as $categoryIndex => $category) {
                        for ($cardIndex = 1; $cardIndex <= 10; $cardIndex++) {
                            $code = 'DEMO-' . $owner->id . '-' . $network->id . '-' . $categoryIndex . '-' . str_pad((string) $cardIndex, 3, '0', STR_PAD_LEFT);
                            Card::updateOrCreate(
                                ['code' => $code],
                                [
                                    'network_id' => $network->id,
                                    'category_id' => $category->id,
                                    'card_number' => $code,
                                    'serial' => 'SER-' . $code,
                                    'status' => 'available',
                                    'sold_to' => null,
                                    'sold_at' => null,
                                    'transaction_id' => null,
                                ],
                            );
                        }
                    }

                    for ($transactionIndex = 1; $transactionIndex <= 16; $transactionIndex++) {
                        $category = $categories[($transactionIndex - 1) % $categories->count()];
                        $client = $clients[($transactionIndex - 1) % $clients->count()];
                        $price = (float) $category->price;
                        $commission = round($price * 0.05, 2);
                        $ownerAmount = $price - $commission;
                        $number = 'DEMO-TXN-' . $owner->id . '-' . $network->id . '-' . str_pad((string) $transactionIndex, 3, '0', STR_PAD_LEFT);
                        $transaction = Transaction::updateOrCreate(
                            ['transaction_number' => $number],
                            [
                                'user_id' => $client->id,
                                'network_id' => $network->id,
                                'category_id' => $category->id,
                                'quantity' => 1,
                                'unit_price' => $price,
                                'total_amount' => $price,
                                'discount_amount' => 0,
                                'commission_amount' => $commission,
                                'network_owner_amount' => $ownerAmount,
                                'cashback_amount' => round($price * 0.02, 2),
                                'balance_before' => 50000,
                                'balance_after' => 50000 - $price,
                                'payment_method' => 'wallet',
                                'status' => 'completed',
                                'notes' => 'عملية تجريبية مكتملة من تطبيق العميل.',
                            ],
                        );
                        $soldCardCode = 'SOLD-' . $owner->id . '-' . $network->id . '-' . str_pad((string) $transactionIndex, 3, '0', STR_PAD_LEFT);
                        $card = Card::updateOrCreate(
                            ['code' => $soldCardCode],
                            [
                                'network_id' => $network->id,
                                'category_id' => $category->id,
                                'card_number' => $soldCardCode,
                                'serial' => 'SER-' . $soldCardCode,
                                'status' => 'sold',
                                'sold_to' => $client->id,
                                'sold_at' => now()->subHours($transactionIndex * 5),
                                'transaction_id' => $transaction->id,
                            ],
                        );
                        $transaction->update(['card_id' => $card->id, 'created_at' => now()->subHours($transactionIndex * 5), 'updated_at' => now()->subHours($transactionIndex * 5)]);
                    }

                    foreach ($clients as $clientIndex => $client) {
                        NetworkRating::updateOrCreate(
                            ['user_id' => $client->id, 'network_id' => $network->id],
                            [
                                'rating' => 5 - ($clientIndex % 2),
                                'review' => ['خدمة ممتازة وسرعة مستقرة.', 'الكروت تعمل بشكل سريع وسهل.', 'تجربة جيدة وتعامل محترم.'][$clientIndex],
                            ],
                        );
                    }

                    foreach ($clients->take(2) as $clientIndex => $client) {
                        $messages = [
                            [$client->id, $owner->id, 'مرحباً، هل تتوفر باقة يوم كامل؟', false],
                            [$owner->id, $client->id, 'نعم، باقة يوم كامل متوفرة ويمكنك شراؤها من التطبيق.', true],
                            [$client->id, $owner->id, 'شكراً لكم، الخدمة ممتازة.', false],
                        ];
                        foreach ($messages as $messageIndex => [$senderId, $receiverId, $message, $isRead]) {
                            ChatMessage::firstOrCreate(
                                ['network_id' => $network->id, 'sender_id' => $senderId, 'receiver_id' => $receiverId, 'message' => $message],
                                ['is_read' => $isRead, 'read_at' => $isRead ? now()->subMinutes(15 + $messageIndex) : null],
                            );
                        }
                    }

                    ChargingPoint::updateOrCreate(
                        ['network_id' => $network->id, 'name' => 'نقطة شحن ' . $network->name],
                        [
                            'phone' => $owner->phone,
                            'location' => 'التحرير - بالقرب من سوق القات',
                            'latitude' => 15.369445,
                            'longitude' => 44.191007,
                            'is_active' => true,
                        ],
                    );
                    DailyOffer::updateOrCreate(
                        ['network_id' => $network->id, 'title' => 'عرض نهاية الأسبوع'],
                        [
                            'category_id' => $categories[1]->id,
                            'description' => 'خصم تجريبي على باقة اليوم الكامل.',
                            'discount_percent' => 10,
                            'discount_percentage' => 10,
                            'discounted_price' => 1080,
                            'starts_at' => now()->subDay(),
                            'ends_at' => now()->addDays(6),
                            'start_date' => now()->subDay(),
                            'end_date' => now()->addDays(6),
                            'is_active' => true,
                        ],
                    );
                    Report::updateOrCreate(
                        ['network_id' => $network->id, 'subject' => 'استفسار عن التغطية'],
                        [
                            'user_id' => $clients[0]->id,
                            'type' => 'technical_issue',
                            'description' => 'هل توجد تغطية قوية في منطقة التحرير؟',
                            'message' => 'هل توجد تغطية قوية في منطقة التحرير؟',
                            'status' => 'open',
                            'admin_reply' => null,
                            'replied_at' => null,
                            'replied_by' => null,
                        ],
                    );
                    Report::updateOrCreate(
                        ['network_id' => $network->id, 'subject' => 'تم حل المشكلة'],
                        [
                            'user_id' => $clients[1]->id,
                            'type' => 'technical_issue',
                            'description' => 'واجهت مشكلة مؤقتة في الكرت ثم عادت الخدمة.',
                            'message' => 'واجهت مشكلة مؤقتة في الكرت ثم عادت الخدمة.',
                            'status' => 'resolved',
                            'admin_reply' => 'تمت المتابعة وحل المشكلة بنجاح.',
                            'replied_at' => now()->subDays(2),
                            'replied_by' => $owner->id,
                        ],
                    );
                }

                foreach ([
                    ['number' => 'DEMO-PAYOUT-' . $owner->id . '-001', 'amount' => 12500, 'paid' => 12500, 'status' => 'received'],
                    ['number' => 'DEMO-PAYOUT-' . $owner->id . '-002', 'amount' => 8000, 'paid' => 8000, 'status' => 'paid_unconfirmed'],
                    ['number' => 'DEMO-PAYOUT-' . $owner->id . '-003', 'amount' => 6000, 'paid' => 0, 'status' => 'rejected'],
                ] as $payoutIndex => $payout) {
                    PayoutRequest::updateOrCreate(
                        ['request_number' => $payout['number']],
                        [
                            'user_id' => $owner->id,
                            'amount' => $payout['amount'],
                            'requested_amount' => $payout['amount'],
                            'remaining_amount' => max(0, $payout['amount'] - $payout['paid']),
                            'paid_amount' => $payout['paid'],
                            'service_name' => $payout['paid'] > 0 ? 'حوالة بنكية' : null,
                            'transaction_number' => $payout['paid'] > 0 ? 'BANK-DEMO-' . $owner->id . '-' . ($payoutIndex + 1) : null,
                            'status' => $payout['status'],
                            'paid_at' => $payout['paid'] > 0 ? now()->subDays(5 - $payoutIndex) : null,
                            'received_confirmed_at' => $payout['status'] === 'received' ? now()->subDays(4) : null,
                            'admin_notes' => 'طلب سحب تجريبي لعرض حالات السحب المختلفة.',
                        ],
                    );
                }

                foreach ([
                    ['type' => 'credit', 'amount' => 45000, 'before' => 0, 'after' => 45000, 'description' => 'أرباح مبيعات تجريبية'],
                    ['type' => 'credit', 'amount' => 53500, 'before' => 45000, 'after' => 98500, 'description' => 'إضافة أرباح مبيعات تجريبية'],
                    ['type' => 'debit', 'amount' => 20000, 'before' => 98500, 'after' => 78500, 'description' => 'مبلغ مجمّد لطلب سحب تجريبي'],
                ] as $logIndex => $log) {
                    WalletLog::updateOrCreate(
                        ['user_id' => $owner->id, 'description' => $log['description']],
                        [
                            'type' => $log['type'],
                            'amount' => $log['amount'],
                            'balance_before' => $log['before'],
                            'balance_after' => $log['after'],
                            'reference_type' => 'demo',
                            'reference_id' => $logIndex + 1,
                        ],
                    );
                }

                foreach ([
                    ['key' => 'sales', 'title' => 'عملية بيع جديدة', 'body' => 'تمت عملية بيع كرت جديدة بنجاح.', 'read_at' => null],
                    ['key' => 'payout', 'title' => 'تحديث طلب السحب', 'body' => 'تم تحويل مبلغ سحب تجريبي إلى حسابك.', 'read_at' => now()->subDay()],
                    ['key' => 'message', 'title' => 'رسالة جديدة من عميل', 'body' => 'لديك رسائل جديدة بانتظار الرد.', 'read_at' => null],
                ] as $notification) {
                    $notificationKey = 'demo-owner-' . $owner->id . '-' . $notification['key'];
                    DB::table('notifications')->updateOrInsert(
                        ['id' => $this->uuidFromKey($notificationKey)],
                        [
                            'type' => 'App\\Notifications\\DemoNotification',
                            'notifiable_type' => User::class,
                            'notifiable_id' => $owner->id,
                            'data' => json_encode([
                                'title' => $notification['title'],
                                'body' => $notification['body'],
                                'type' => $notification['key'],
                            ], JSON_UNESCAPED_UNICODE),
                            'read_at' => $notification['read_at'],
                            'created_at' => now()->subHours($notification['key'] === 'sales' ? 1 : 18),
                            'updated_at' => now(),
                        ],
                    );
                }
            }
        });
    }

    private function uuidFromKey(string $key): string
    {
        $hash = md5($key);

        return substr($hash, 0, 8) . '-' . substr($hash, 8, 4) . '-4' . substr($hash, 13, 3) . '-a' . substr($hash, 17, 3) . '-' . substr($hash, 20, 12);
    }
}
