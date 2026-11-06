<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\MikrotikSubscription;
use App\Services\MikrotikPageRenderer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

/**
 * Hotspot login-page template store.
 *
 * The owner picks a template + customizes name/colors/logo; we render
 * the file set to a temp folder and the router downloads each file
 * via `/tool/fetch` — RouterOS API cannot receive file contents, so
 * this pull-model replaces FTP for hosted templates.
 *
 * `serve()` is public (router fetch carries no token); rendered
 * folders expire after 24h.
 */
class NetworkOwnerMikrotikPageController extends Controller
{
    public function __construct(private MikrotikPageRenderer $renderer) {}

    /** GET /network-owner/mikrotik/page-templates — template catalog. */
    public function index(): JsonResponse
    {
        return response()->json([
            'success' => true,
            'data' => $this->renderer->templates(),
        ]);
    }

    /** POST /network-owner/mikrotik/page-templates/render. */
    public function render(Request $request): JsonResponse
    {
        $v = Validator::make($request->all(), [
            'template_id' => 'required|string|max:40',
            'network_name' => 'nullable|string|max:80',
            'welcome_msg' => 'nullable|string|max:160',
            'whatsapp' => 'nullable|string|max:20',
            'speed_label' => 'nullable|string|max:40',
            'color_primary' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'color_accent' => ['nullable', 'regex:/^#[0-9a-fA-F]{6}$/'],
            'logo' => 'nullable|image|mimes:png,jpg,jpeg,webp,svg|max:2048',
            'logo_base64' => 'nullable|string|max:3000000',
        ]);
        if ($v->fails()) {
            return response()->json(
                ['success' => false, 'errors' => $v->errors()], 422);
        }

        $id = $request->input('template_id');
        if (!$this->renderer->exists($id)) {
            return response()->json(
                ['success' => false, 'message' => 'القالب غير موجود'], 404);
        }

        if ($this->renderer->isPremium($id)
            && !$this->hasPaidSubscription($request->user()->id)) {
            return response()->json([
                'success' => false,
                'message' => 'هذا القالب مخصص للباقات المدفوعة — فعّل اشتراكاً للاستفادة منه',
            ], 403);
        }

        $logo = $this->logoDataUri($request);

        $vars = [
            'network_name' => $request->input('network_name', 'شبكتي'),
            'welcome_msg' => $request->input('welcome_msg', ''),
            'whatsapp' => $request->input('whatsapp', ''),
            'speed_label' => $request->input('speed_label', ''),
            'color_primary' => $request->input('color_primary', '#1a3a6b'),
            'color_accent' => $request->input('color_accent', '#c8102e'),
        ];

        $result = $this->renderer->render($id, $vars, $logo);

        $files = array_map(fn($f) => [
            'name' => $f['name'],
            'url' => url("/api/mikrotik-pages/{$result['render_id']}/{$f['name']}"),
        ], $result['files']);

        return response()->json([
            'success' => true,
            'data' => [
                'render_id' => $result['render_id'],
                'files' => $files,
                'preview_url' => url(
                    "/api/mikrotik-pages/{$result['render_id']}/preview.html"),
            ],
        ]);
    }

    /** GET /api/mikrotik-pages/{render}/{file} — public (router fetch). */
    public function serve(string $render, string $file): BinaryFileResponse|JsonResponse
    {
        $path = $this->renderer->filePath($render, $file);
        if (!$path) {
            return response()->json(
                ['success' => false, 'message' => 'not found'], 404);
        }
        $mime = match (pathinfo($file, PATHINFO_EXTENSION)) {
            'html' => 'text/html; charset=utf-8',
            'js' => 'application/javascript',
            'css' => 'text/css',
            'png' => 'image/png',
            'svg' => 'image/svg+xml',
            default => 'application/octet-stream',
        };
        return response()->file($path, ['Content-Type' => $mime]);
    }

    /** Premium templates need a paid, still-running subscription. */
    private function hasPaidSubscription(int $userId): bool
    {
        return MikrotikSubscription::where('user_id', $userId)
            ->where('status', 'active')
            ->where('ends_at', '>', now())
            ->exists();
    }

    /** Embed the owner's logo as a data-URI so the page needs zero
     * extra files — captive portals load before any internet. */
    private function logoDataUri(Request $request): ?string
    {
        if ($request->hasFile('logo')) {
            $file = $request->file('logo');
            return 'data:' . $file->getMimeType() . ';base64,'
                . base64_encode(file_get_contents($file->getRealPath()));
        }
        $b64 = $request->input('logo_base64');
        if (is_string($b64) && str_starts_with($b64, 'data:image/')) {
            return $b64;
        }
        return null;
    }
}
