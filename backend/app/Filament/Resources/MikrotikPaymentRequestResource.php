<?php

namespace App\Filament\Resources;

use App\Filament\Resources\MikrotikPaymentRequestResource\Pages;
use App\Models\MikrotikPaymentRequest;
use App\Models\MikrotikSubscription;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Components\Grid;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;
use Illuminate\Support\Facades\DB;

class MikrotikPaymentRequestResource extends Resource
{
    protected static ?string $model = MikrotikPaymentRequest::class;
    protected static ?int $navigationSort = 14;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-banknotes'; }
    public static function getNavigationLabel(): string { return 'مدفوعات MikroTik'; }
    public static function getNavigationGroup(): ?string { return 'الشبكات'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Grid::make(2)->schema([
                Forms\Components\TextInput::make('user.name')
                    ->label('المالك')->disabled()->dehydrated(false),
                Forms\Components\TextInput::make('plan.name')
                    ->label('الخطة')->disabled()->dehydrated(false),
            ]),
            Grid::make(3)->schema([
                Forms\Components\TextInput::make('sender_name')
                    ->label('اسم المرسل')->required(),
                Forms\Components\TextInput::make('amount')
                    ->label('المبلغ')->numeric()->disabled(),
                Forms\Components\TextInput::make('transfer_receipt_number')
                    ->label('رقم السند/الحوالة'),
            ]),
            Forms\Components\FileUpload::make('receipt_image')
                ->label('صورة الإيصال')
                ->disk('public')
                ->image()
                ->openable()
                ->disabled()
                ->dehydrated(false),
            Forms\Components\Textarea::make('admin_note')
                ->label('ملاحظة الإدارة')
                ->helperText('تظهر للمالك عند الرفض'),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('user.name')->label('المالك')->searchable()->sortable(),
                Tables\Columns\TextColumn::make('plan.name')->label('الخطة')->sortable(),
                Tables\Columns\TextColumn::make('amount')->label('المبلغ')->money('YER')->sortable(),
                Tables\Columns\TextColumn::make('sender_name')->label('اسم المرسل')->searchable(),
                Tables\Columns\TextColumn::make('bankAccount.bank_name')->label('الحساب المصرفي')->placeholder('—'),
                Tables\Columns\TextColumn::make('transfer_receipt_number')->label('رقم السند')->placeholder('—'),
                Tables\Columns\TextColumn::make('status')->label('الحالة')
                    ->badge()
                    ->formatStateUsing(fn ($state) => match ($state) {
                        'pending' => 'قيد المراجعة',
                        'approved' => 'مقبول',
                        'rejected' => 'مرفوض',
                        default => $state,
                    })
                    ->color(fn ($state) => match ($state) {
                        'pending' => 'warning',
                        'approved' => 'success',
                        'rejected' => 'danger',
                        default => 'gray',
                    }),
                Tables\Columns\TextColumn::make('created_at')->label('التاريخ')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('status')
                    ->label('الحالة')
                    ->options([
                        'pending' => 'قيد المراجعة',
                        'approved' => 'مقبول',
                        'rejected' => 'مرفوض',
                    ]),
            ])
            ->actions([
                \Filament\Actions\Action::make('approve')
                    ->label('موافقة')
                    ->icon('heroicon-o-check')
                    ->color('success')
                    ->visible(fn (MikrotikPaymentRequest $record) => $record->status === 'pending')
                    ->requiresConfirmation()
                    ->modalHeading('تفعيل الاشتراك')
                    ->modalDescription('سيتم إنشاء اشتراك نشط بهذه الخطة للمالك')
                    ->action(function (MikrotikPaymentRequest $record) {
                        DB::transaction(function () use ($record) {
                            $record->update([
                                'status' => 'approved',
                                'reviewed_by' => auth()->id(),
                                'reviewed_at' => now(),
                            ]);
                            MikrotikSubscription::where('user_id', $record->user_id)
                                ->whereIn('status', ['trial', 'active'])
                                ->update(['status' => 'expired']);
                            MikrotikSubscription::create([
                                'user_id' => $record->user_id,
                                'plan_id' => $record->plan_id,
                                'status' => 'active',
                                'starts_at' => now(),
                                'ends_at' => now()->addDays($record->plan->duration_days),
                                'payment_request_id' => $record->id,
                            ]);
                        });
                        self::notifyOwner($record, true);
                    }),
                \Filament\Actions\Action::make('reject')
                    ->label('رفض')
                    ->icon('heroicon-o-x-mark')
                    ->color('danger')
                    ->visible(fn (MikrotikPaymentRequest $record) => $record->status === 'pending')
                    ->form([
                        \Filament\Forms\Components\Textarea::make('note')
                            ->label('سبب الرفض')
                            ->required(),
                    ])
                    ->action(function (MikrotikPaymentRequest $record, array $data) {
                        $record->update([
                            'status' => 'rejected',
                            'admin_note' => $data['note'],
                            'reviewed_by' => auth()->id(),
                            'reviewed_at' => now(),
                        ]);
                        self::notifyOwner($record, false);
                    }),
                \Filament\Actions\EditAction::make()->label('عرض'),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([25, 50]);
    }

    /** Push the review outcome to the owner — same service the API
     * uses to alert admins about new payment requests. */
    private static function notifyOwner(
        MikrotikPaymentRequest $record, bool $approved): void
    {
        try {
            $plan = $record->plan?->name ?? '';
            app(\App\Services\NotificationService::class)->send(
                $record->user,
                $approved ? 'تم تفعيل اشتراك MikroTik' : 'طلب دفع مرفوض',
                $approved
                    ? "تمت الموافقة على دفعتك — اشتراكك في «{$plan}» نشط الآن."
                    : "رُفض طلب الدفع لخطة «{$plan}». السبب: {$record->admin_note}",
                ['type' => 'mikrotik_payment_review',
                 'request_id' => $record->id,
                 'status' => $approved ? 'approved' : 'rejected']
            );
        } catch (\Throwable $e) {
            \Log::warning('MikroTik review notification failed: ' . $e->getMessage());
        }
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListMikrotikPaymentRequests::route('/'),
            'edit' => Pages\EditMikrotikPaymentRequest::route('/{record}/edit'),
        ];
    }
}
