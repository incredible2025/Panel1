<?php

namespace App\Http\Controllers;

use App\Models\AppDevice;
use App\Models\ManagedApp;
use App\Services\PlaybackGuidance;
use App\Services\PlaybackReports;
use App\Services\PlaybackSessions;
use Carbon\Carbon;
use Illuminate\Contracts\View\View;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Crypt;
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
        abort_if(strlen($request->getContent()) > 8192, 413);
        $device = AppDevice::where('managed_app_id', $app->id)->where('secret_hash', hash('sha256', $secret))->firstOrFail();
        $key = 'playback:'.$device->id;
        abort_if(RateLimiter::tooManyAttempts($key, $request->input('schema_version') === 2 ? 40 : 12), 429);
        RateLimiter::hit($key, 60);
        $data = $request->validate([
            'event_id' => ['required', 'uuid'],
            'line_username' => ['nullable', 'string', 'max:128', 'not_regex:/[\x00-\x1f\x7f]/u'],
            'version' => ['required', 'string', 'max:80', 'regex:/^[0-9A-Za-z.+-]+$/D'],
            'build' => ['required', 'integer', 'min:1', 'max:2100000000'],
            'device_model' => ['required', 'string', 'max:80', 'regex:/^[A-Za-z0-9 _()-]+$/D'],
            'os_version' => ['required', 'string', 'max:40', 'regex:/^Android [0-9.]+$/D'],
            'form_factor' => ['required', Rule::in(['tv', 'mobile'])],
            'engine' => ['required', Rule::in(['native', 'compatibility', 'vlc', 'none'])],
            'decoding' => ['required', Rule::in(['automatic', 'hardware', 'software', 'none'])],
            'kind' => ['required', Rule::in(['live', 'movie', 'series', 'catchup', 'none'])],
            'category' => ['required', Rule::in(array_keys(PlaybackReports::CATEGORIES))],
            'source' => ['required', Rule::in(['automatic', 'user'])],
            'schema_version' => ['sometimes', 'integer', Rule::in([1, 2])],
            'session_id' => ['nullable', 'uuid'],
            'sequence' => ['nullable', 'integer', 'min:1', 'max:1000000'],
            'elapsed_ms' => ['nullable', 'integer', 'min:0', 'max:604800000'],
            'occurred_at' => ['nullable', 'string', 'max:40', 'date'],
            'details' => ['sometimes', 'array:codec_string,bandwidth_bps,video_codec,audio_codec,actual_decoding,decoder,native_code,cause,width,height,bitrate,buffer_ms,dropped_frames,error_number,http_status,buffering_ms,fps,first_frame,attempt,stage,transports,vpn,network_validated,metered,checks'],
            'details.codec_string' => ['sometimes', 'string', 'max:80', 'regex:/^(?:avc1|avc3|hev1|hvc1|av01|vp09|mp4a)[A-Za-z0-9.,]*$/D'],
            'details.bandwidth_bps' => ['sometimes', 'integer', 'min:0', 'max:1000000000'],
            'details.video_codec' => ['sometimes', Rule::in(['h264', 'hevc', 'av1', 'vp8', 'vp9', 'mpeg2', 'mpeg4', 'unknown'])],
            'details.audio_codec' => ['sometimes', Rule::in(['aac', 'ac3', 'eac3', 'dts', 'opus', 'vorbis', 'mp3', 'pcm', 'unknown'])],
            'details.actual_decoding' => ['sometimes', Rule::in(['hardware', 'software', 'unknown'])],
            'details.decoder' => ['sometimes', 'string', 'max:80', 'regex:/^(?:OMX\.|c2\.|mediacodec|h264|hevc|av1|vp8|vp9|mpeg|ffmpeg)[A-Za-z0-9_.-]{0,70}$/iD'],
            'details.native_code' => ['sometimes', 'string', 'max:90', 'regex:/^(?:ERROR_CODE_[A-Z0-9_]+|MPV_(?:HTTP|DECODER|FORMAT|NETWORK|GENERIC)|VLC_ENCOUNTERED_ERROR|INITIALIZATION_TIMEOUT|JAVA_(?:OUT_OF_MEMORY|ILLEGAL_STATE|LINKAGE|UNCAUGHT_EXCEPTION))$/D'],
            'details.cause' => ['sometimes', Rule::in(['unknown', 'http', 'dns', 'tls', 'timeout', 'connection', 'decoder', 'format'])],
            'details.stage' => ['sometimes', Rule::in(['opening', 'playing', 'buffering', 'recovering', 'stopped', 'unknown'])],
            'details.width' => ['sometimes', 'integer', 'min:0', 'max:16384'], 'details.height' => ['sometimes', 'integer', 'min:0', 'max:16384'],
            'details.bitrate' => ['sometimes', 'integer', 'min:0', 'max:1000000000'],
            'details.buffer_ms' => ['sometimes', 'integer', 'min:0', 'max:3600000'],
            'details.dropped_frames' => ['sometimes', 'integer', 'min:0', 'max:1000000000'],
            'details.error_number' => ['sometimes', 'integer', 'min:0', 'max:100000'],
            'details.http_status' => ['sometimes', 'integer', 'min:100', 'max:599'],
            'details.buffering_ms' => ['sometimes', 'integer', 'min:0', 'max:86400000'],
            'details.fps' => ['sometimes', 'numeric', 'gt:0', 'max:240'],
            'details.first_frame' => ['sometimes', 'boolean'], 'details.vpn' => ['sometimes', 'boolean'],
            'details.network_validated' => ['sometimes', 'boolean'], 'details.metered' => ['sometimes', 'boolean'],
            'details.attempt' => ['sometimes', 'integer', 'min:1', 'max:1000'],
            'details.transports' => ['sometimes', 'array', 'max:5'],
            'details.transports.*' => [Rule::in(['Wi-Fi', 'Ethernet', 'Mobile', 'VPN', 'Other'])],
            'details.checks' => ['sometimes', 'array', 'max:20'],
            'details.checks.*' => ['array:stage,code,status,elapsed_ms'],
            'details.checks.*.stage' => ['required', Rule::in(['network', 'server', 'dns', 'tcp', 'tls', 'fallback', 'api', 'account', 'limits', 'clock', 'live', 'movies', 'series', 'stream'])],
            'details.checks.*.code' => ['required', 'string', 'max:64', 'regex:/^[A-Z][A-Z0-9_]{1,63}$/D'],
            'details.checks.*.status' => ['required', Rule::in(['passed', 'warning', 'failed', 'skipped'])],
            'details.checks.*.elapsed_ms' => ['required', 'integer', 'min:0', 'max:120000'],
        ]);
        $manual = in_array($data['category'], ['green_screen', 'no_picture', 'pixelation', 'diagnosis'], true);
        abort_unless(($data['source'] === 'user') === $manual, 422);
        abort_if($data['category'] !== 'diagnosis' && in_array('none', [$data['engine'], $data['decoding'], $data['kind']], true), 422);
        abort_if(isset($data['details']['checks']) && $data['category'] !== 'diagnosis', 422);
        // Acknowledge older clients without retaining healthy lifecycle events.
        if (! in_array($data['category'], [...PlaybackReports::ERRORS, 'diagnosis'], true)) {
            return response()->noContent()->header('Cache-Control', 'no-store');
        }
        if (isset($data['line_username']) && $data['line_username'] !== '') {
            $data['line_username'] = Crypt::encryptString($data['line_username']);
        } else {
            unset($data['line_username']);
        }
        if (isset($data['occurred_at'])) {
            $occurred = Carbon::parse($data['occurred_at'])->utc();
            if ($occurred->lt(now()->subDays(7)) || $occurred->gt(now()->addMinutes(5))) {
                $data['occurred_at'] = null;
                $data['details']['device_clock_untrusted'] = true;
            } else {
                $data['occurred_at'] = $occurred;
            }
        }
        if (isset($data['details'])) {
            $data['details'] = json_encode($data['details'], JSON_THROW_ON_ERROR);
        }
        DB::table('playback_events')->insertOrIgnore([...$data, 'managed_app_id' => $app->id,
            'app_device_id' => $device->id, 'created_at' => now()]);

        return response()->noContent()->header('Cache-Control', 'no-store');
    }

    public function index(Request $request, PlaybackReports $reports): View
    {
        $filters = $request->validate(['app' => ['nullable', 'integer', 'exists:managed_apps,id'], 'days' => ['nullable', Rule::in([1, 7, 30])],
            'engine' => ['nullable', Rule::in(['native', 'compatibility', 'vlc'])],
            'version' => ['nullable', 'string', 'max:80', 'regex:/^[0-9A-Za-z.+-]+$/D'],
            'model' => ['nullable', 'string', 'max:80', 'regex:/^[A-Za-z0-9 _()-]+$/D'],
            'codec' => ['nullable', Rule::in(['h264', 'hevc', 'av1', 'vp8', 'vp9', 'mpeg2', 'mpeg4', 'unknown'])],
            'reference' => ['nullable', 'string', 'regex:/^(?:D-[A-Fa-f0-9]{8}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12})$/D'],
        ]);
        $appId = isset($filters['app']) ? (int) $filters['app'] : null;
        $days = (int) ($filters['days'] ?? 7);
        $sessions = app(PlaybackSessions::class);
        $events = $sessions->events($appId, $days, array_filter($filters, fn ($value) => $value !== null && $value !== ''));
        $issues = (clone $events)->whereIn('category', PlaybackReports::ERRORS);
        $entries = (clone $issues)->orderByDesc('id')->paginate(20)->withQueryString();
        foreach ($entries as $entry) {
            $entry->username = PlaybackSessions::username($entry->line_username);
            $entry->evidence = PlaybackSessions::details($entry->details);
            $entry->guidance = PlaybackGuidance::describe($entry->category, $entry->evidence);
            $entry->installation = PlaybackSessions::installation($entry->managed_app_id, $entry->app_device_id);
        }

        return view('management.playback', ['apps' => ManagedApp::orderBy('name')->get(), 'appId' => $appId, 'days' => $days,
            'summary' => ['events' => (clone $issues)->count(), 'devices' => (clone $issues)->distinct()->count('app_device_id')],
            'entries' => $entries, 'filters' => $filters, 'categories' => PlaybackReports::CATEGORIES,
            'diagnoses' => ! empty($filters['reference']) ? (clone $events)->where('category', 'diagnosis')->orderByDesc('id')->limit(20)->get() : collect(),
            'versions' => $reports->query($appId, 30, false)->distinct()->orderByDesc('build')->get(['version', 'build']),
            'models' => $reports->query($appId, 30, false)->distinct()->orderBy('device_model')->pluck('device_model')]);
    }

    public function session(AppDevice $device, string $session): View
    {
        $query = DB::table('playback_events')->where('app_device_id', $device->id)->where('session_id', $session)->whereIn('category', [...PlaybackReports::ERRORS, 'diagnosis'])->where('created_at', '>=', now()->subDays(30));
        abort_unless((clone $query)->exists(), 404);
        $events = (clone $query)->orderByRaw('coalesce(sequence, case when category=\'crash\' then 1000001 else 1000002 end)')->orderBy('id')->limit(200)->get();
        foreach ($events as $event) {
            $event->username = PlaybackSessions::username($event->line_username);
            $event->evidence = PlaybackSessions::details($event->details);
            $event->guidance = PlaybackGuidance::describe($event->category, $event->evidence);
        }

        return view('management.playback-session', ['events' => $events, 'total' => (clone $query)->count(),
            'brand' => ManagedApp::findOrFail($device->managed_app_id), 'session' => $session,
            'reference' => 'D-'.strtoupper(substr($session, 0, 8)),
            'installation' => PlaybackSessions::installation($device->managed_app_id, $device->id), 'categories' => PlaybackReports::CATEGORIES]);
    }
}
