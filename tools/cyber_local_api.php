#!/usr/bin/env php
<?php

/*
|--------------------------------------------------------------------------
| CYB-05 dev tool — local CyberNet API on sqlite
|--------------------------------------------------------------------------
| The staging MySQL is not reachable from a dev machine and legacy core
| migrations break on sqlite, so this script builds an isolated sqlite
| file carrying ONLY what the cyber routes touch:
|
|   - regions / directorates / sub_directorates, recreated at their real
|     column shape and seeded from live staging snapshots
|     (cyber_plan/governorates_seed.json, sub_directorates_seed.json —
|     re-fetch: /api/governorates + /api/sub-directorates)
|   - every 2026_11_02 migration (all are cyber_* / cyber-additive),
|     executed verbatim in filename order — packages self-seed
|     (200/800/1500).
|
| Usage (run from testapp/):
|   php tools/cyber_local_api.php --fresh     rebuild the sqlite file
|   php tools/cyber_local_api.php --serve [--port 8090] [--host 0.0.0.0]
|   php tools/cyber_local_api.php --topup 74XXXXXXX 5000
|                                           simulate an agent credit
|                                           through the real service
|
| --serve exports the sqlite env to the artisan child, so the running
| API is this file's database — nothing touches staging MySQL.
| Point the app at http://<lan-or-10.0.2.2>:PORT/api ; for a USB device
| use `adb reverse tcp:PORT tcp:PORT` and http://127.0.0.1:PORT/api.
*/

$opts = getopt('', ['fresh', 'serve', 'port:', 'host:', 'topup:', 'amount:']);
$backend = dirname(__DIR__).'/backend';
$dbFile = $backend.'/database/cyber_local.sqlite';
$planDir = dirname(__DIR__).'/cyber_plan';

// ---- env overrides (must precede the framework boot) -------------------
foreach ([
    'APP_ENV' => 'local',
    'APP_DEBUG' => 'true',
    'DB_CONNECTION' => 'sqlite',
    'DB_DATABASE' => $dbFile,
    'SESSION_DRIVER' => 'file',
    'SESSION_DRIVER' => 'file',
    'CACHE_STORE' => 'file',
    'QUEUE_CONNECTION' => 'sync',
    'BROADCAST_CONNECTION' => 'log',
    'CYBER_ENABLED' => 'true',
] as $k => $v) {
    putenv("$k=$v");
    $_ENV[$k] = $v;
    $_SERVER[$k] = $v;
}

if (isset($opts['fresh']) && file_exists($dbFile)) {
    unlink($dbFile);
}

if (! file_exists($dbFile)) {
    touch($dbFile);
}

require $backend.'/vendor/autoload.php';

/** @var \Illuminate\Foundation\Application $app */
$app = require $backend.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// ---- 1) lookup tables at their real shape -------------------------------
if (! Schema::hasTable('regions')) {
    Schema::create('regions', function ($table) {
        $table->id();
        $table->string('name');
        $table->string('name_en')->nullable();
        $table->string('type')->default('north');
        $table->string('currency')->default('YER_OLD');
        $table->boolean('is_active')->default(true);
        $table->timestamps();
    });
    out('created regions');
}
if (! Schema::hasTable('directorates')) {
    Schema::create('directorates', function ($table) {
        $table->id();
        $table->unsignedBigInteger('region_id');
        $table->string('name');
        $table->string('name_en')->nullable();
        $table->boolean('is_active')->default(true);
        $table->timestamps();
    });
    out('created directorates');
}
if (! Schema::hasTable('sub_directorates')) {
    Schema::create('sub_directorates', function ($table) {
        $table->id();
        $table->unsignedBigInteger('directorate_id');
        $table->string('name');
        $table->string('name_en')->nullable();
        $table->boolean('is_active')->default(true);
        $table->timestamps();
    });
    out('created sub_directorates');
}

