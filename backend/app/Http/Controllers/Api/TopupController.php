<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\TopupOrder;
use App\Models\TopupServiceSetting;
use App\Models\WalletLog;
use App\Services\CurrencyService;
use App\Services\TaizTelService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Instant top-up (TaizTel / yemoney.net) — bills the customer's Saiber
 * wallet and forwards the operation to the provider. Provider secrets
 * never leave the server; the app only sees this controller's API.
 *
 * Money flow per payable operation:
 *   1. validate + compute fee (per-service: none | percent | fixed)
 *   2. DB transaction: lock user, check balance, debit, WalletLog, create pending order
 *   3. call provider (outside the transaction)
 *   4. success → mark done | provider "under process" (-2) → stays pending, resolvable via status
 *      | definitive failure → refund wallet and mark failed
 */
class TopupController extends Controller
{
    public function __construct(private TaizTelService $provider) {}

    // ── GET /topup/services ─────────────────────────────────────────
    public function services(): JsonResponse
    {
        $services = TopupServiceSetting::where('is_active', true)
            ->orderBy('sort_order')
            ->get(['code', 'name_ar', 'category', 'provider_endpoint', 'account',
                   'fee_type', 'fee_value', 'meta', 'packages']);

        // Inject admin-managed place lists (meta.places: {id => name}) into the
        // placeid field's options — falls back to a free-text input when empty.
        foreach ($services as $s) {
            $meta = $s->meta ?? [];
            if (empty($meta['places']) || !is_array($meta['places'])) continue;
            $options = [];
            foreach ($meta['places'] as $id => $name) {
                $options[] = ['v' => (string) $id, 'l' => (string) $name];
            }
            foreach (($meta['fields'] ?? []) as &$f) {
                if (($f['key'] ?? '') === 'placeid' && $options) {
                    $f['type'] = 'select';
                    $f['options'] = $options;
                }
            }
            $s->meta = $meta;
        }

        return response()->json(['success' => true, 'data' => $services]);
    }

    // ── POST /topup/query — free look-ups (balance/subscriber info) ──
    public function query(Request $request): JsonResponse
    {
        $request->validate(['service' => 'required|string', 'num' => 'required|string']);
        $service = $this->service($request->service);
        if (!$service) return $this->fail('الخدمة غير متوفرة', 404);

        $meta = $service->meta ?? [];
        if (empty($meta['query'])) return $this->fail('هذه الخدمة لا تدعم الاستعلام', 422);

        $params = ['action' => 'query'];
        $postBody = [];
        $account = $this->gateway($service, $request);
        $mobile = $request->num;

        switch ($service->provider_endpoint) {
            case 'post':
                $request->validate(['type' => 'required|in:adsl,line']);
                $params['type'] = $request->type;
                break;
            case 'electwater':
                $request->validate(['placeid' => 'required|string']);
                $params['act'] = $meta['act'] ?? 'elect';
                $postBody = ['userid' => $request->num, 'placeid' => $request->placeid];
                // electwater's `mobile` is the agent's own 9-digit number —
                // the subscriber travels in the POST `userid` field.
                $mobile = config("taiztel.accounts.{$account}.username");
                break;
            case 'adenet':
            case 'yem4g':
                $params['num'] = $request->num;
                break;
        }

        $res = $this->provider->call($account, $service->provider_endpoint, $params, $mobile, null, $postBody);
        return $this->providerReply($res);
    }

    // ── GET /topup/offers?service=yem|mtn|saba&num= ─────────────────
    public function offers(Request $request): JsonResponse
    {
        $request->validate(['service' => 'required|string']);
        $service = $this->service($request->service);
        if (!$service) return $this->fail('الخدمة غير متوفرة', 404);

        $offersEndpoint = $service->meta['offers'] ?? null;
        if (!$offersEndpoint) return $this->fail('لا توجد عروض لهذه الخدمة', 422);

        $account = $this->gateway($service, $request);
        $mobile = $request->num ?: config("taiztel.accounts.{$account}.username");
        $params = ['action' => 'queryoffer'];

        // mtnoffer / sabaoffer are standalone endpoints taking num.
        if (in_array($offersEndpoint, ['mtnoffer', 'sabaoffer', 'sabaunits'])) {
            $request->validate(['num' => 'required|string']);
            $res = $this->provider->call($account, $offersEndpoint, ['num' => $request->num], $request->num);
        } else {
            // 'yemoffer' maps to yem?action=queryoffer
            $res = $this->provider->call($account, 'yem', $params, $mobile);
        }

        return $this->providerReply($res);
    }

