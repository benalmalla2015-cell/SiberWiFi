<?php

namespace App\Filament\Resources;

use App\Filament\Resources\ReportResource\Pages;
use App\Models\Report;
use App\Services\NotificationService;
use Filament\Forms;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables;
use Filament\Tables\Table;

class ReportResource extends Resource
{
    protected static ?string $model = Report::class;
    protected static ?int $navigationSort = 1;

    public static function getNavigationIcon(): ?string { return 'heroicon-o-exclamation-triangle'; }
    public static function getNavigationLabel(): string { return 'البلاغات'; }
    public static function getNavigationGroup(): ?string { return 'الدعم'; }

    public static function form(Schema $schema): Schema
    {
        return $schema->components([
            Forms\Components\TextInput::make('user.name')->label('العميل')->disabled(),
            Forms\Components\TextInput::make('network.name')->label('الشبكة')->disabled(),
            Forms\Components\TextInput::make('type')->label('نوع البلاغ')->disabled(),
            Forms\Components\TextInput::make('subject')->label('الموضوع')->disabled(),
            Forms\Components\Textarea::make('message')->label('الرسالة')->disabled()->rows(4),
            Forms\Components\Select::make('status')
                ->label('الحالة')
                ->options([
                    'open' => 'مفتوح',
                    'in_progress' => 'قيد المعالجة',
                    'resolved' => 'تم الحل',
                    'closed' => 'مغلق',
                ])
                ->required(),
            Forms\Components\Textarea::make('admin_reply')->label('رد الإدارة / صاحب الشبكة')->rows(3),
        ]);
    }

    public static function table(Table $table): Table
    {
        return $table
            ->columns([
                Tables\Columns\TextColumn::make('id')->label('#'),
                Tables\Columns\TextColumn::make('user.name')->label('العميل')->searchable(),
                Tables\Columns\TextColumn::make('network.name')->label('الشبكة')->searchable(),
                Tables\Columns\TextColumn::make('type')->label('النوع'),
                Tables\Columns\TextColumn::make('subject')->label('الموضوع'),
                Tables\Columns\BadgeColumn::make('status')
                    ->label('الحالة')
                    ->colors([
                        'warning' => 'open',
                        'primary' => 'in_progress',
                        'success' => 'resolved',
                        'danger' => 'closed',
                    ])
                    ->formatStateUsing(fn($s) => match($s) {
                        'open' => 'مفتوح',
                        'in_progress' => 'قيد المعالجة',
                        'resolved' => 'تم الحل',
                        'closed' => 'مغلق',
                        default => $s,
                    }),
                Tables\Columns\TextColumn::make('created_at')->label('تاريخ البلاغ')->dateTime()->sortable(),
            ])
            ->filters([
                Tables\Filters\SelectFilter::make('status')->label('الحالة')->options([
                    'open' => 'مفتوح',
                    'in_progress' => 'قيد المعالجة',
                    'resolved' => 'تم الحل',
                    'closed' => 'مغلق',
                ]),
                Tables\Filters\SelectFilter::make('network_id')->label('الشبكة')->relationship('network', 'name'),
            ])
            ->actions([
                \Filament\Actions\EditAction::make()->label('معالجة'),
                \Filament\Actions\Action::make('replyNotify')
                    ->label('رد وإرسال إشعار')
                    ->icon('heroicon-o-chat-bubble-left-ellipsis')
                    ->requiresConfirmation()
                    ->modalHeading('إرسال رد')
                    ->modalDescription('سيتم إرسال الرد كإشعار للعميل.')
                    ->form([
                        Forms\Components\Textarea::make('reply')->label('الرد')->required()->rows(3),
                    ])
                    ->action(function (Report $record, array $data) {
                        $record->update([
                            'admin_reply' => $data['reply'],
                            'status' => 'resolved',
                            'replied_at' => now(),
                            'replied_by' => auth()->id(),
                        ]);
                        try {
                            app(NotificationService::class)->send(
                                $record->user,
                                'رد على بلاغك',
                                'تم الرد على بلاغك بخصوص شبكة ' . $record->network?->name . ': ' . $data['reply'],
                                ['type' => 'report_reply', 'report_id' => $record->id]
                            );
                        } catch (\Throwable $e) {
                            \Log::warning('Report reply notification failed: ' . $e->getMessage());
                        }
                    })
                    ->visible(fn(?Report $record) => in_array($record?->status, ['open', 'in_progress'])), 
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([25, 50, 100]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListReports::route('/'),
            'edit' => Pages\EditReport::route('/{record}/edit'),
        ];
    }
}
