<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccBackup;
use App\Services\AccBackupService;
use App\Services\AccContext;
use App\Services\AccOrderException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Accounting backup registry (ACC-12, PLAN §4):
 * POST /backup exports, GET /backups lists, download streams the
 * snapshot, import registers an uploaded file, restore atomically
 * replaces the tenant's acc_* state (AccBackupService).
 */
class AccBackupController extends Controller
{
    public function __construct(private AccBackupService $backups) {}

    public function index(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        $rows = AccBackup::where('network_owner_id', $ctx->ownerId)
            ->latest('id')
            ->paginate(25);

        return response()->json([
            'success' => true,
            'data' => $rows->through(fn (AccBackup $b) => $this->serialize($b)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $backup = $this->backups->export($ctx);

        return response()->json([
            'success' => true,
            'message' => 'تم إنشاء النسخة الاحتياطية',
            'data' => $this->serialize($backup),
        ], 201);
    }

    public function download(Request $request, int $backup): StreamedResponse|JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = $this->owned($ctx, $backup);
        if (! $model->fileExists()) {
            return response()->json([
                'success' => false,
                'message' => 'ملف النسخة غير موجود على القرص',
            ], 404);
        }

        return Storage::disk('local')->download(
            $model->storagePath(), $model->filename
        );
    }

    public function import(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate(['file' => 'required|file|max:20480']);

        try {
            $backup = $this->backups->import($ctx, $request->file('file'));
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم استيراد النسخة — جاهزة للاستعادة',
            'data' => $this->serialize($backup),
        ], 201);
    }

    public function restore(Request $request, int $backup): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $model = $this->owned($ctx, $backup);

        try {
            $stats = $this->backups->restore($ctx, $model);
        } catch (AccOrderException $e) {
            return $this->fail($e);
        }

        return response()->json([
            'success' => true,
            'message' => "تمت الاستعادة — {$stats['rows']} سجلاً أُعيد",
        ]);
    }

    private function owned(AccContext $ctx, int $id): AccBackup
    {
        $model = AccBackup::where('network_owner_id', $ctx->ownerId)->find($id);
        abort_if($model === null, 404, 'النسخة غير موجودة');

        return $model;
    }

    private function serialize(AccBackup $b): array
    {
        return [
            'id' => $b->id,
            'filename' => $b->filename,
            'size' => (int) $b->size,
            'tables_count' => (int) $b->tables_count,
            'rows_count' => (int) $b->rows_count,
            'checksum' => $b->checksum,
            'file_exists' => $b->fileExists(),
            'created_at' => $b->created_at?->toISOString(),
        ];
    }

    private function fail(AccOrderException $e): JsonResponse
    {
        return response()->json([
            'success' => false,
            'message' => $e->getMessage(),
        ], $e->status);
    }
}