    // ── POST /topup/pay — direct amount top-up ──────────────────────
    public function pay(Request $request): JsonResponse
    {
        $request->validate([
            'service' => 'required|string',
            'amount' => 'required_without_all:units,package|numeric|min:1',
            'units' => 'nullable|numeric|min:1',
            'package' => 'nullable|string',
        ]);
        $service = $this->service($request->service);
        if (!$service) return $this->fail('الخدمة غير متوفرة', 404);
        if ($service->category === 'game' || $service->provider_endpoint === 'gameswcards') {
            return $this->fail('خدمة الألعاب تُنفَّذ عبر نقطة البطاقات', 422);
        }

        $num = (string) $request->input('num', '');
        $this->validateTarget($service, $num, $request);

        // Package activation: the code resolves server-side to a price/mode —
        // the client only sends the package code, never a trusted amount.
        if ($request->filled('package')) {
            return $this->payPackage($request, $service, $num);
        }

        // Unit-based billing (e.g. Sabafon credit): the client sends a unit
        // count and the server prices it — never trusts a client amount.
        $unitPrice = (float) ($service->meta['unit_price'] ?? 0);
        if ($request->filled('units') && $unitPrice > 0) {
            $request->merge(['amount' => round((float) $request->units * $unitPrice, 2)]);
        }

        [$endpoint, $params, $postBody, $mobile] = $this->buildBillCall($service, $request);
        if ($endpoint === null) return $this->fail('نوع عملية غير مدعوم لهذه الخدمة', 422);

        $amount = (float) $request->amount;
        return $this->chargeAndSubmit(
            $request->user(), $service, $num, $amount,
            $endpoint, $params, $mobile, $postBody,
            $this->gateway($service, $request),
            $request->all()
        );
    }

    // ── GET /topup/quote?service=&amount=&account= — fee + conversion preview ──
    public function quote(Request $request): JsonResponse
    {
        $request->validate([
            'service' => 'required|string',
            'amount' => 'nullable|numeric|min:1',
            'units' => 'nullable|numeric|min:1',
            'package' => 'nullable|string',
            'account' => 'nullable|in:north,south',
        ]);
        $service = $this->service($request->service);
        if (!$service) return $this->fail('الخدمة غير متوفرة', 404);

        $account = $this->gateway($service, $request);

        // Resolve the quoted amount — a package code, a unit count, or a
        // raw amount (same precedence as pay()).
        $amount = (float) $request->input('amount', 0);
        if ($request->filled('package')) {
            $pkg = collect($service->packages ?? [])->firstWhere('code', $request->package);
            if (!$pkg) return $this->fail('الباقة غير متوفرة لهذه الخدمة', 422);
            $net = $pkg['network'] ?? 'both';
            if ($net !== 'both' && $net !== $account) {
                return $this->fail($net === 'north'
                    ? 'هذه الباقة متاحة عبر بوابة الشمال فقط'
                    : 'هذه الباقة متاحة عبر بوابة الجنوب فقط', 422);
            }
            $amount = (float) ($pkg['price'] ?? 0);
        } elseif ($request->filled('units')) {
            $unitPrice = (float) ($service->meta['unit_price'] ?? 0);
            if ($unitPrice <= 0) return $this->fail('تسعير الوحدات غير مفعّل لهذه الخدمة', 422);
            $amount = round((float) $request->units * $unitPrice, 2);
        }
        if ($amount <= 0) return $this->fail('أدخل مبلغاً أو باقة صحيحة', 422);
        $fee = $this->feeFor($service, $amount);
        $total = $amount + $fee;

        $buyerRegion = $request->user()->region_type ?? 'south';
        $providerCurrency = $account; // 'north' gateway bills in north currency
        $charge = CurrencyService::convert($total, $providerCurrency, $buyerRegion);

        return response()->json(['success' => true, 'data' => [
            'account' => $account,
            'amount' => $amount,
            'fee' => $fee,
            'total_provider' => $total,
            'provider_currency' => $providerCurrency,
            'wallet_charge' => $charge,
            'wallet_currency' => $buyerRegion,
            'converted' => $providerCurrency !== $buyerRegion,
            // Delivered-credit estimate (tax-inclusive → net) when configured.
            'net' => isset($service->meta['net_ratio'])
                ? round($amount * (float) $service->meta['net_ratio'])
                : null,
            'unit_price' => ($service->meta['unit_price'] ?? null) !== null
                ? (float) $service->meta['unit_price'] : null,
            'units' => $request->filled('units') ? (float) $request->units : null,
        ]]);
    }

