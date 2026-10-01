<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // users
        Schema::table('users', function (Blueprint $table) {
            if (!Schema::hasColumn('users', 'phone')) {
                $table->string('phone')->nullable()->unique()->after('email');
            }
            if (!Schema::hasColumn('users', 'type')) {
                $table->string('type')->default('client')->after('phone');
            }
            if (!Schema::hasColumn('users', 'region_type')) {
                $table->string('region_type')->nullable()->after('type');
            }
            if (!Schema::hasColumn('users', 'account_number')) {
                $table->string('account_number')->nullable()->unique()->after('region_type');
            }
            if (!Schema::hasColumn('users', 'referral_code')) {
                $table->string('referral_code')->nullable()->unique()->after('account_number');
            }
            if (!Schema::hasColumn('users', 'referred_by')) {
                $table->foreignId('referred_by')->nullable()->constrained('users')->nullOnDelete()->after('referral_code');
            }
            if (!Schema::hasColumn('users', 'balance')) {
                $table->decimal('balance', 12, 2)->default(0)->after('referred_by');
            }
            if (!Schema::hasColumn('users', 'available_balance')) {
                $table->decimal('available_balance', 12, 2)->default(0)->after('balance');
            }
            if (!Schema::hasColumn('users', 'frozen_balance')) {
                $table->decimal('frozen_balance', 12, 2)->default(0)->after('available_balance');
            }
            if (!Schema::hasColumn('users', 'currency')) {
                $table->string('currency')->default('YER')->after('frozen_balance');
            }
            if (!Schema::hasColumn('users', 'is_active')) {
                $table->boolean('is_active')->default(true)->after('currency');
            }
            if (!Schema::hasColumn('users', 'is_verified')) {
                $table->boolean('is_verified')->default(false)->after('is_active');
            }
            if (!Schema::hasColumn('users', 'avatar')) {
                $table->string('avatar')->nullable()->after('is_verified');
            }
        });

        // network_owners
        Schema::table('network_owners', function (Blueprint $table) {
            if (!Schema::hasColumn('network_owners', 'user_id')) {
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('network_owners', 'business_name')) {
                $table->string('business_name')->nullable();
            }
            if (!Schema::hasColumn('network_owners', 'national_id')) {
                $table->string('national_id')->nullable();
            }
            if (!Schema::hasColumn('network_owners', 'bank_name')) {
                $table->string('bank_name')->nullable();
            }
            if (!Schema::hasColumn('network_owners', 'bank_account')) {
                $table->string('bank_account')->nullable();
            }
            if (!Schema::hasColumn('network_owners', 'notes')) {
                $table->text('notes')->nullable();
            }
            if (!Schema::hasColumn('network_owners', 'is_approved')) {
                $table->boolean('is_approved')->default(false);
            }
            if (!Schema::hasColumn('network_owners', 'approved_at')) {
                $table->timestamp('approved_at')->nullable();
            }
            if (!Schema::hasColumn('network_owners', 'approved_by')) {
                $table->foreignId('approved_by')->nullable()->constrained('users')->nullOnDelete();
            }
        });

        // networks
        Schema::table('networks', function (Blueprint $table) {
            if (!Schema::hasColumn('networks', 'user_id')) {
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('networks', 'region_id')) {
                $table->foreignId('region_id')->nullable()->constrained('regions')->nullOnDelete();
            }
            if (!Schema::hasColumn('networks', 'directorate_id')) {
                $table->foreignId('directorate_id')->nullable()->constrained('directorates')->nullOnDelete();
            }
            if (!Schema::hasColumn('networks', 'name')) {
                $table->string('name');
            }
            if (!Schema::hasColumn('networks', 'slug')) {
                $table->string('slug')->nullable()->unique();
            }
            if (!Schema::hasColumn('networks', 'logo')) {
                $table->string('logo')->nullable();
            }
            if (!Schema::hasColumn('networks', 'cover_image')) {
                $table->string('cover_image')->nullable();
            }
            if (!Schema::hasColumn('networks', 'background_image')) {
                $table->string('background_image')->nullable();
            }
            if (!Schema::hasColumn('networks', 'url')) {
                $table->string('url')->nullable();
            }
            if (!Schema::hasColumn('networks', 'description')) {
                $table->text('description')->nullable();
            }
            if (!Schema::hasColumn('networks', 'phone')) {
                $table->string('phone')->nullable();
            }
            if (!Schema::hasColumn('networks', 'commission_rate')) {
                $table->decimal('commission_rate', 5, 2)->default(5);
            }
            if (!Schema::hasColumn('networks', 'supports_credit')) {
                $table->boolean('supports_credit')->default(false);
            }
            if (!Schema::hasColumn('networks', 'average_rating')) {
                $table->decimal('average_rating', 3, 2)->default(0);
            }
            if (!Schema::hasColumn('networks', 'ratings_count')) {
                $table->unsignedInteger('ratings_count')->default(0);
            }
            if (!Schema::hasColumn('networks', 'sales_count')) {
                $table->unsignedInteger('sales_count')->default(0);
            }
            if (!Schema::hasColumn('networks', 'views_count')) {
                $table->unsignedInteger('views_count')->default(0);
            }
            if (!Schema::hasColumn('networks', 'status')) {
                $table->string('status')->default('pending');
            }
            if (!Schema::hasColumn('networks', 'rejection_reason')) {
                $table->text('rejection_reason')->nullable();
            }
            if (!Schema::hasColumn('networks', 'is_featured')) {
                $table->boolean('is_featured')->default(false);
            }
            if (!Schema::hasColumn('networks', 'approved_at')) {
                $table->timestamp('approved_at')->nullable();
            }
            if (!Schema::hasColumn('networks', 'approved_by')) {
                $table->foreignId('approved_by')->nullable()->constrained('users')->nullOnDelete();
            }
            if (!Schema::hasColumn('networks', 'deleted_at')) {
                $table->softDeletes();
            }
        });

        // card_categories
        Schema::table('card_categories', function (Blueprint $table) {
            if (!Schema::hasColumn('card_categories', 'network_id')) {
                $table->foreignId('network_id')->constrained('networks')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('card_categories', 'name')) {
                $table->string('name');
            }
            if (!Schema::hasColumn('card_categories', 'speed')) {
                $table->string('speed')->nullable();
            }
            if (!Schema::hasColumn('card_categories', 'duration')) {
                $table->unsignedInteger('duration')->nullable();
            }
            if (!Schema::hasColumn('card_categories', 'duration_unit')) {
                $table->string('duration_unit')->nullable();
            }
            if (!Schema::hasColumn('card_categories', 'price')) {
                $table->decimal('price', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('card_categories', 'value')) {
                $table->decimal('value', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('card_categories', 'description')) {
                $table->text('description')->nullable();
            }
            if (!Schema::hasColumn('card_categories', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
        });

        // cards
        Schema::table('cards', function (Blueprint $table) {
            if (!Schema::hasColumn('cards', 'network_id')) {
                $table->foreignId('network_id')->constrained('networks')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('cards', 'category_id')) {
                $table->foreignId('category_id')->nullable()->constrained('card_categories')->nullOnDelete();
            }
            if (!Schema::hasColumn('cards', 'serial')) {
                $table->string('serial')->nullable();
            }
            if (!Schema::hasColumn('cards', 'code')) {
                $table->string('code');
            }
            if (!Schema::hasColumn('cards', 'status')) {
                $table->string('status')->default('available');
            }
            if (!Schema::hasColumn('cards', 'sold_to')) {
                $table->foreignId('sold_to')->nullable()->constrained('users')->nullOnDelete();
            }
            if (!Schema::hasColumn('cards', 'sold_at')) {
                $table->timestamp('sold_at')->nullable();
            }
            if (!Schema::hasColumn('cards', 'transaction_id')) {
                $table->foreignId('transaction_id')->nullable()->constrained('transactions')->nullOnDelete();
            }
        });

        // transactions
        Schema::table('transactions', function (Blueprint $table) {
            if (!Schema::hasColumn('transactions', 'transaction_number')) {
                $table->string('transaction_number')->nullable()->unique();
            }
            if (!Schema::hasColumn('transactions', 'user_id')) {
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('transactions', 'network_id')) {
                $table->foreignId('network_id')->constrained('networks')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('transactions', 'card_id')) {
                $table->foreignId('card_id')->nullable()->constrained('cards')->nullOnDelete();
            }
            if (!Schema::hasColumn('transactions', 'category_id')) {
                $table->foreignId('category_id')->nullable()->constrained('card_categories')->nullOnDelete();
            }
            if (!Schema::hasColumn('transactions', 'quantity')) {
                $table->unsignedInteger('quantity')->default(1);
            }
            if (!Schema::hasColumn('transactions', 'total_amount')) {
                $table->decimal('total_amount', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('transactions', 'commission_amount')) {
                $table->decimal('commission_amount', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('transactions', 'network_owner_amount')) {
                $table->decimal('network_owner_amount', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('transactions', 'cashback_amount')) {
                $table->decimal('cashback_amount', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('transactions', 'status')) {
                $table->string('status')->default('completed');
            }
            if (!Schema::hasColumn('transactions', 'notes')) {
                $table->text('notes')->nullable();
            }
        });

        // wallet_logs
        Schema::table('wallet_logs', function (Blueprint $table) {
            if (!Schema::hasColumn('wallet_logs', 'user_id')) {
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('wallet_logs', 'type')) {
                $table->string('type');
            }
            if (!Schema::hasColumn('wallet_logs', 'amount')) {
                $table->decimal('amount', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('wallet_logs', 'balance_before')) {
                $table->decimal('balance_before', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('wallet_logs', 'balance_after')) {
                $table->decimal('balance_after', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('wallet_logs', 'description')) {
                $table->text('description')->nullable();
            }
            if (!Schema::hasColumn('wallet_logs', 'reference_type')) {
                $table->string('reference_type')->nullable();
            }
            if (!Schema::hasColumn('wallet_logs', 'reference_id')) {
                $table->unsignedBigInteger('reference_id')->nullable();
            }
        });

        // payout_requests
        Schema::table('payout_requests', function (Blueprint $table) {
            if (!Schema::hasColumn('payout_requests', 'request_number')) {
                $table->string('request_number')->nullable()->unique();
            }
            if (!Schema::hasColumn('payout_requests', 'user_id')) {
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('payout_requests', 'amount')) {
                $table->decimal('amount', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('payout_requests', 'paid_amount')) {
                $table->decimal('paid_amount', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('payout_requests', 'service_name')) {
                $table->string('service_name')->nullable();
            }
            if (!Schema::hasColumn('payout_requests', 'transaction_number')) {
                $table->string('transaction_number')->nullable();
            }
            if (!Schema::hasColumn('payout_requests', 'status')) {
                $table->string('status')->default('pending');
            }
            if (!Schema::hasColumn('payout_requests', 'paid_at')) {
                $table->timestamp('paid_at')->nullable();
            }
            if (!Schema::hasColumn('payout_requests', 'received_confirmed_at')) {
                $table->timestamp('received_confirmed_at')->nullable();
            }
            if (!Schema::hasColumn('payout_requests', 'admin_notes')) {
                $table->text('admin_notes')->nullable();
            }
        });

        // reports
        Schema::table('reports', function (Blueprint $table) {
            if (!Schema::hasColumn('reports', 'user_id')) {
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('reports', 'network_id')) {
                $table->foreignId('network_id')->constrained('networks')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('reports', 'type')) {
                $table->string('type')->nullable();
            }
            if (!Schema::hasColumn('reports', 'subject')) {
                $table->string('subject')->nullable();
            }
            if (!Schema::hasColumn('reports', 'message')) {
                $table->text('message');
            }
            if (!Schema::hasColumn('reports', 'status')) {
                $table->string('status')->default('open');
            }
            if (!Schema::hasColumn('reports', 'admin_reply')) {
                $table->text('admin_reply')->nullable();
            }
            if (!Schema::hasColumn('reports', 'replied_at')) {
                $table->timestamp('replied_at')->nullable();
            }
            if (!Schema::hasColumn('reports', 'replied_by')) {
                $table->foreignId('replied_by')->nullable()->constrained('users')->nullOnDelete();
            }
        });

        // network_ratings
        Schema::table('network_ratings', function (Blueprint $table) {
            if (!Schema::hasColumn('network_ratings', 'user_id')) {
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('network_ratings', 'network_id')) {
                $table->foreignId('network_id')->constrained('networks')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('network_ratings', 'rating')) {
                $table->decimal('rating', 3, 2)->default(0);
            }
            if (!Schema::hasColumn('network_ratings', 'review')) {
                $table->text('review')->nullable();
            }
        });

        // chat_messages
        Schema::table('chat_messages', function (Blueprint $table) {
            if (!Schema::hasColumn('chat_messages', 'network_id')) {
                $table->foreignId('network_id')->constrained('networks')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('chat_messages', 'sender_id')) {
                $table->foreignId('sender_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('chat_messages', 'receiver_id')) {
                $table->foreignId('receiver_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('chat_messages', 'message')) {
                $table->text('message');
            }
            if (!Schema::hasColumn('chat_messages', 'is_read')) {
                $table->boolean('is_read')->default(false);
            }
            if (!Schema::hasColumn('chat_messages', 'read_at')) {
                $table->timestamp('read_at')->nullable();
            }
        });

        // charging_points
        Schema::table('charging_points', function (Blueprint $table) {
            if (!Schema::hasColumn('charging_points', 'network_id')) {
                $table->foreignId('network_id')->constrained('networks')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('charging_points', 'name')) {
                $table->string('name');
            }
            if (!Schema::hasColumn('charging_points', 'phone')) {
                $table->string('phone')->nullable();
            }
            if (!Schema::hasColumn('charging_points', 'location')) {
                $table->string('location')->nullable();
            }
            if (!Schema::hasColumn('charging_points', 'latitude')) {
                $table->decimal('latitude', 10, 8)->nullable();
            }
            if (!Schema::hasColumn('charging_points', 'longitude')) {
                $table->decimal('longitude', 11, 8)->nullable();
            }
            if (!Schema::hasColumn('charging_points', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
        });

        // favorites
        Schema::table('favorites', function (Blueprint $table) {
            if (!Schema::hasColumn('favorites', 'user_id')) {
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('favorites', 'network_id')) {
                $table->foreignId('network_id')->constrained('networks')->cascadeOnDelete();
            }
        });

        // daily_offers
        Schema::table('daily_offers', function (Blueprint $table) {
            if (!Schema::hasColumn('daily_offers', 'network_id')) {
                $table->foreignId('network_id')->constrained('networks')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('daily_offers', 'title')) {
                $table->string('title');
            }
            if (!Schema::hasColumn('daily_offers', 'description')) {
                $table->text('description')->nullable();
            }
            if (!Schema::hasColumn('daily_offers', 'discount_percent')) {
                $table->decimal('discount_percent', 5, 2)->default(0);
            }
            if (!Schema::hasColumn('daily_offers', 'starts_at')) {
                $table->timestamp('starts_at')->nullable();
            }
            if (!Schema::hasColumn('daily_offers', 'ends_at')) {
                $table->timestamp('ends_at')->nullable();
            }
            if (!Schema::hasColumn('daily_offers', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
        });

        // advertisements
        Schema::table('advertisements', function (Blueprint $table) {
            if (!Schema::hasColumn('advertisements', 'title')) {
                $table->string('title');
            }
            if (!Schema::hasColumn('advertisements', 'image')) {
                $table->string('image')->nullable();
            }
            if (!Schema::hasColumn('advertisements', 'url')) {
                $table->string('url')->nullable();
            }
            if (!Schema::hasColumn('advertisements', 'position')) {
                $table->string('position')->nullable();
            }
            if (!Schema::hasColumn('advertisements', 'sort_order')) {
                $table->integer('sort_order')->default(0);
            }
            if (!Schema::hasColumn('advertisements', 'starts_at')) {
                $table->timestamp('starts_at')->nullable();
            }
            if (!Schema::hasColumn('advertisements', 'ends_at')) {
                $table->timestamp('ends_at')->nullable();
            }
            if (!Schema::hasColumn('advertisements', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
        });

        // cashback_settings
        Schema::table('cashback_settings', function (Blueprint $table) {
            if (!Schema::hasColumn('cashback_settings', 'min_amount')) {
                $table->decimal('min_amount', 12, 2)->default(0);
            }
            if (!Schema::hasColumn('cashback_settings', 'cashback_percent')) {
                $table->decimal('cashback_percent', 5, 2)->default(0);
            }
            if (!Schema::hasColumn('cashback_settings', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
        });

        // commission_settings
        Schema::table('commission_settings', function (Blueprint $table) {
            if (!Schema::hasColumn('commission_settings', 'commission_percent')) {
                $table->decimal('commission_percent', 5, 2)->default(5);
            }
            if (!Schema::hasColumn('commission_settings', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
        });

        // app_settings
        Schema::table('app_settings', function (Blueprint $table) {
            if (!Schema::hasColumn('app_settings', 'key')) {
                $table->string('key')->unique();
            }
            if (!Schema::hasColumn('app_settings', 'value')) {
                $table->text('value')->nullable();
            }
            if (!Schema::hasColumn('app_settings', 'type')) {
                $table->string('type')->default('string');
            }
            if (!Schema::hasColumn('app_settings', 'group')) {
                $table->string('group')->nullable();
            }
        });

        // fcm_tokens
        Schema::table('fcm_tokens', function (Blueprint $table) {
            if (!Schema::hasColumn('fcm_tokens', 'user_id')) {
                $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('fcm_tokens', 'token')) {
                $table->text('token');
            }
            if (!Schema::hasColumn('fcm_tokens', 'device_model')) {
                $table->string('device_model')->nullable();
            }
            if (!Schema::hasColumn('fcm_tokens', 'app_version')) {
                $table->string('app_version')->nullable();
            }
            if (!Schema::hasColumn('fcm_tokens', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
            if (!Schema::hasColumn('fcm_tokens', 'last_used_at')) {
                $table->timestamp('last_used_at')->nullable();
            }
        });

        // regions
        Schema::table('regions', function (Blueprint $table) {
            if (!Schema::hasColumn('regions', 'name')) {
                $table->string('name');
            }
            if (!Schema::hasColumn('regions', 'type')) {
                $table->string('type')->nullable();
            }
            if (!Schema::hasColumn('regions', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
        });

        // directorates
        Schema::table('directorates', function (Blueprint $table) {
            if (!Schema::hasColumn('directorates', 'region_id')) {
                $table->foreignId('region_id')->constrained('regions')->cascadeOnDelete();
            }
            if (!Schema::hasColumn('directorates', 'name')) {
                $table->string('name');
            }
            if (!Schema::hasColumn('directorates', 'name_en')) {
                $table->string('name_en')->nullable();
            }
            if (!Schema::hasColumn('directorates', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
        });
    }

    public function down(): void
    {
        // This migration is additive only; rollback is intentionally omitted for safety.
    }
};
