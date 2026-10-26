<?php

// TaizTel (yemoney.net) instant top-up provider configuration.
// Secrets live in .env only — never commit real credentials.
return [
    'base_url' => env('TAIZTEL_BASE_URL', 'https://taiztel.yemoney.net/api/yr/'),
    'timeout'  => (int) env('TAIZTEL_TIMEOUT', 30),

    // Agent accounts. Each service maps to one account key.
    'accounts' => [
        'south' => [
            'userid'   => env('TAIZTEL_SOUTH_USERID'),
            'username' => env('TAIZTEL_SOUTH_USERNAME'), // also used as "mobile" owner
            'password' => env('TAIZTEL_SOUTH_PASSWORD'),
        ],
        'north' => [
            'userid'   => env('TAIZTEL_NORTH_USERID'),
            'username' => env('TAIZTEL_NORTH_USERNAME'),
            'password' => env('TAIZTEL_NORTH_PASSWORD'),
        ],
    ],

    // Default account for services that do not override it.
    'default_account' => env('TAIZTEL_DEFAULT_ACCOUNT', 'south'),

    // Provider prices are treated as southern YER; converted to the
    // buyer's region currency the same way card purchases do.
    'provider_currency' => 'south',
];
