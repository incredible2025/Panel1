<?php

namespace App\Http\Controllers;

use App\Models\AppDevice;
use App\Models\ManagedApp;
use App\Services\PlaybackReports;
use Illuminate\Contracts\View\View;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\Rule;

class PlaybackReportController extends Controller
{
    public function store(Request $request, string $appId): Response
    {
        $app = ManagedApp::where('app_id', $appId)->where('revision', '>', 0)->firstOrFail();
        $secret = $request->bearerToken() ?? '';
        abort_unless(preg_match('/^[a-f0-9]{64}$/D', $secret) === 1, 401);
        abort_if(strlen($request->getContent()) > 2048, 413);
        $device = AppDevice::where('managed_app_id', $app->id)->where('secret_hash', hash('sha256', $secret))->firstOrFail();
        $key = 'playback:'.$device->id;
        abort_if(RateLimiter::tooManyAttempts($key, 12), 429);
        RateLimiter::hit($key, 60);
        $data = $request->validate([
            'event_id' => ['required', 'uuid'],
            'version' => ['required', 'string', 'max:80', 'regex:/^[0-9A-Za-z.+-]+$/D'],
            'build' => ['required', 'integer', 'min:1', 'max:2100000000'],
            'device_model' => ['required', 'string', 'max:80', 'regex:/^[A-Za-z0-9 _()-]+$/D'],
            'os_version' => ['required', 'string', 'max:40', 'regex:/^Android [0-9.]+$/D'],
            'form_factor' => ['required', Rule::in(['tv', 'mobile'])],
            'engine' => ['required', Rule::in(['native', 'compatibility', 'vlc'])],
            'decoding' => ['required', Rule::in(['automatic', 'hardware', 'software'])],
            'kind' => ['required', Rule::in(['live', 'movie', 'series', 'catchup'])],
            'category' => ['required', Rule::in(array_keys(PlaybackReports::CATEGORIES))],
            'source' => ['required', Rule::in(['automatic', 'user'])],
        ]);
        $manual = in_array($data['category'], ['green_screen', 'no_picture', 'pixelation'], true);
        abort_unless(($data['source'] === 'user') === $manual, 422);
        DB::table('playback_events')->insertOrIgnore([...$data, 'managed_app_id' => $app->id,
            'app_device_id' => $device->id, 'created_at' => now()]);

        return response()->noContent()->header('Cache-Control', 'no-store');
    }

    public function index(Request $request, PlaybackReports $reports): View
    {
        $filters = $request->validate(['app' => ['nullable', 'integer', 'exists:managed_apps,id'], 'days' => ['nullable', Rule::in([1, 7, 30])]]);
        $appId = isset($filters['app']) ? (int) $filters['app'] : null;
        $days = (int) ($filters['days'] ?? 7);

        return view('management.playback', ['apps' => ManagedApp::orderBy('name')->get(), 'appId' => $appId, 'days' => $days,
            'summary' => $reports->summary($appId, $days), 'categories' => PlaybackReports::CATEGORIES]);
    }
}
