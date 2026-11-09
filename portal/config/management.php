<?php

return [
    'require_two_factor' => env('MANAGEMENT_REQUIRE_2FA', false),
    'signing_key_path' => env('MANAGEMENT_SIGNING_KEY_PATH', storage_path('app/private/config-signing.key')),
];
