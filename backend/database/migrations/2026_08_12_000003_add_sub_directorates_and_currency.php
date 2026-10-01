<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Real known مديريات (districts) for the governorates the client
     * specifically requested. Any other existing governorate gets a single
     * placeholder district (named after the governorate) so the system
     * keeps working end-to-end; admins can add the real districts anytime
     * from "المديريات" in the dashboard without any further code changes.
     */
    private function districtsMap(): array
    {
        return [
            'عدن' => ['صيرة (كريتر)', 'خور مكسر', 'المعلا', 'التواهي', 'المنصورة', 'الشيخ عثمان', 'دار سعد', 'البريقة'],
            'أبين' => ['زنجبار', 'خنفر', 'لودر', 'المحفد', 'مودية', 'الوضيع', 'حجر', 'ميفعة', 'أحور', 'سرار', 'جيشان'],
            'حضرموت' => ['المكلا', 'سيئون', 'تريم', 'الشحر', 'القطن', 'دوعن', 'غيل باوزير', 'حورة', 'ثمود', 'عمد', 'الديس الشرقية', 'شبام'],
            'شبوة' => ['عتق', 'بيحان', 'نصاب', 'عرما', 'رضوم', 'الروضة', 'الطلح', 'حبان', 'جردان', 'مرخة العليا', 'مرخة السفلى', 'ميفعة', 'النشيمة', 'حطيب'],
            'المهرة' => ['الغيضة', 'سيحوت', 'قشن', 'حصوين', 'حوف', 'شحن', 'منعر', 'دمقوت', 'الفلج'],
            'صنعاء' => ['بني حشيش', 'سنحان', 'همدان', 'أرحب', 'خولان', 'بلاد الروس', 'مناخة', 'الحيمة الداخلية', 'الحيمة الخارجية'],
            'تعز' => ['القاهرة', 'صالة', 'المسراخ', 'المواسط', 'شرعب الرونة', 'شرعب السلام', 'صبر الموادم', 'الشمايتين', 'المعافر'],
            'إب' => ['إب', 'يريم', 'المخادر', 'حبيش', 'السدة', 'ذي السفال', 'العدين', 'الظهار'],
            'الحديدة' => ['الحديدة', 'باجل', 'الزهرة', 'الزيدية', 'المراوعة', 'الدريهمي', 'بيت الفقيه'],
        ];
    }

    public function up(): void
    {
        if (!Schema::hasTable('sub_directorates')) {
            Schema::create('sub_directorates', function (Blueprint $table) {
                $table->id();
                $table->foreignId('directorate_id')->constrained('directorates')->cascadeOnDelete();
                $table->string('name');
                $table->string('name_en')->nullable();
                $table->boolean('is_active')->default(true);
                $table->timestamps();
            });
        }

        Schema::table('users', function (Blueprint $table) {
            if (!Schema::hasColumn('users', 'sub_directorate_id')) {
                $table->foreignId('sub_directorate_id')->nullable()->after('directorate_id')
                    ->constrained('sub_directorates')->nullOnDelete();
            }
        });

        Schema::table('networks', function (Blueprint $table) {
            if (!Schema::hasColumn('networks', 'sub_directorate_id')) {
                $table->foreignId('sub_directorate_id')->nullable()->after('directorate_id')
                    ->constrained('sub_directorates')->nullOnDelete();
            }
        });

        if (!Schema::hasTable('exchange_rate_settings')) {
            Schema::create('exchange_rate_settings', function (Blueprint $table) {
                $table->id();
                $table->enum('base_currency', ['north', 'south'])->default('north');
                // How many units of the OTHER currency equal 100 units of the base currency.
                // Example: base=north, rate_percent=380 => 100 ريال شمال = 380 ريال جنوب
                $table->decimal('rate_percent', 10, 4)->default(100);
                $table->text('description')->nullable();
                $table->boolean('is_active')->default(true);
                $table->timestamps();
            });
        }

        // Seed districts for existing governorates (idempotent).
        $map = $this->districtsMap();
        $directorates = DB::table('directorates')->select('id', 'name')->get();
        foreach ($directorates as $directorate) {
            $existing = DB::table('sub_directorates')->where('directorate_id', $directorate->id)->count();
            if ($existing > 0) {
                continue;
            }
            $names = $map[$directorate->name] ?? [$directorate->name];
            $now = now();
            $rows = array_map(fn ($name) => [
                'directorate_id' => $directorate->id,
                'name' => $name,
                'is_active' => true,
                'created_at' => $now,
                'updated_at' => $now,
            ], $names);
            DB::table('sub_directorates')->insert($rows);
        }

        if (DB::table('exchange_rate_settings')->count() === 0) {
            DB::table('exchange_rate_settings')->insert([
                'base_currency' => 'north',
                'rate_percent' => 380,
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    public function down(): void
    {
        Schema::table('networks', function (Blueprint $table) {
            $table->dropConstrainedForeignId('sub_directorate_id');
        });
        Schema::table('users', function (Blueprint $table) {
            $table->dropConstrainedForeignId('sub_directorate_id');
        });
        Schema::dropIfExists('exchange_rate_settings');
        Schema::dropIfExists('sub_directorates');
    }
};
