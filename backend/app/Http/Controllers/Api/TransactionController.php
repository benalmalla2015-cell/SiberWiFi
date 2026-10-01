<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Card;
use App\Models\CardCategory;
use App\Models\CashbackSetting;
use App\Models\CommissionSetting;
use App\Models\DailyOffer;
use App\Models\Referral;
use App\Models\Transaction;
use App\Models\TransactionCard;
use App\Models\WalletLog;
use App\Services\CurrencyService;
use App\Services\NotificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class TransactionController extends Controller
{
    public function purchase(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'card_id' => 'required_without:category_id|integer|exists:cards,id',
            'category_id' => 'required_without:card_id|integer|exists:card_categories,id',
            'quantity' => 'nullable|integer|min:1|max:100',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        $quantity = (int) $request->input('quantity', 1);

        if ($request->filled('card_id') && $quantity !== 1) {
            return response()->json(['success' => false, 'message' => 'لا يمكن تحديد كمية عند شراء كرت محدد'], 422);
        }

        return DB::transaction(function () use ($request, $user, $quantity) {
            $lockedUser = $user->newQuery()->lockForUpdate()->findOrFail($user->id);

            if ($request->card_id) {
                $cards = Card::with(['category', 'network'])
                    ->whereKey($request->card_id)
                    ->where('status', 'available')
                    ->lockForUpdate()
                    ->get();
            } else {
                $category = CardCategory::whereKey($request->category_id)
                    ->where('is_active', true)
                    ->lockForUpdate()
                    ->firstOrFail();
                $cards = Card::with(['category', 'network'])
                    ->where('category_id', $category->id)
                    ->where('status', 'available')
                    ->orderBy('id')
                    ->lockForUpdate()
                    ->limit($quantity)
                    ->get();
            }

            if ($cards->count() !== $quantity) {
                return response()->json(['success' => false, 'message' => 'عدد الكروت المتاحة لا يكفي لإتمام الشراء'], 422);
            }

            $card = $cards->first();
            $category = $card->category;
            $network = $card->network;
            if (!$network || $network->status !== 'active') {
                return response()->json(['success' => false, 'message' => 'هذه الشبكة غير متاحة للشراء حالياً'], 403);
            }

            $unitPrice = (float) ($category?->price ?? 0);
            $value = (float) ($category?->value ?? $unitPrice);

            // Active daily offer for this network+category (all-categories
            // offers or ones listing this category). The discount reduces
            // the native price, so the network owner bears it.
            $offer = DailyOffer::applicableFor($network->id, $category?->id);
            $offerUnitPrice = $offer ? $offer->applyToUnitPrice($unitPrice) : $unitPrice;
            $nativeDiscount = round(($unitPrice - $offerUnitPrice) * $quantity, 2);
            $nativePrice = round($offerUnitPrice * $quantity, 2); // in the network's own currency

            $networkCurrency = $network->region?->type ?? 'north';
            $buyerCurrency = $user->region_type ?? 'north';
            $price = CurrencyService::convert($nativePrice, $networkCurrency, $buyerCurrency);
            $discountAmount = $nativeDiscount > 0
                ? round(CurrencyService::convert($nativeDiscount, $networkCurrency, $buyerCurrency), 2)
                : 0.0;
            $exchangeRateApplied = CurrencyService::isConversionNeeded($networkCurrency, $buyerCurrency)
                ? CurrencyService::multiplierNorthToSouth()
                : null;

            if ((float) $lockedUser->balance < $price || (float) $lockedUser->available_balance < $price) {
                return response()->json(['success' => false, 'message' => 'رصيدك غير كافٍ لإتمام الشراء'], 422);
            }

            // Commission/owner earnings are always computed on the network's
            // own native price so an owner's profit is never distorted by
            // the buyer's currency/region.
            $commissionRate = CommissionSetting::where('is_active', true)->value('commission_percent') ?? $network->commission_rate ?? 5;
            $commissionAmount = round($nativePrice * ($commissionRate / 100), 2);
            $ownerAmount = $nativePrice - $commissionAmount;

            $cashbackAmount = 0;
            $cashbackSetting = CashbackSetting::where('is_active', true)
                ->where('min_amount', '<=', $price)
                ->orderByDesc('min_amount')
                ->first();
            if ($cashbackSetting && $cashbackSetting->cashback_percent > 0) {
                $cashbackAmount = round($price * ($cashbackSetting->cashback_percent / 100), 2);
            }

            $balanceBefore = (float) $lockedUser->balance;
            $lockedUser->decrement('balance', $price);
            $lockedUser->decrement('available_balance', $price);
            $lockedUser->refresh();
            $user = $lockedUser;

            WalletLog::create([
                'user_id' => $user->id,
                'type' => 'debit',
                'amount' => $price,
                'balance_before' => $balanceBefore,
                'balance_after' => $user->balance,
                'description' => 'شراء كرت شحن من شبكة ' . $network->name,
                'reference_type' => 'purchase',
            ]);

            if ($cashbackAmount > 0) {
                $cbBefore = $user->balance;
                $user->increment('balance', $cashbackAmount);
                $user->increment('available_balance', $cashbackAmount);
                WalletLog::create([
                    'user_id' => $user->id,
                    'type' => 'credit',
                    'amount' => $cashbackAmount,
                    'balance_before' => $cbBefore,
                    'balance_after' => $user->balance,
                    'description' => 'كاشباك من عملية الشراء',
                    'reference_type' => 'cashback',
                ]);
            }

            if ($ownerAmount > 0) {
                $owner = $network->owner;
                if ($owner) {
                    $owner->increment('available_balance', $ownerAmount);
                }
            }

            $transaction = Transaction::create([
                'transaction_number' => 'TRX-' . strtoupper(Str::random(10)),
                'user_id' => $user->id,
                'network_id' => $network->id,
                'card_id' => $card->id,
                'category_id' => $category?->id,
                'quantity' => $quantity,
                'unit_price' => $offerUnitPrice,
                'total_amount' => $price,
                'discount_amount' => $discountAmount,
                'commission_amount' => $commissionAmount,
                'network_owner_amount' => $ownerAmount,
                'cashback_amount' => $cashbackAmount,
                'balance_before' => $balanceBefore,
                'balance_after' => $user->balance,
                'payment_method' => 'wallet',
                'status' => 'completed',
                'network_currency' => $networkCurrency,
                'buyer_currency' => $buyerCurrency,
                'native_amount' => $nativePrice,
                'exchange_rate_applied' => $exchangeRateApplied,
            ]);

            foreach ($cards as $purchasedCard) {
                $purchasedCard->update([
                    'status' => 'sold',
                    'sold_to' => $user->id,
                    'sold_at' => now(),
                    'transaction_id' => $transaction->id,
                ]);
                TransactionCard::create([
                    'transaction_id' => $transaction->id,
                    'card_id' => $purchasedCard->id,
                ]);
            }

            $network->increment('sales_count', $quantity);

            // Referral commission
            if ($user->referred_by) {
                $referralSetting = CommissionSetting::where('is_active', true)->first();
                $referralPercent = $referralSetting?->commission_percent ?? 1;
                $referralAmount = round($price * ($referralPercent / 100), 2);
                if ($referralAmount > 0) {
                    // عمولة الشراء تُستحق للشخص الذي نفذ الشراء (المشتري)،
                    // بينما "صاحب كود الدعوة" يُسجل كمصدر الإحالة فقط.
                    Referral::create([
                        'referrer_id' => $user->id,
                        'referred_id' => $user->referred_by,
                        'transaction_id' => $transaction->id,
                        'commission_amount' => $referralAmount,
                        'commission_percentage' => $referralPercent,
                        'is_paid' => false,
                    ]);
                }
            }

            try {
                app(NotificationService::class)->send(
                    $user,
                    'تم شراء الكرت بنجاح',
                    'تم شراء كرت بقيمة ' . number_format($value) . ' ريال من ' . $network->name,
                    ['type' => 'purchase_complete', 'transaction_id' => $transaction->id]
                );
                app(NotificationService::class)->send(
                    $network->owner,
                    'بيع كرت جديد',
                    'تم بيع كرت من شبكتك ' . $network->name . ' بقيمة ' . number_format($price) . ' ريال',
                    ['type' => 'card_sold', 'transaction_id' => $transaction->id]
                );
                if ($network->owner) {
                    app(NotificationService::class)->sendLowStockAlert($network->owner);
                }
            } catch (\Throwable $e) {
                \Log::warning('Purchase notification failed: ' . $e->getMessage());
            }

            return response()->json([
                'success' => true,
                'message' => 'تم شراء الكرت بنجاح',
                'data' => [
                    'transaction_id' => $transaction->id,
                    'transaction_number' => $transaction->transaction_number,
                    'card_serial' => $card->serial,
                    'card_code' => $card->code,
                    'cards' => $cards->map(fn (Card $purchasedCard) => [
                        'code' => $purchasedCard->code,
                        'serial' => $purchasedCard->serial,
                    ])->values(),
                    'value' => $value,
                    'price' => $price,
                    'original_price' => round($price + $discountAmount, 2),
                    'discount' => $discountAmount,
                    'discount_percent' => $offer?->effectiveDiscountPercent() ?? 0.0,
                    'offer_title' => $offer?->title,
                    'native_price' => $nativePrice,
                    'network_currency' => $networkCurrency,
                    'buyer_currency' => $buyerCurrency,
                    'currency_converted' => $exchangeRateApplied !== null,
                    'currency_note' => $exchangeRateApplied !== null
                        ? 'تم تحويل السعر من ' . CurrencyService::currencyLabel($networkCurrency) . ' إلى ' . CurrencyService::currencyLabel($buyerCurrency) . ' بسبب اختلاف سعر الصرف بين المناطق'
                        : null,
                    'cashback' => $cashbackAmount,
                    'new_balance' => (float) $user->balance,
                ],
            ]);
        });
    }

    /**
     * "سلفني" — hand out cards to the customer as an advance instead of a
     * paid purchase. The amount owed is tracked on the user's
     * `advance_balance` and settled automatically (before any spendable
     * credit) the next time their wallet top-up is approved by the admin
     * (see Filament\Resources\WalletLogResource::approveTopup).
     *
     * The network owner's commission/profit for this sale is intentionally
     * NOT realized here — it is only recognized once the advance is repaid,
     * so an unpaid advance can never distort the profit/commission figures.
     */
    public function purchaseAdvance(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'category_id' => 'required|integer|exists:card_categories,id',
            'quantity' => 'nullable|integer|min:1|max:100',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $user = $request->user();
        $quantity = (int) $request->input('quantity', 1);

        if (!$user->isEligibleForAdvance()) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكنك استخدام خدمة "سلفني" إلا بعد شحن رصيدك لأول مرة. يرجى شحن رصيدك أولاً.',
            ], 422);
        }

        return DB::transaction(function () use ($request, $user, $quantity) {
            $category = CardCategory::whereKey($request->category_id)
                ->where('is_active', true)
                ->lockForUpdate()
                ->firstOrFail();

            if (!$category->advance_enabled || $category->advance_status !== 'approved') {
                return response()->json(['success' => false, 'message' => 'خدمة السلفة غير متاحة لهذه الفئة'], 422);
            }

            $available = max(0, (int) $category->advance_max_cards - (int) $category->advance_used_count);
            if ($available < $quantity) {
                return response()->json(['success' => false, 'message' => 'عدد الكروت المتاحة كسلفة لا يكفي، الحد المتاح حالياً: ' . $available], 422);
            }

            // Per-customer cap: how many cards of this category a single
            // customer may ever receive as an advance, set by the network
            // owner when enabling the service.
            if ($category->advance_max_per_customer !== null) {
                $customerUsed = (int) Transaction::where('user_id', $user->id)
                    ->where('category_id', $category->id)
                    ->where('is_advance', true)
                    ->sum('quantity');
                $customerRemaining = max(0, (int) $category->advance_max_per_customer - $customerUsed);
                if ($customerRemaining < $quantity) {
                    return response()->json([
                        'success' => false,
                        'message' => 'وصلت إلى الحد الأقصى المسموح لك من السلفة لهذه الفئة (' . $category->advance_max_per_customer . ' كرت). المتبقي لك: ' . $customerRemaining,
                    ], 422);
                }
            }

            $lockedUser = $user->newQuery()->lockForUpdate()->findOrFail($user->id);

            $cards = Card::with(['category', 'network'])
                ->where('category_id', $category->id)
                ->where('status', 'available')
                ->orderBy('id')
                ->lockForUpdate()
                ->limit($quantity)
                ->get();

            if ($cards->count() !== $quantity) {
                return response()->json(['success' => false, 'message' => 'عدد الكروت المتاحة لا يكفي لإتمام السلفة'], 422);
            }

            $card = $cards->first();
            $network = $card->network;
            if (!$network || $network->status !== 'active') {
                return response()->json(['success' => false, 'message' => 'هذه الشبكة غير متاحة للسلفة حالياً'], 403);
            }

            $unitPrice = (float) ($category->price ?? 0);
            $value = (float) ($category->value ?? $unitPrice);

            // Same daily-offer discount as a paid purchase — the customer
            // owes the discounted amount and the owner bears the discount.
            $offer = DailyOffer::applicableFor($network->id, $category->id);
            $offerUnitPrice = $offer ? $offer->applyToUnitPrice($unitPrice) : $unitPrice;
            $nativeDiscount = round(($unitPrice - $offerUnitPrice) * $quantity, 2);
            $nativePrice = round($offerUnitPrice * $quantity, 2);

            $networkCurrency = $network->region?->type ?? 'north';
            $buyerCurrency = $lockedUser->region_type ?? 'north';
            $price = CurrencyService::convert($nativePrice, $networkCurrency, $buyerCurrency);
            $discountAmount = $nativeDiscount > 0
                ? round(CurrencyService::convert($nativeDiscount, $networkCurrency, $buyerCurrency), 2)
                : 0.0;

            $commissionRate = CommissionSetting::where('is_active', true)->value('commission_percent') ?? $network->commission_rate ?? 5;
            $commissionAmount = round($nativePrice * ($commissionRate / 100), 2);
            $ownerAmount = $nativePrice - $commissionAmount;

            // Balance is untouched: the customer did not pay, they owe it.
            $balance = (float) $lockedUser->balance;
            $lockedUser->increment('advance_balance', $price);
            $lockedUser->refresh();

            $transaction = Transaction::create([
                'transaction_number' => 'ADV-' . strtoupper(Str::random(10)),
                'user_id' => $lockedUser->id,
                'network_id' => $network->id,
                'card_id' => $card->id,
                'category_id' => $category->id,
                'quantity' => $quantity,
                'unit_price' => $offerUnitPrice,
                'total_amount' => $price,
                'discount_amount' => $discountAmount,
                'commission_amount' => $commissionAmount,
                'network_owner_amount' => $ownerAmount,
                'cashback_amount' => 0,
                'balance_before' => $balance,
                'balance_after' => $balance,
                'payment_method' => 'advance',
                'status' => 'completed',
                'network_currency' => $networkCurrency,
                'buyer_currency' => $buyerCurrency,
                'native_amount' => $nativePrice,
                'is_advance' => true,
                'advance_status' => 'outstanding',
                'repaid_amount' => 0,
            ]);

            foreach ($cards as $purchasedCard) {
                $purchasedCard->update([
                    'status' => 'sold',
                    'sold_to' => $lockedUser->id,
                    'sold_at' => now(),
                    'transaction_id' => $transaction->id,
                ]);
                TransactionCard::create([
                    'transaction_id' => $transaction->id,
                    'card_id' => $purchasedCard->id,
                ]);
            }

            $category->increment('advance_used_count', $quantity);
            $network->increment('sales_count', $quantity);
            $network->recalculateAdvanceSupport();

            try {
                app(NotificationService::class)->send(
                    $lockedUser,
                    'تم استلام السلفة بنجاح',
                    'تم استلام ' . $quantity . ' كرت كسلفة من ' . $network->name . ' بقيمة ' . number_format($price) . ' ريال. سيتم خصمها من رصيدك عند الشحن القادم.',
                    ['type' => 'advance_granted', 'transaction_id' => $transaction->id]
                );
                app(NotificationService::class)->send(
                    $network->owner,
                    'سلفة جديدة على شبكتك',
                    'حصل عميل على سلفة ' . $quantity . ' كرت من شبكتك ' . $network->name . ' بقيمة ' . number_format($price) . ' ريال (سيُحتسب لك عند سداد العميل).',
                    ['type' => 'advance_issued', 'transaction_id' => $transaction->id]
                );
            } catch (\Throwable $e) {
                \Log::warning('Advance notification failed: ' . $e->getMessage());
            }

            return response()->json([
                'success' => true,
                'message' => 'تم استلام الكروت كسلفة بنجاح، سيتم خصم قيمتها من رصيدك عند الشحن القادم',
                'data' => [
                    'transaction_id' => $transaction->id,
                    'transaction_number' => $transaction->transaction_number,
                    'network_name' => $network->name,
                    'cards' => $cards->map(fn (Card $purchasedCard) => [
                        'code' => $purchasedCard->code,
                        'serial' => $purchasedCard->serial,
                    ])->values(),
                    'value' => $value,
                    'price' => $price,
                    'original_price' => round($price + $discountAmount, 2),
                    'discount' => $discountAmount,
                    'discount_percent' => $offer?->effectiveDiscountPercent() ?? 0.0,
                    'offer_title' => $offer?->title,
                    'is_advance' => true,
                    'advance_balance' => (float) $lockedUser->advance_balance,
                ],
            ]);
        });
    }

    public function history(Request $request): JsonResponse
    {
        $transactions = Transaction::with([
                'network:id,name',
                'category:id,name,value',
                'card:id,serial,code',
                'transactionCards.card:id,serial,code',
            ])
            ->where('user_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->paginate(20);

        // Every field the invoice-detail screen (`show()`) needs is embedded
        // here too, so the app can cache the *full* invoice for every item
        // the moment this list loads (while online) instead of only caching
        // whichever single invoice the customer happened to tap on. That way
        // any transaction in "فواتير الشراء" can be opened later while
        // offline and still show its complete details.
        return response()->json([
            'success' => true,
            'data' => $transactions->map(fn ($t) => $this->transactionResource($t))->values(),
            'meta' => [
                'total' => $transactions->total(),
                'current_page' => $transactions->currentPage(),
                'last_page' => $transactions->lastPage(),
            ],
        ]);
    }

    public function show(Request $request, int $id): JsonResponse
    {
        $transaction = Transaction::with([
                'network:id,name',
                'card:id,serial,code',
                'category:id,name,value',
                'transactionCards.card:id,serial,code',
            ])
            ->where('user_id', $request->user()->id)
            ->findOrFail($id);

        return response()->json([
            'success' => true,
            'data' => $this->transactionResource($transaction),
        ]);
    }

    /**
     * Shared invoice payload used by both `history()` (the purchases list)
     * and `show()` (a single invoice). Both endpoints return the exact same
     * shape so the app can cache every entry from the list as a complete,
     * standalone invoice — enabling full offline access to any purchase's
     * details, not just the ones the customer has explicitly opened while
     * online.
     */
    private function transactionResource(Transaction $transaction): array
    {
        // Multi-card purchases (quantity > 1) record every card via
        // TransactionCard; fall back to the single `card` relation for
        // older transactions created before that table existed.
        $cards = $transaction->transactionCards->isNotEmpty()
            ? $transaction->transactionCards->map(fn ($tc) => [
                'code' => $tc->card?->code,
                'serial' => $tc->card?->serial,
            ])->values()
            : ($transaction->card
                ? collect([['code' => $transaction->card->code, 'serial' => $transaction->card->serial]])
                : collect());

        return [
            'id' => $transaction->id,
            'transaction_number' => $transaction->transaction_number,
            'network_name' => $transaction->network?->name,
            'category_name' => $transaction->category?->name,
            'value' => (float) ($transaction->category?->value ?? 0),
            'price' => (float) $transaction->total_amount,
            'cashback' => (float) $transaction->cashback_amount,
            'commission' => (float) $transaction->commission_amount,
            'status' => $transaction->status,
            'payment_method' => $transaction->payment_method,
            'is_advance' => (bool) $transaction->is_advance,
            'advance_status' => $transaction->advance_status,
            'card_serial' => $transaction->card?->serial,
            'card_code' => $transaction->card?->code,
            'cards' => $cards,
            'created_at' => $transaction->created_at?->toDateTimeString(),
        ];
    }
}