// ---- 2) cyber migrations, verbatim --------------------------------------
$files = glob($backend.'/database/migrations/2026_11_02_*.php');
sort($files);
$ran = 0;
foreach ($files as $file) {
    $name = basename($file, '.php');
    // Skip tables that already exist so the tool is re-runnable without --fresh.
    if (preg_match('/create_([a-z_]+)_table/', $name, $m) && Schema::hasTable($m[1])) {
        continue;
    }
    if (str_contains($name, 'add_') && preg_match('/_to_([a-z_]+)_table/', $name, $m)
        && ! Schema::hasTable($m[1])) {
        continue;
    }
    $migration = require $file;
    try {
        $migration->up();
        $ran++;
        out("migrated $name");
    } catch (Throwable $e) {
        out("SKIP $name — {$e->getMessage()}");
    }
}
out("cyber migrations applied: $ran");

// ---- 3) seed lookups from staging snapshots ------------------------------
$now = date('Y-m-d H:i:s');
$govs = json_decode(file_get_contents($planDir.'/governorates_seed.json'), true)['data'] ?? [];
$subs = json_decode(file_get_contents($planDir.'/sub_directorates_seed.json'), true)['data'] ?? [];

if (DB::table('regions')->count() === 0) {
    $seen = [];
    foreach ($govs as $g) {
        if (! isset($seen[$g['region_id']])) {
            $seen[$g['region_id']] = $g['region'] ?? 'region '.$g['region_id'];
        }
    }
    foreach ($seen as $id => $name) {
        DB::table('regions')->insert([
            'id' => $id, 'name' => $name, 'name_en' => $name,
            'type' => 'north', 'currency' => 'YER_OLD', 'is_active' => 1,
            'created_at' => $now, 'updated_at' => $now,
        ]);
    }
}
if (DB::table('directorates')->count() === 0) {
    foreach ($govs as $g) {
        DB::table('directorates')->insert([
            'id' => $g['id'], 'region_id' => $g['region_id'],
            'name' => $g['name'], 'name_en' => $g['name_en'],
            'is_active' => 1, 'created_at' => $now, 'updated_at' => $now,
        ]);
    }
}
if (DB::table('sub_directorates')->count() === 0) {
    foreach ($subs as $s) {
        DB::table('sub_directorates')->insert([
            'id' => $s['id'], 'directorate_id' => $s['directorate_id'],
            'name' => $s['name'], 'name_en' => $s['name_en'],
            'is_active' => 1, 'created_at' => $now, 'updated_at' => $now,
        ]);
    }
}
out(sprintf('seeded: %d regions, %d directorates, %d sub_directorates',
    DB::table('regions')->count(),
    DB::table('directorates')->count(),
    DB::table('sub_directorates')->count()));

// ---- 4) --topup: simulate an agent credit via the real service -----------
if (isset($opts['topup'])) {
    $sim = (string) $opts['topup'];
    $amount = (float) ($opts['amount'] ?? 0);
    if ($amount <= 0) {
        fail('--topup requires --amount N');
    }
    $billing = $app->make(App\Services\CyberBillingService::class);
    $res = $billing->topup(1, $sim, $amount, 'local-'.bin2hex(random_bytes(8)));
    out("topup ok — sim {$res['topup']->sim_no} +{$res['topup']->amount} → balance {$res['balance']}");
}

// ---- 5) --serve -----------------------------------------------------------
if (isset($opts['serve'])) {
    $port = (string) ($opts['port'] ?? '8090');
    $host = (string) ($opts['host'] ?? '127.0.0.1');
    out("serving CyberNet API on http://$host:$port/api/cyber (db: $dbFile)");
    chdir($backend);
    passthru(
        escapeshellarg(PHP_BINARY).' artisan serve --host='.escapeshellarg($host).' --port='.escapeshellarg($port),
        $code
    );
    exit($code ?? 0);
}

function out(string $msg): void
{
    fwrite(STDOUT, "[cyber-local] $msg\n");
}

function fail(string $msg): void
{
    fwrite(STDERR, "[cyber-local] ERROR: $msg\n");
    exit(1);
}