    // ── POST /topup/game — games & gift cards ───────────────────────
    public function game(Request $request): JsonResponse
    {
        $request->validate([
            'type' => 'required|string',
            'uniqcode' => 'required|string',
            'playerid' => 'required|string',
            'mobile' => 'required|digits:9',
            'amount' => 'required|numeric|min:1',
        ]);
        $service = $this->service('games');
        if (!$service) return $this->fail('الخدمة غير متوفرة', 404);

        $params = [
            'type' => $request->type,
            'uniqcode' => $request->uniqcode,
            'playerid' => $request->playerid,
            'playername' => (string) $request->input('playername', ''),
            'zoneid' => (string) $request->input('zoneid', ''),
            'email' => (string) $request->input('email', ''),
            'mobile' => $request->mobile,
        ];

        return $this->chargeAndSubmit(
            $request->user(), $service, (string) $request->mobile, (float) $request->amount,
            'gameswcards', $params, (string) $request->mobile, [],
            $this->gateway($service, $request),
            $request->all()
        );
    }

    // ── POST /topup/offer/activate — activate a numbered offer ──────
    public function activateOffer(Request $request): JsonResponse
    {
        $request->validate([
            'service' => 'required|string|in:yem',
            'num' => 'required|digits:9',
            'offer' => 'required',          // offerid (yem) or offerkey (offeryem)
            'offer_kind' => 'required|in:id,key',
            'method' => 'required|in:New,Renew,Remove',
            'solfa' => 'nullable|in:Y,N',
        ]);
        $service = $this->service('yem');
        if (!$service) return $this->fail('الخدمة غير متوفرة', 404);

        // Resolve the offer price server-side — never trust a client-sent price.
        $list = $this->provider->call($this->gateway($service, $request), 'yem', ['action' => 'queryoffer'], $request->num);
        $price = $this->extractOfferPrice($list['data'] ?? [], $request->offer, $request->offer_kind);
        if ($price === null) return $this->fail('تعذر تحديد سعر العرض — حدّث قائمة العروض وحاول مجدداً', 422);

        if ($request->offer_kind === 'key') {
            $params = ['action' => 'billoffer', 'offerkey' => $request->offer, 'method' => $request->method, 'solfa' => $request->input('solfa', 'N')];
            $endpoint = 'offeryem';
        } else {
            $params = ['action' => 'billoffer', 'offerid' => $request->offer, 'method' => $request->method];
            $endpoint = 'yem';
        }

        return $this->chargeAndSubmit(
            $request->user(), $service, $request->num, $price,
            $endpoint, $params, $request->num, [],
            $this->gateway($service, $request),
            ['offer' => $request->offer, 'kind' => $request->offer_kind, 'method' => $request->method]
        );
    }

    // ── GET /topup/orders ───────────────────────────────────────────
    public function orders(Request $request): JsonResponse
    {
        $orders = TopupOrder::where('user_id', $request->user()->id)
            ->latest()->limit(100)->get();
        return response()->json(['success' => true, 'data' => $orders]);
    }

    // ── GET /topup/orders/{id}/status — poll provider + auto-refund ──
    public function orderStatus(Request $request, int $id): JsonResponse
    {
        $order = TopupOrder::where('user_id', $request->user()->id)->findOrFail($id);
        if ($order->status === 'done' || ($order->status === 'failed' && $order->refunded)) {
            return response()->json(['success' => true, 'data' => $order]);
        }

        $res = $this->provider->status($order->account, $order->target, $order->transid);
        $data = $res['data'] ?? [];

        if (!empty($data)) {
            if ((string) ($data['isDone'] ?? '0') === '1') {
                $order->update(['status' => 'done', 'provider_response' => $data, 'provider_price' => $data['price'] ?? $order->provider_price]);
            } elseif ((string) ($data['isBan'] ?? '0') === '1') {
                $this->refund($order, 'العملية محظورة لدى المزود');
                $order->update(['status' => 'banned', 'provider_response' => $data]);
            }
        }

        return response()->json(['success' => true, 'data' => $order->fresh()]);
    }

