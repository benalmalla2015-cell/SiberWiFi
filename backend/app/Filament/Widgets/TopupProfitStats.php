<?php

namespace App\Filament\Widgets;

use App\Models\Card;
use App\Models\TopupOrder;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;
use Illuminate\Support\Facades\DB;

/**
 * إحصاءات أرباح الشحن الفوري + إيراد مبيعات الكروت.
 *
 * دلالة الحقول في topup_orders:
 *   - fee            العمولة المسجّلة لكل عملية (بعملة البوابة account)
 *   - total_charged  المخصوم من محفظة العميل (بعملة منطقته)
 *   - provider_price تكلفة المزود الفعلية (بعملة البوابة)
 * لذلك تُعرض العمولة مجمّعة حسب عملة البوابة — لا خلط بين العملتين.
 */
class TopupProfitStats extends StatsOverviewWidget
{
    protected ?string $heading = 'أرباح الشحن الفوري ومبيعات الكروت';

    protected int | array | null $columns = 4;

    protected function getStats(): array
    {
        $done = TopupOrder::where('status', 'done');

        $feeSouth = (float) (clone $done)->where('account', 'south')->sum('fee');
        $feeNorth = (float) (clone $done)->where('account', 'north')->sum('fee');
        $feeSouthToday = (float) (clone $done)->where('account', 'south')->whereDate('created_at', today())->sum('fee');
        $feeNorthToday = (float) (clone $done)->where('account', 'north')->whereDate('created_at', today())->sum('fee');
        $feeSouthMonth = (float) (clone $done)->where('account', 'south')->whereMonth('created_at', now()->month)->sum('fee');
        $feeNorthMonth = (float) (clone $done)->where('account', 'north')->whereMonth('created_at', now()->month)->sum('fee');

        $doneCount = (clone $done)->count();
        $pendingCount = TopupOrder::where('status', 'pending')->count();
        $failedCount = TopupOrder::whereIn('status', ['failed', 'banned'])->count();
        $refundedCount = TopupOrder::where('refunded', true)->count();

        // إيراد مبيعات الكروت = مجموع أسعار فئات الكروت المباعة.
        $cardsSold = Card::where('status', 'sold')->count();
        $cardsRevenue = (float) DB::table('cards')
            ->join('card_categories', 'cards.category_id', '=', 'card_categories.id')
            ->where('cards.status', 'sold')
            ->sum('card_categories.price');

        $fmt = fn (float $v) => number_format($v, 2);

        return [
            Stat::make('إجمالي عمولة الشحن — جنوب', "{$fmt($feeSouth)} ر.ج")
                ->description("اليوم {$fmt($feeSouthToday)} · الشهر {$fmt($feeSouthMonth)}")
                ->icon('heroicon-o-banknotes')
                ->color('success'),
            Stat::make('إجمالي عمولة الشحن — شمال', "{$fmt($feeNorth)} ر.ش")
                ->description("اليوم {$fmt($feeNorthToday)} · الشهر {$fmt($feeNorthMonth)}")
                ->icon('heroicon-o-banknotes')
                ->color('info'),
            Stat::make('العمليات', (string) $doneCount)
                ->description("معلّقة {$pendingCount} · فاشلة {$failedCount} · مستردة {$refundedCount}")
                ->icon('heroicon-o-clipboard-document-check')
                ->color($failedCount > 0 ? 'warning' : 'success'),
            Stat::make('إيراد مبيعات الكروت', "{$fmt($cardsRevenue)} ر.ي")
                ->description("{$cardsSold} كرت مُباع")
                ->icon('heroicon-o-ticket')
                ->color('primary'),
        ];
    }
}
