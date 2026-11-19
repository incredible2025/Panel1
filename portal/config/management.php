<?php

return [
    'upload_inbox' => env('MANAGEMENT_UPLOAD_INBOX', storage_path('app/private/upload-inbox')),
    'release_receipts' => env('MANAGEMENT_RELEASE_RECEIPTS', storage_path('app/private/release-receipts')),
    'require_two_factor' => env('MANAGEMENT_REQUIRE_2FA', false),
    'signing_key_path' => env('MANAGEMENT_SIGNING_KEY_PATH', storage_path('app/private/config-signing.key')),
];