    // ══ Internals ═══════════════════════════════════════════════════

    private function service(string $code): ?TopupServiceSetting
    {
        return TopupServiceSetting::where('code', $code)->where('is_active', true)->first();
    }

    /**
     * Effective provider account for this operation. The client may request
     * the "north" gateway explicitly; otherwise the service's configured
     * account applies.
     */
    private function gateway(TopupServiceSetting $service, Request $request): string
    {
        $acc = (string) $request->input('account', $service->account);
        return in_array($acc, ['north', 'south'], true) ? $acc : $service->account;
    }

    private function feeFor(TopupServiceSetting $service, float $amount): float
    {
        return match ($service->fee_type) {
            'percent' => round($amount * ((float) $service->fee_value / 100), 2),
            'fixed' => round((float) $service->fee_value, 2),
            default => 0.0,
        };
    }

    /**
     * Activate a predefined package (meta-driven catalog). The price and the
     * provider call are resolved server-side so the client cannot tamper.
     */
    private function payPackage(Request $request, TopupServiceSetting $service, string $num): JsonResponse
    {
        $code = (string) $request->input('package');
        $packages = collect($service->packages ?? []);
        $pkg = $packages->firstWhere('code', $code);
        if (!$pkg) return $this->fail('الباقة غير متوفرة لهذه الخدمة', 422);

        $price = (float) ($pkg['price'] ?? 0);
        if ($price <= 0) return $this->fail('سعر الباقة غير معرّف', 422);

        $account = $this->gateway($service, $request);

        // Gateway-gated packages (TaizTel splits catalogs by north/south).
        $net = $pkg['network'] ?? 'both';
        if ($net !== 'both' && $net !== $account) {
            return $this->fail($net === 'north'
                ? 'هذه الباقة متاحة عبر بوابة الشمال فقط'
                : 'هذه الباقة متاحة عبر بوابة الجنوب فقط', 422);
        }

        // Per-package activation mode overrides the service-level package_mode:
        //   mtnoffer/sabaoffer → endpoint takes the package code as `num`
        //   offeryem           → offer-key activation (method + optional solfa)
        //   billoffer          → Yemen Mobile offer-id activation
        //   amount (default)   → bill the package price via the service endpoint
        $mode = $pkg['activation'] ?? ($service->meta['package_mode'] ?? 'amount');
        $submit = fn (string $endpoint, array $params) => $this->chargeAndSubmit(
            $request->user(), $service, $num, $price,
            $endpoint, $params, $num, [],
            $account,
            ['package' => $code, 'name' => $pkg['name'] ?? '']
        );

        switch ($mode) {
            case 'sabaoffer':
            case 'mtnoffer':
            case 'sabaunits':
                return $submit($mode, ['num' => $code]);
            case 'offeryem':
                return $submit('offeryem', [
                    'offerkey' => $code,
                    'method' => $request->input('method', 'New'),
                    'solfa' => $request->input('solfa', 'N'),
                ]);
            case 'billoffer':
                return $submit('yem', ['action' => 'billoffer', 'offerid' => $code]);
        }

        // Default: bill the package's price through the service's own endpoint.
        // Optional per-package params (e.g. {"type":"adsl"}) flow into the call.
        $extra = [];
        if (!empty($pkg['params'])) {
            $decoded = is_array($pkg['params']) ? $pkg['params'] : (json_decode((string) $pkg['params'], true) ?: []);
            $extra = $decoded;
        }
        $request->merge(['amount' => $price] + $extra);
        [$endpoint, $params, $postBody, $mobile] = $this->buildBillCall($service, $request);
        if ($endpoint === null) return $this->fail('نوع عملية غير مدعوم لهذه الخدمة', 422);

        return $this->chargeAndSubmit(
            $request->user(), $service, $num, $price,
            $endpoint, $params, $mobile, $postBody,
            $account,
            ['package' => $code, 'name' => $pkg['name'] ?? '']
        );
    }

    private function validateTarget(TopupServiceSetting $service, string $num, Request $request): void
    {
        $fields = collect($service->meta['fields'] ?? []);
        $numField = $fields->firstWhere('key', 'num');
        $len = (int) ($numField['len'] ?? 0);

        if ($len > 0 && !preg_match('/^\d{' . $len . '}$/', $num)) {
            abort(response()->json(['success' => false, 'message' => "الرقم يجب أن يكون {$len} خانات"], 422));
        }
        if ($num === '') {
            abort(response()->json(['success' => false, 'message' => 'الرقم مطلوب'], 422));
        }
    }

