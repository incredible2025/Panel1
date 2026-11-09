<?php

namespace App\Services;

use RuntimeException;

class ConfigSigner
{
    public static function encode(string $bytes): string
    {
        return sodium_bin2base64($bytes, SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING);
    }

    private function secret(): string
    {
        $path = config('management.signing_key_path');
        if (! is_file($path)) {
            throw new RuntimeException('Configuration signing is not initialized.');
        }
        $secret = file_get_contents($path);
        if (strlen($secret) !== SODIUM_CRYPTO_SIGN_SECRETKEYBYTES) {
            throw new RuntimeException('Invalid configuration signing key.');
        }

        return $secret;
    }

    public function publicKey(): string
    {
        return self::encode(sodium_crypto_sign_publickey_from_secretkey($this->secret()));
    }

    public function sign(array $configuration): array
    {
        $bytes = json_encode($configuration, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);

        return [
            'payload' => self::encode($bytes),
            'signature' => self::encode(sodium_crypto_sign_detached($bytes, $this->secret())),
        ];
    }
}
