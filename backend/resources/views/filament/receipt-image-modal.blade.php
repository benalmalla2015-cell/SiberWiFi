<div style="text-align: center; padding: 1rem;">
    @if($record->receipt_image)
        <img 
            src="{{ asset('storage/' . $record->receipt_image) }}" 
            alt="صورة السند" 
            style="max-width: 100%; max-height: 70vh; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);"
        />
        <div style="margin-top: 1rem;">
            <a 
                href="{{ asset('storage/' . $record->receipt_image) }}" 
                target="_blank" 
                style="color: #1E2D7D; text-decoration: underline; font-weight: bold;"
            >
                فتح في نافذة جديدة
            </a>
        </div>
    @else
        <p style="color: #999;">لا توجد صورة سند مرفقة</p>
    @endif
</div>
