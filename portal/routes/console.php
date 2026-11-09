<?php

use App\Models\User;
use App\Services\OwnerInvitation;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Validation\Rules\Password;

Artisan::command('management:invite-owner', function () {
    if (User::where('role', 'owner')->exists()) {
        $this->error('An owner already exists.');

        return 1;
    }
    $token = bin2hex(random_bytes(32));
    $path = app(OwnerInvitation::class)->path();
    if (! is_dir(dirname($path))) {
        mkdir(dirname($path), 0700, true);
    }
    file_put_contents($path, json_encode(['hash' => hash('sha256', $token), 'expires' => time() + 3600], JSON_THROW_ON_ERROR), LOCK_EX);
    chmod($path, 0600);
    $this->line(route('owner.setup', $token));

    return 0;
})->purpose('Issue a single-use, one-hour first-owner setup link');

Artisan::command('management:initialize', function () {
    $path = config('management.signing_key_path');
    if (is_file($path)) {
        $this->info('Configuration signing is already initialized. Existing key preserved.');

        return;
    }
    if (! is_dir(dirname($path))) {
        mkdir(dirname($path), 0700, true);
    }
    $file = fopen($path, 'x');
    if (! $file) {
        throw new RuntimeException('Cannot create private signing key.');
    }
    chmod($path, 0600);
    $secret = sodium_crypto_sign_secretkey(sodium_crypto_sign_keypair());
    if (fwrite($file, $secret) !== strlen($secret)) {
        throw new RuntimeException('Could not write signing key.');
    }
    fclose($file);
    $this->info('Configuration signing initialized. Back up the private application data before publishing.');
})->purpose('Initialize a private configuration signing key without overwriting an existing key');

Artisan::command('management:owner', function () {
    if (User::where('role', 'owner')->exists()) {
        $this->error('An owner already exists. This command only creates the first owner.');

        return 1;
    }
    $data = [
        'name' => $this->ask('Owner name'),
        'email' => $this->ask('Owner email'),
        'password' => $this->secret('Owner password (at least 14 characters, with letters and numbers)'),
        'password_confirmation' => $this->secret('Confirm owner password'),
    ];
    $validated = validator($data, [
        'name' => 'required|string|max:100',
        'email' => 'required|email|max:255|unique:users',
        'password' => ['required', 'confirmed', Password::min(14)->letters()->numbers()],
    ])->validate();
    $user = new User($validated);
    $user->role = 'owner';
    $user->email_verified_at = now();
    $user->save();
    $this->info('Owner created. Sign in to manage your apps.');

    return 0;
})->purpose('Create the first owner interactively without logging a password');