    /**
     * Map a service + request into a provider "bill" call.
     * @return array{0:?string,1:array,2:array,3:string}
     */
    private function buildBillCall(TopupServiceSetting $service, Request $request): array
    {
        $num = (string) $request->input('num');
        $amount = $request->amount;

        // NOTE: for mtn / sabaphone / sbay / adenet / gomla the provider's
        // `num` parameter is the AMOUNT (or quantity) — `mobile` carries the
        // subscriber number. Sending the phone as `num` would bill wrongly.
        return match ($service->provider_endpoint) {
            'yem' => ['yem', ['action' => 'bill', 'amount' => $amount], [], $num],
            'sbay' => ['sbay', ['action' => 'bill', 'num' => $amount], [], $num],
            'sabaphone' => ['sabaphone', ['action' => 'bill', 'num' => $amount], [], $num],
            'adenet' => ['adenet', ['action' => 'bill', 'num' => $amount], [], $num],
            'sabagomla', 'mtngomla', 'mobilegomla' => [$service->provider_endpoint, ['num' => $amount], [], $num],
            'mtn' => ['mtn', [
                'action' => 'bill', 'num' => $amount,
                'type' => $request->input('type', 'prepaid'),
                'israsid' => $request->input('israsid', '0'),
            ], [], $num],
            'yem4g' => ['yem4g', [
                'action' => 'bill', 'amount' => $amount,
                'type' => $request->input('type', '1'),
            ], [], $num],
            'post' => ['post', [
                'action' => 'bill', 'amount' => $amount,
                'type' => $request->input('type', 'line'),
            ], [], $num],
            // «way» numbers map to the provider's «why» endpoint — supports
            // optional rasid (credit type) and packageid (bundle code).
            'way' => ['why', array_filter([
                'action' => 'bill', 'num' => $amount,
                'rasid' => $request->input('rasid'),
                'packageid' => $request->input('packageid'),
            ], fn ($v) => $v !== null), [], $num],
            // electwater `mobile` must be the agent's 9-digit number;
            // the subscriber goes in POST `userid`.
            'electwater' => ['electwater', [
                'action' => 'bill', 'amount' => $amount,
                'act' => $service->meta['act'] ?? 'elect',
            ], ['userid' => $num, 'placeid' => (string) $request->input('placeid', '')],
                config('taiztel.accounts.' . $this->gateway($service, $request) . '.username')],
            default => [null, [], [], $num],
        };
    }

    /**
     * Debit the wallet, create the order, submit to provider, settle status.
     */
    private function chargeAndSubmit($user, TopupServiceSetting $service, string $target, float $amount, string $endpoint, array $params, string $mobile, array $postBody, string $account, array $payload): JsonResponse
    {
        // Fee in the gateway's currency, then convert the total to the buyer's currency.
        $fee = $this->feeFor($service, $amount);
        $totalNative = $amount + $fee;
        $buyerRegion = $user->region_type ?? 'south';
        $providerCurrency = $account; // south gateway → southern YER, north → northern
        $charge = CurrencyService::convert($totalNative, $providerCurrency, $buyerRegion);

        $transid = $this->provider->newTransId();

        $order = DB::transaction(function () use ($user, $service, $target, $amount, $fee, $charge, $transid, $account, $payload) {
            $locked = $user->newQuery()->where('id', $user->id)->lockForUpdate()->first();
            if ((float) $locked->balance < $charge || (float) $locked->available_balance < $charge) {
                abort(response()->json(['success' => false, 'message' => 'رصيدك غير كافٍ لإتمام العملية'], 422));
            }
            $before = (float) $locked->balance;
            $locked->decrement('balance', $charge);
            $locked->decrement('available_balance', $charge);
            $locked->refresh();

            $order = TopupOrder::create([
                'user_id' => $locked->id,
                'service_code' => $service->code,
                'account' => $account,
                'target' => $target,
                'amount' => $amount,
                'fee' => $fee,
                'total_charged' => $charge,
                'transid' => $transid,
                'status' => 'pending',
                'request_payload' => $payload,
            ]);

            WalletLog::create([
                'user_id' => $locked->id,
                'type' => 'debit',
                'amount' => $charge,
                'balance_before' => $before,
                'balance_after' => $locked->balance,
                'description' => 'شحن فوري — ' . $service->name_ar . ' (' . $target . ')',
                'reference_type' => 'topup',
                'reference_id' => $order->id,
            ]);

            return $order;
        });

        // Provider call outside the DB transaction.
        $res = $this->provider->call($order->account, $endpoint, $params, $mobile, $transid, $postBody);
        $data = $res['data'] ?? [];
        $code = (string) ($data['resultCode'] ?? ($res['ok'] ? '' : 'http_error'));

        if ($code === '0') {
            $order->update([
                'status' => 'done',
                'result_code' => $code,
                'result_desc' => $data['resultDesc'] ?? null,
                'provider_ref_id' => $data['sequenceId'] ?? $data['ref_id'] ?? null,
                'provider_price' => $data['price'] ?? null,
                'provider_response' => $data,
            ]);
        } elseif ($code === '-2') {
            // Under process — keep pending; orderStatus() resolves it later.
            $order->update(['result_code' => $code, 'result_desc' => $data['resultDesc'] ?? 'قيد المعالجة', 'provider_response' => $data]);
        } else {
            $this->refund($order, $data['resultDesc'] ?? 'رفض المزود العملية');
            $order->update([
                'status' => 'failed',
                'result_code' => $code,
                'result_desc' => $data['resultDesc'] ?? ($res['http_error'] ?? 'خطأ في الاتصال بالمزود'),
                'provider_response' => $data,
            ]);
        }

        return response()->json([
            'success' => in_array($order->fresh()->status, ['done', 'pending'], true),
            'message' => $order->result_desc ?? ($order->status === 'pending' ? 'العملية قيد المعالجة لدى المزود' : 'تمت العملية'),
            'data' => $order->fresh(),
        ]);
    }

