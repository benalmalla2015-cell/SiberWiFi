<?php

namespace App\Http\Controllers\Api\Cyber\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class CyberRegisterRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'full_name' => [
                'required', 'string', 'max:255',
                function (string $attribute, mixed $value, \Closure $fail): void {
                    $parts = array_filter(preg_split('/\s+/u', trim((string) $value)) ?: []);
                    if (count($parts) < (int) config('cyber.min_name_parts', 4)) {
                        $fail('الاسم الكامل يجب أن يكون رباعياً على الأقل — أدخل الاسم كاملاً (الاسم، الأب، الجد، اللقب).');
                    }
                },
            ],
            'document_type' => ['required', Rule::in(config('cyber.id_types', ['national_id', 'passport']))],
            'id_front_image' => ['required', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
            'id_back_image' => ['required_if:document_type,national_id', 'nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
            'directorate_id' => ['required', 'integer', 'exists:directorates,id'],
            'sub_directorate_id' => ['required', 'integer', 'exists:sub_directorates,id'],
            'device_id' => ['nullable', 'string', 'max:255'],
        ];
    }

    /**
     * المديرية المختارة يجب أن تتبع المحافظة المحددة.
     */
    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            if (! $this->filled(['directorate_id', 'sub_directorate_id'])) {
                return;
            }
            $belongs = \App\Models\SubDirectorate::whereKey($this->integer('sub_directorate_id'))
                ->where('directorate_id', $this->integer('directorate_id'))
                ->exists();
            if (! $belongs) {
                $validator->errors()->add('sub_directorate_id', 'المديرية المختارة لا تتبع المحافظة المحددة');
            }
        });
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'full_name.required' => 'الاسم الكامل مطلوب',
            'document_type.required' => 'نوع الوثيقة مطلوب',
            'document_type.in' => 'نوع الوثيقة يجب أن يكون بطاقة شخصية أو جواز سفر',
            'id_front_image.required' => 'صورة الوثيقة مطلوبة',
            'id_front_image.image' => 'صورة الوثيقة يجب أن تكون ملف صورة صالح',
            'id_front_image.max' => 'حجم صورة الوثيقة يجب ألا يتجاوز 5 ميجابايت',
            'id_back_image.required_if' => 'صورة الوجه الخلفي للبطاقة مطلوبة',
            'id_back_image.image' => 'صورة الوجه الخلفي يجب أن تكون ملف صورة صالح',
            'id_back_image.max' => 'حجم صورة الوجه الخلفي يجب ألا يتجاوز 5 ميجابايت',
            'directorate_id.required' => 'المحافظة مطلوبة',
            'directorate_id.exists' => 'المحافظة المختارة غير صحيحة',
            'sub_directorate_id.required' => 'المديرية مطلوبة',
            'sub_directorate_id.exists' => 'المديرية المختارة غير صحيحة',
        ];
    }
}
