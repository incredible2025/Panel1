<?php

use App\Models\AppDevice;
use App\Models\AppRelease;
use App\Models\ManagedApp;
use App\Models\User;
use App\Services\OwnerInvitation;
use App\Services\ReleaseCentre;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schedule;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rules\Password;

Artisan::command('management:housekeeping', function () {
    AppDevice::where('last_seen_at', '<', now()->subDays(30))->delete();
    AppDevice::where('pair_expires_at', '<=', now())->update(['pair_hash' => null, 'pair_expires_at' => null]);
    $disk = Storage::disk('local');
    $used = ManagedApp::whereNotNull('brand_logo')->pluck('brand_logo')->all();
    foreach ($disk->files('brand-assets') as $path) {
        if (! in_array($path, $used, true) && $disk->lastModified($path) < now()->subDay()->timestamp) {
            $disk->delete($path);
        }
    }
    $this->info('Inactive activity records and expired pairing codes removed.');
});
Artisan::command('management:sync-releases', function () {
    foreach (ManagedApp::all() as $app) {
        app(ReleaseCentre::class)->sync($app);
    }
});
Artisan::command('management:import-release {app} {ticket}', function () {
    $app = ManagedApp::where('app_id', $this->argument('app'))->firstOrFail();
    $ticket = $this->argument('ticket');
    if (! preg_match('/^[a-f0-9-]{36}$/D', $ticket) || $app->public_release_id) {
        $this->error('Use a verified receipt for an app without an imported public release.');

        return 1;
    }
    $receipt = json_decode(file_get_contents(config('management.release_receipts').'/'.$ticket.'.json'), true, flags: JSON_THROW_ON_ERROR);
    if (($receipt['appId'] ?? '') !== $app->app_id || ($receipt['ticket'] ?? '') !== $ticket
        || ($receipt['status'] ?? '') !== 'published' || ($receipt['manifest']['applicationId'] ?? '') !== $app->package_id) {
        $this->error('Verified release receipt does not match this app.');

        return 1;
    }
    DB::transaction(function () use ($app, $ticket, $receipt) {
        AppRelease::create(['id' => $ticket, 'managed_app_id' => $app->id, 'status' => 'published', 'manifest' => $receipt['manifest']]);
        $app->update(['public_release_id' => $ticket]);
    });
    $this->info('Existing verified public release imported.');
});
Schedule::command('management:housekeeping')->daily();
Schedule::command('management:sync-releases')->everyMinute()->withoutOverlapping();

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