    private function refund(TopupOrder $order, string $reason): void
    {
        if ($order->refunded) return;
        DB::transaction(function () use ($order, $reason) {
            $user = $order->user()->lockForUpdate()->first();
            $before = (float) $user->balance;
            $user->increment('balance', (float) $order->total_charged);
            $user->increment('available_balance', (float) $order->total_charged);
            $user->refresh();
            WalletLog::create([
                'user_id' => $user->id,
                'type' => 'credit',
                'amount' => $order->total_charged,
                'balance_before' => $before,
                'balance_after' => $user->balance,
                'description' => 'استرداد شحن فوري — ' . $reason,
                'reference_type' => 'topup_refund',
                'reference_id' => $order->id,
            ]);
            $order->update(['refunded' => true]);
        });
    }

    private function extractOfferPrice(array $data, string $offer, string $kind): ?float
    {
        // Offers may come as a flat list or nested — walk and match.
        $lists = [];
        array_walk_recursive($data, function ($v, $k) use (&$lists) { $lists[$k][] = $v; });

        foreach ($this->flattenOffers($data) as $item) {
            if (!is_array($item)) continue;
            $id = (string) ($item['offerid'] ?? $item['offerId'] ?? $item['id'] ?? '');
            $key = (string) ($item['offerkey'] ?? $item['offerKey'] ?? $item['key'] ?? '');
            if (($kind === 'id' && $id === (string) $offer) || ($kind === 'key' && $key === (string) $offer)) {
                $price = $item['price'] ?? $item['amount'] ?? $item['cost'] ?? null;
                return $price !== null ? (float) $price : null;
            }
        }
        return null;
    }

    private function flattenOffers(array $data): array
    {
        $out = [];
        $walk = function ($node) use (&$walk, &$out) {
            if (!is_array($node)) return;
            if (array_is_list($node)) {
                foreach ($node as $v) $walk($v);
            } elseif (isset($node['offerid']) || isset($node['offerkey']) || isset($node['offerId']) || isset($node['offerKey'])) {
                $out[] = $node;
            } else {
                foreach ($node as $v) $walk($v);
            }
        };
        $walk($data);
        return $out;
    }

    private function providerReply(array $res): JsonResponse
    {
        $data = $res['data'] ?? [];
        $code = (string) ($data['resultCode'] ?? '');
        if ($code !== '' && $code !== '0') {
            return response()->json(['success' => false, 'message' => $data['resultDesc'] ?? 'خطأ من المزود', 'data' => $data], 422);
        }
        return response()->json(['success' => true, 'data' => $data]);
    }

    private function fail(string $message, int $status): JsonResponse
    {
        return response()->json(['success' => false, 'message' => $message], $status);
    }
}
