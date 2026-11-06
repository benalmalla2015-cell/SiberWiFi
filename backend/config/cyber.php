<?php

/*
|--------------------------------------------------------------------------
| CyberNet module configuration — Track CYB
|--------------------------------------------------------------------------
| Central, additive-only settings for the digital-subscriber network.
| Read via config('cyber.*'). Nothing here alters core behaviour.
*/

return [

    /*
    | Master switch for the module (feature gate mirrors).
    */
    'enabled' => env('CYBER_ENABLED', true),

    /*
    | Subscriber "SIM" numbering: 9 digits starting with the prefix
    | (e.g. 74XXXXXXX). Used by CyberSubscriber issuance (CYB-03).
    */
    'sim_prefix' => env('CYBER_SIM_PREFIX', '74'),
    'sim_length' => env('CYBER_SIM_LENGTH', 9),

    /*
    | Registration document rules (CYB-03).
    */
    'min_name_parts' => 4,
    'id_types' => ['national_id', 'passport'],

    /*
    | RADIUS integration (CYB-01/CYB-04). The backend talks to the
    | CyberNet engine over a private channel; CoA disconnects go out
    | to NAS clients on port 3799. Filled at deployment — safe defaults
    | keep the app fully functional before the VPS exists.
    */
    'radius' => [
        'host' => env('CYBER_RADIUS_HOST', '127.0.0.1'),
        'auth_port' => (int) env('CYBER_RADIUS_AUTH_PORT', 1812),
        'acct_port' => (int) env('CYBER_RADIUS_ACCT_PORT', 1813),
        'coa_port' => (int) env('CYBER_RADIUS_COA_PORT', 3799),
        'secret' => env('CYBER_RADIUS_SECRET', ''),
        'engine_url' => env('CYBER_ENGINE_URL', ''),
        'engine_token' => env('CYBER_ENGINE_TOKEN', ''),
    ],

    /*
    | Host revenue share defaults (CYB-11) — host / platform percent.
    */
    'host_share_percent' => (int) env('CYBER_HOST_SHARE', 65),

    /*
    | Agent commission on each top-up (CYB-07) — percent of the
    | topped-up amount credited to the agent's ledger.
    */
    'agent_commission_percent' => (float) env('CYBER_AGENT_COMMISSION', 5),

    /*
    | Pilot SSID presented to subscribers (CYB-02 host template).
    */
    'ssid' => env('CYBER_SSID', 'CyberNet'),

    /*
    | CYB-14 request signing. The Flutter release build carries
    | --dart-define=CYBER_HMAC_KEY; the same value goes in the server
    | env as CYBER_HMAC_KEY. Signatures bind method|path|ts|nonce|
    | sha256(body)|device_id with a ±300s replay window. Disabled
    | when the env key is absent (local dev/pilot).
    */
    'hmac' => [
        'enabled' => env('CYBER_HMAC_ENABLED', false),
        'key' => env('CYBER_HMAC_KEY', ''),
    ],

    /*
    | EAP-TLS provisioning (CYB-01/02 pilot): the device-bound certificate
    | endpoint serves bundles staged by ops under storage/app/{dir}
    | ({sim}.p12 + ca.crt); p12 export passwords follow the
    | issue-cert.sh convention "cyber{sim_no}". The real CYB-01 issuer
    | keeps the same contract once it lands.
    */
    'cert' => [
        'dir' => 'cyber/certs',
        'domain' => env('CYBER_RADIUS_DOMAIN', 'radius.cybernet.local'),
    ],

    /*
    | «سلفني» subscriber credit (CYB-06). default_limit seeds a
    | subscriber's cyber_credit_limits row on first use; ops may raise
    | it per subscriber directly on the row.
    */
    'credit' => [
        'default_limit' => (float) env('CYBER_CREDIT_LIMIT', 500),
    ],
];
