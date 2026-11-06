<?php

namespace App\Http\Controllers\Api\Accounting;

use App\Http\Controllers\Controller;
use App\Models\AccDocHeader;
use App\Services\AccContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

/**
 * Printed-document header (ACC-12, PLAN §2.5): one settings row
 * per tenant + an optional private logo image streamed through
 * GET /doc-header/logo.
 */
class AccDocHeaderController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);

        return response()->json([
            'success' => true,
            'data' => $this->serialize($this->row($ctx)),
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $data = $request->validate([
            'business_name' => 'nullable|string|max:190',
            'subtitle' => 'nullable|string|max:190',
            'phone' => 'nullable|string|max:40',
            'address' => 'nullable|string|max:190',
            'footer_text' => 'nullable|string|max:190',
            'show_logo' => 'nullable|boolean',
        ]);

        $row = $this->row($ctx);
        $row->fill([
            'business_name' => array_key_exists('business_name', $data)
                ? $data['business_name'] : $row->business_name,
            'subtitle' => array_key_exists('subtitle', $data) ? $data['subtitle'] : $row->subtitle,
            'phone' => array_key_exists('phone', $data) ? $data['phone'] : $row->phone,
            'address' => array_key_exists('address', $data) ? $data['address'] : $row->address,
            'footer_text' => array_key_exists('footer_text', $data) ? $data['footer_text'] : $row->footer_text,
            'show_logo' => array_key_exists('show_logo', $data)
                ? filter_var($data['show_logo'], FILTER_VALIDATE_BOOLEAN)
                : $row->show_logo,
        ]);
        $row->save();

        return response()->json([
            'success' => true,
            'message' => 'تم حفظ رأس المستند',
            'data' => $this->serialize($row),
        ]);
    }

    /** Upload/replace the private logo image (png|jpg|webp ≤ 2MB). */
    public function uploadLogo(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $request->validate([
            'logo' => 'required|file|mimes:png,jpg,jpeg,webp|max:2048',
        ]);

        $row = $this->row($ctx);
        $dir = 'acc_doc_logos/' . $ctx->ownerId;
        $path = $request->file('logo')->store($dir, 'local');

        // Drop the previous file — the row tracks the current one.
        if ($row->logo_path && $row->logo_path !== $path) {
            Storage::disk('local')->delete($row->logo_path);
        }
        $row->logo_path = $path;
        $row->show_logo = true;
        $row->save();

        return response()->json([
            'success' => true,
            'message' => 'تم رفع الشعار',
            'data' => $this->serialize($row),
        ]);
    }

    public function removeLogo(Request $request): JsonResponse
    {
        $ctx = AccContext::fromRequest($request);
        $row = $this->row($ctx);
        if ($row->logo_path) {
            Storage::disk('local')->delete($row->logo_path);
        }
        $row->logo_path = null;
        $row->save();

        return response()->json([
            'success' => true,
            'message' => 'تم حذف الشعار',
            'data' => $this->serialize($row),
        ]);
    }

    /** Streams the private logo — auth'd, tenant-scoped. */
    public function logo(Request $request)
    {
        $ctx = AccContext::fromRequest($request);
        $row = $this->row($ctx);
        abort_if(
            $row->logo_path === null || ! Storage::disk('local')->exists($row->logo_path),
            404, 'لا يوجد شعار'
        );

        return Storage::disk('local')->response($row->logo_path);
    }

    private function row(AccContext $ctx): AccDocHeader
    {
        return AccDocHeader::firstOrCreate(
            ['network_owner_id' => $ctx->ownerId],
            ['show_logo' => true]
        );
    }

    private function serialize(AccDocHeader $h): array
    {
        return [
            'business_name' => $h->business_name,
            'subtitle' => $h->subtitle,
            'phone' => $h->phone,
            'address' => $h->address,
            'footer_text' => $h->footer_text,
            'show_logo' => (bool) $h->show_logo,
            'has_logo' => $h->logo_path !== null
                && Storage::disk('local')->exists($h->logo_path),
        ];
    }
}
