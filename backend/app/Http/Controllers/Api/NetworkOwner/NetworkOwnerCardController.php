<?php

namespace App\Http\Controllers\Api\NetworkOwner;

use App\Http\Controllers\Controller;
use App\Models\Card;
use App\Models\CardCategory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Validator;
use Maatwebsite\Excel\Facades\Excel;
use Maatwebsite\Excel\Concerns\ToArray;
use SimpleXMLElement;

class NetworkOwnerCardController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();

        $query = Card::with(['network:id,name', 'category:id,name,price,value'])
            ->whereIn('network_id', $networkIds);

        if ($request->network_id && in_array($request->network_id, $networkIds)) {
            $query->where('network_id', $request->network_id);
        }
        if ($request->status) {
            $query->where('status', $request->status);
        }
        if ($request->category_id) {
            $query->where('category_id', $request->category_id);
        }

        $perPage = min(max($request->integer('per_page', 50), 1), 10000);
        $cards = $query->latest()->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $cards->map(fn($c) => [
                'id' => $c->id,
                'serial' => $c->serial,
                'code' => $c->code ?? $c->card_number,
                'card_number' => $c->card_number,
                'status' => $c->status,
                'category' => $c->category ? [
                    'id' => $c->category->id,
                    'name' => $c->category->name,
                    'price' => (float) $c->category->price,
                    'value' => (float) $c->category->value,
                ] : null,
                'category_id' => $c->category_id,
                'price' => (float) ($c->category?->price ?? 0),
                'value' => (float) ($c->category?->value ?? 0),
                'network_name' => $c->network?->name,
                'sold_at' => $c->sold_at?->toDateTimeString(),
                'created_at' => $c->created_at->toDateTimeString(),
            ])->values(),
            'meta' => [
                'total' => $cards->total(),
                'current_page' => $cards->currentPage(),
                'last_page' => $cards->lastPage(),
            ],
        ]);
    }

    public function categories(Request $request): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();

        $categories = CardCategory::whereIn('network_id', $networkIds)
            ->withCount(['cards as available_count' => fn($q) => $q->where('status', 'available')])
            ->withCount(['cards as sold_count' => fn($q) => $q->where('status', 'sold')])
            ->orderBy('name')
            ->get()
            ->map(fn($c) => [
                'id' => $c->id,
                'network_id' => $c->network_id,
                'name' => $c->name,
                'speed' => $c->speed,
                'duration' => $c->duration,
                'duration_unit' => $c->duration_unit,
                'price' => (float) $c->price,
                'value' => (float) $c->value,
                'description' => $c->description,
                'is_active' => (bool) $c->is_active,
                'advance_enabled' => (bool) $c->advance_enabled,
                'advance_max_per_customer' => $c->advance_max_per_customer,
                'available_count' => $c->available_count,
                'sold_count' => $c->sold_count,
            ]);

        return response()->json(['success' => true, 'data' => $categories]);
    }

    public function storeCategory(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'network_id' => 'required|exists:networks,id',
            'name' => 'required|string|max:255',
            'speed' => 'nullable|string|max:100',
            'duration' => 'nullable|integer|min:1',
            'duration_unit' => 'nullable|string|max:50',
            'price' => 'required|numeric|min:0',
            'value' => 'required|numeric|min:0',
            'description' => 'nullable|string|max:2000',
            'advance_enabled' => 'sometimes|boolean',
            'advance_max_per_customer' => 'nullable|integer|min:1',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $networkIds = $request->user()->networks()->pluck('id')->toArray();
        if (!in_array($request->network_id, $networkIds)) {
            return response()->json(['success' => false, 'message' => 'غير مصرح لك بهذه الشبكة'], 403);
        }

        if ($request->boolean('advance_enabled') && !$request->filled('advance_max_per_customer')) {
            return response()->json([
                'success' => false,
                'message' => 'يجب تحديد الحد الأقصى لعدد الكروت المسموح بها سلفني',
            ], 422);
        }

        $data = $request->only([
            'network_id', 'name', 'speed', 'duration', 'duration_unit', 'price', 'value', 'description',
        ]);
        if ($request->has('advance_enabled')) {
            $advanceEnabled = $request->boolean('advance_enabled');
            $data['advance_enabled'] = $advanceEnabled;
            $data['advance_status'] = $advanceEnabled ? 'approved' : 'none';
            if ($request->filled('advance_max_per_customer')) {
                $data['advance_max_per_customer'] = $request->integer('advance_max_per_customer');
                $data['advance_max_cards'] = $request->integer('advance_max_per_customer');
            }
        }

        $category = CardCategory::create($data);

        return response()->json([
            'success' => true,
            'message' => 'تم إضافة الفئة بنجاح',
            'data' => $this->categoryResource($category),
        ], 201);
    }

    public function updateCategory(Request $request, int $id): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();
        $category = CardCategory::whereIn('network_id', $networkIds)->findOrFail($id);

        $validator = Validator::make($request->all(), [
            'name' => 'sometimes|required|string|max:255',
            'speed' => 'nullable|string|max:100',
            'duration' => 'nullable|integer|min:1',
            'duration_unit' => 'nullable|string|max:50',
            'price' => 'sometimes|required|numeric|min:0',
            'value' => 'sometimes|required|numeric|min:0',
            'description' => 'nullable|string|max:2000',
            'is_active' => 'sometimes|boolean',
            'advance_enabled' => 'sometimes|boolean',
            'advance_max_per_customer' => 'nullable|integer|min:1',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $data = $request->only([
            'name', 'speed', 'duration', 'duration_unit', 'price', 'value', 'description', 'is_active',
        ]);
        if ($request->has('advance_enabled')) {
            $advanceEnabled = $request->boolean('advance_enabled');
            if ($request->filled('advance_max_per_customer')) {
                $data['advance_max_per_customer'] = $request->integer('advance_max_per_customer');
                $data['advance_max_cards'] = $request->integer('advance_max_per_customer');
            } elseif ($advanceEnabled && !$category->advance_max_per_customer) {
                return response()->json([
                    'success' => false,
                    'message' => 'يجب تحديد الحد الأقصى لعدد الكروت المسموح بها سلفني',
                ], 422);
            }
            $data['advance_enabled'] = $advanceEnabled;
            $data['advance_status'] = $advanceEnabled ? 'approved' : 'none';
        }

        $category->update($data);

        return response()->json([
            'success' => true,
            'message' => 'تم تحديث الفئة بنجاح',
            'data' => $this->categoryResource($category->fresh()),
        ]);
    }

    /**
     * Dedicated endpoint for toggling "سلفني" (advance/lending) on a category
     * and setting the per-customer card limit, without touching the rest of
     * the category's fields.
     */
    public function updateAdvanceSettings(Request $request, int $id): JsonResponse
    {
        $networkIds = $request->user()->networks()->pluck('id')->toArray();
        $category = CardCategory::whereIn('network_id', $networkIds)->findOrFail($id);

        $validator = Validator::make($request->all(), [
            'advance_enabled' => 'required|boolean',
            'advance_max_per_customer' => 'nullable|integer|min:1',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        $advanceEnabled = $request->boolean('advance_enabled');
        $data = ['advance_enabled' => $advanceEnabled];

        if ($request->filled('advance_max_per_customer')) {
            $data['advance_max_per_customer'] = $request->integer('advance_max_per_customer');
            $data['advance_max_cards'] = $request->integer('advance_max_per_customer');
        } elseif ($advanceEnabled && !$category->advance_max_per_customer) {
            return response()->json([
                'success' => false,
                'message' => 'يجب تحديد الحد الأقصى لعدد الكروت المسموح بها سلفني',
            ], 422);
        }

        $data['advance_status'] = $advanceEnabled ? 'approved' : 'none';

        $category->update($data);

        return response()->json([
            'success' => true,
            'message' => $advanceEnabled ? 'تم تفعيل سلفني للفئة' : 'تم إيقاف سلفني للفئة',
            'data' => $this->categoryResource($category->fresh()),
        ]);
    }

    public function upload(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'network_id' => 'required|exists:networks,id',
            'category_id' => 'required|exists:card_categories,id',
            'codes' => 'nullable|array|min:1',
            'codes.*' => 'nullable|string|max:255',
            'cards_file' => 'nullable|file|mimes:csv,xls,xlsx,xml,txt|max:10240',
        ]);

        if ($validator->fails()) {
            return response()->json(['success' => false, 'errors' => $validator->errors()], 422);
        }

        if (! $request->hasFile('cards_file') && ! $request->filled('codes')) {
            return response()->json([
                'success' => false,
                'message' => 'يرجى إدخال أكواد الكروت أو رفع ملف',
                'errors' => ['codes' => ['يرجى إدخال أكواد الكروت أو رفع ملف']],
            ], 422);
        }

        $networkIds = $request->user()->networks()->pluck('id')->toArray();
        if (!in_array($request->network_id, $networkIds)) {
            return response()->json(['success' => false, 'message' => 'غير مصرح لك بهذه الشبكة'], 403);
        }

        $category = CardCategory::where('network_id', $request->network_id)->findOrFail($request->category_id);

        $codes = [];

        if ($request->hasFile('cards_file')) {
            $codes = $this->extractCodesFromFile($request->file('cards_file'));
        }

        if ($request->filled('codes')) {
            $codes = array_merge($codes, $request->input('codes', []));
        }

        $codes = array_map('trim', $codes);
        $codes = array_unique(array_filter($codes));

        if (empty($codes)) {
            return response()->json([
                'success' => false,
                'message' => 'لم يتم العثور على أكواد كروت صالحة في الملف أو الحقل',
            ], 422);
        }

        $now = now();
        $cards = array_map(fn($code) => [
            'network_id' => $request->network_id,
            'category_id' => $category->id,
            'card_number' => $code,
            'code' => $code,
            'serial' => $code,
            'status' => 'available',
            'created_at' => $now,
            'updated_at' => $now,
        ], $codes);

        $inserted = 0;
        foreach (array_chunk($cards, 500) as $chunk) {
            $inserted += Card::query()->insertOrIgnore($chunk);
        }

        $duplicates = count($codes) - $inserted;

        return response()->json([
            'success' => true,
            'message' => $duplicates > 0
                ? "تم رفع {$inserted} كرت وتخطي {$duplicates} كرت مكرر"
                : "تم رفع {$inserted} كرت بنجاح",
            'uploaded_count' => $inserted,
            'skipped_count' => $duplicates,
        ]);
    }

    private function extractCodesFromFile(UploadedFile $file): array
    {
        $extension = strtolower($file->getClientOriginalExtension());

        if ($extension === 'xml') {
            return $this->parseXmlFile($file);
        }

        return $this->parseExcelFile($file);
    }

    private function parseExcelFile(UploadedFile $file): array
    {
        $sheets = Excel::toArray(new class implements ToArray {
            public function array(array $row): array
            {
                return $row;
            }
        }, $file);

        $codes = [];
        $headerMap = null;

        foreach ($sheets as $rows) {
            if (!is_array($rows)) {
                continue;
            }

            foreach ($rows as $rowIndex => $row) {
                if (!is_array($row)) {
                    continue;
                }

                $values = [];
                foreach ($row as $index => $value) {
                    if ($value !== null && $value !== '') {
                        $values[$index] = trim((string) $value);
                    }
                }

                if (empty($values)) {
                    continue;
                }

                if ($rowIndex === 0) {
                    $headerMap = $this->detectHeaderColumns($row);
                    if ($headerMap !== null) {
                        continue;
                    }
                }

                if ($headerMap !== null) {
                    $preferredKey = $headerMap['username'] ?? $headerMap['code'] ?? $headerMap['password'] ?? array_key_first($values);
                    $code = $values[$preferredKey] ?? '';
                } else {
                    $code = reset($values);
                }

                if ($this->isValidCode($code)) {
                    $codes[] = $code;
                }
            }
        }

        return $codes;
    }

    private function detectHeaderColumns(array $row): ?array
    {
        $headers = [];
        foreach ($row as $index => $value) {
            $headers[$index] = strtolower(trim((string) ($value ?? '')));
        }

        $map = [];
        $keywords = [
            'username' => ['username', 'user name', 'user', 'uname', 'name', 'اسم المستخدم', 'المستخدم'],
            'code' => ['code', 'serial', 'number', 'card number', 'كود', 'رمز', 'رقم الكرت', 'الرقم التسلسلي'],
            'password' => ['password', 'pass', 'secret', 'كلمة المرور', 'الباسورد', 'الرقم السري'],
        ];

        foreach ($keywords as $key => $words) {
            foreach ($headers as $index => $header) {
                if (mb_strlen($header) > 40) {
                    continue;
                }
                foreach ($words as $word) {
                    if ($header === $word || str_contains($header, $word)) {
                        $map[$key] = $index;
                        break 2;
                    }
                }
            }
        }

        return empty($map) ? null : $map;
    }

    private function parseXmlFile(UploadedFile $file): array
    {
        $realPath = $file->getRealPath();
        $xml = @simplexml_load_file($realPath);

        if ($xml === false) {
            return [];
        }

        $codes = [];
        $this->extractCodesFromXmlNode($xml, $codes);

        return array_values(array_unique(array_filter($codes)));
    }

    private function extractCodesFromXmlNode(SimpleXMLElement $node, array &$codes): void
    {
        $codeLikeNames = ['username', 'user', 'name', 'code', 'card', 'serial'];

        foreach ($node->attributes() ?? [] as $attrName => $attrValue) {
            $name = strtolower((string) $attrName);
            if (in_array($name, $codeLikeNames, true)) {
                $value = trim((string) $attrValue);
                if ($this->isValidCode($value)) {
                    $codes[] = $value;
                }
            }
        }

        foreach ($node->children() as $child) {
            $name = strtolower($child->getName());
            if (in_array($name, $codeLikeNames, true)) {
                $value = trim((string) $child);
                if ($this->isValidCode($value)) {
                    $codes[] = $value;
                }
            }
            $this->extractCodesFromXmlNode($child, $codes);
        }
    }

    private function isValidCode($value): bool
    {
        if ($value === null) {
            return false;
        }

        $str = trim((string) $value);

        if ($str === '' || mb_strlen($str) < 3 || mb_strlen($str) > 255) {
            return false;
        }

        return true;
    }

    private function categoryResource(CardCategory $category): array
    {
        return [
            'id' => $category->id,
            'network_id' => $category->network_id,
            'name' => $category->name,
            'speed' => $category->speed,
            'duration' => $category->duration,
            'duration_unit' => $category->duration_unit,
            'price' => (float) $category->price,
            'value' => (float) $category->value,
            'description' => $category->description,
            'is_active' => (bool) $category->is_active,
            'advance_enabled' => (bool) $category->advance_enabled,
            'advance_max_per_customer' => $category->advance_max_per_customer,
        ];
    }
}
