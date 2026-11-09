<?php

use App\Services\ConfigSigner;
use Illuminate\Contracts\Console\Kernel;

// Deterministic test material only. Never use this seed for a deployment.
require dirname(__DIR__, 2).'/vendor/autoload.php';
$app = require dirname(__DIR__, 2).'/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();
$path = tempnam(sys_get_temp_dir(), 'client-fixture');
try {
    file_put_contents($path, sodium_crypto_sign_secretkey(sodium_crypto_sign_seed_keypair(str_repeat("\x07", 32))));
    config(['management.signing_key_path' => $path]);
    $signer = new ConfigSigner;
    $payload = [
        'schemaVersion' => 1, 'appId' => 'fixture-brand', 'packageId' => 'com.example.fixture',
        'serviceId' => '11111111-1111-4111-8111-111111111111', 'revision' => 1,
        'endpoints' => ['https://primary.example.test/service', 'http://backup.example.test/fallback'],
        'updateManifestUrl' => 'https://updates.example.test/update.json', 'issuedAt' => '2026-11-09T00:00:00+00:00',
    ];
    echo json_encode(['appId' => $payload['appId'], 'packageId' => $payload['packageId'],
        'configUrl' => 'https://manager.example.test/api/v1/apps/fixture-brand/config',
        'verificationKey' => $signer->publicKey(), 'bootstrap' => $signer->sign($payload)], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR)."\n";
} finally {
    unlink($path);
}
