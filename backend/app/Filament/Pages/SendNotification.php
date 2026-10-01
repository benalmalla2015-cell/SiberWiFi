<?php

namespace App\Filament\Pages;

use App\Models\SentNotification;
use App\Models\User;
use App\Services\NotificationService;
use Filament\Actions\Action;
use Filament\Forms\Components\FileUpload;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Concerns\InteractsWithForms;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Schema;

class SendNotification extends Page
{
    use InteractsWithForms;

    protected static string|\BackedEnum|null $navigationIcon = 'heroicon-o-paper-airplane';
    protected static ?string $navigationLabel = 'إرسال إشعار';
    protected static string|\UnitEnum|null $navigationGroup = 'الإشعارات';
    protected static ?int $navigationSort = 100;
    protected static bool $shouldRegisterNavigation = false;
    protected string $view = 'filament.pages.send-notification';

    public ?array $data = [];

    public function mount(): void
    {
        $this->form->fill();
    }

    public function form(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('title')
                    ->label('عنوان الإشعار')
                    ->required()
                    ->maxLength(255),

                Textarea::make('body')
                    ->label('نص الإشعار')
                    ->required()
                    ->rows(4),

                FileUpload::make('image')
                    ->label('صورة الإشعار (اختياري)')
                    ->image()
                    ->disk('public')
                    ->directory('notification_images')
                    ->nullable(),

                Select::make('target')
                    ->label('تطبيق المستهدفين')
                    ->options([
                        'customer_app' => 'تطبيق العملاء',
                        'network_owner_app' => 'تطبيق أصحاب الشبكات',
                        'all' => 'الكل',
                    ])
                    ->required()
                    ->default('customer_app'),
            ])
            ->statePath('data');
    }

    public function send(): void
    {
        $data = $this->form->getState();
        $title = $data['title'];
        $body = $data['body'];
        $target = $data['target'];
        $image = $data['image'] ?? null;
        $imageUrl = $image ? asset('storage/' . $image) : null;

        $query = User::query()
            ->where('is_active', true)
            ->whereHas('fcmTokens', fn ($query) => $query->where('is_active', true));

        if ($target === 'customer_app') {
            $query->where('type', 'client');
        } elseif ($target === 'network_owner_app') {
            $query->where('type', 'network_owner');
        }

        $sentNotification = SentNotification::create([
            'title' => $title,
            'body' => $body,
            'image' => $image,
            'target' => $target,
            'recipients_count' => 0,
            'sent_by' => auth()->id(),
        ]);

        $count = 0;
        $service = app(NotificationService::class);

        foreach ($query->cursor() as $user) {
            try {
                $service->send($user, $title, $body, [
                    'type' => 'general',
                    'target' => $target,
                    'title' => $title,
                    'body' => $body,
                    'image' => $imageUrl,
                ], $imageUrl);
            } catch (\Throwable $e) {
                report($e);
            }

            $count++;
        }

        $sentNotification->update(['recipients_count' => $count]);

        $this->form->fill();

        Notification::make()
            ->title("تم إرسال الإشعار إلى {$count} مستخدم")
            ->success()
            ->send();
    }

    protected function getFormActions(): array
    {
        return [
            Action::make('send')
                ->label('إرسال الإشعار')
                ->action('send'),
        ];
    }
}
