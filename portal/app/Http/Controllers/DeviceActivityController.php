<?php

namespace App\Http\Controllers;

use App\Models\AppDevice;
use App\Models\AppRelease;
use App\Models\ManagedApp;
use App\Services\ReleaseCentre;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;

class DeviceActivityController extends Controller
{
    private function app(string $appId): ManagedApp
    {
        return ManagedApp::where('app_id', $appId)->where('revision', '>', 0)->firstOrFail();
    }

    private function secret(Request $request): string
    {
        $secret = $request->bearerToken() ?? '';
        abort_unless(preg_match('/^[a-f0-9]{64}$/D', $secret), 401);

        return hash('sha256', $secret);
    }

    public function heartbeat(Request $request, string $appId)
    {
        $app = $this->app($appId);
        $hash = $this->secret($request);
        abort_if(strlen($request->getContent()) > 2048, 413);
        $data = $request->validate([
            'version' => ['required', 'string', 'max:80', 'regex:/^[0-9A-Za-z.+-]+$/'],
            'build' => ['required', 'integer', 'min:1', 'max:2100000000'],
            'revision' => ['required', 'integer', 'min:0', 'max:'.$app->revision],
        ]);
        $key = 'activity:'.$app->id.':'.$hash;
        abort_if(RateLimiter::tooManyAttempts($key, 6), 429);
        RateLimiter::hit($key, 60);
        AppDevice::updateOrCreate(['managed_app_id' => $app->id, 'secret_hash' => $hash], [
            ...$data, 'last_seen_at' => now(),
        ]);

        return response()->noContent()->header('Cache-Control', 'no-store');
    }

    public function pair(Request $request, string $appId)
    {
        $app = $this->app($appId);
        $hash = $this->secret($request);
        $key = 'pair:'.$app->id.':'.$hash;
        abort_if(RateLimiter::tooManyAttempts($key, 3), 429);
        RateLimiter::hit($key, 600);
        $device = AppDevice::where('managed_app_id', $app->id)->where('secret_hash', $hash)->firstOrFail();
        // Globally unique active code; never return another device's existing code.
        do {
            $code = (string) random_int(100000, 999999);
            $codeHash = hash('sha256', $code);
        } while (AppDevice::where('pair_hash', $codeHash)->exists());
        $device->update(['pair_hash' => $codeHash, 'pair_expires_at' => now()->addMinutes(10)]);

        return response()->json(['code' => $code, 'expiresInSeconds' => 600])->header('Cache-Control', 'no-store');
    }

    public function updates(Request $request, string $appId)
    {
        $app = $this->app($appId);
        app(ReleaseCentre::class)->sync($app);
        $public = AppRelease::where('managed_app_id', $app->id)->find($app->public_release_id);
        $selected = $public;
        $secret = $request->bearerToken();
        if (is_string($secret) && preg_match('/^[a-f0-9]{64}$/D', $secret)) {
            $tester = AppDevice::where('managed_app_id', $app->id)
                ->where('secret_hash', hash('sha256', $secret))->where('tester', true)->exists();
            if ($tester && $app->test_release_id) {
                $candidate = AppRelease::where('managed_app_id', $app->id)->find($app->test_release_id);
                if ($candidate && $candidate->status === 'testing'
                    && ($candidate->manifest['versionCode'] ?? 0) > ($public?->manifest['versionCode'] ?? 0)) {
                    $selected = $candidate;
                }
            }
        }
        abort_unless($selected?->manifest, 404);

        return response()->json($selected->manifest)->header('Cache-Control', 'private, no-store')->header('Vary', 'Authorization');
    }
}
