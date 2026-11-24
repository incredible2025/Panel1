<?php

namespace App\Services;

use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;

class PlaybackSessions
{
    /** @param array<string, mixed> $filters */
    private function filter(Builder $query, array $filters, string $prefix = ''): void
    {
        foreach (['engine' => 'engine', 'version' => 'version', 'model' => 'device_model'] as $key => $column) {
            if (! empty($filters[$key])) {
                $query->where($prefix.$column, $filters[$key]);
            }
        }
        if (! empty($filters['codec'])) {
            $query->whereRaw($prefix === 'matching.' ? "json_extract(matching.details, '$.video_codec') = ?" : "json_extract(details, '$.video_codec') = ?", [$filters['codec']]);
        }
    }

    /** @param array<string, mixed> $filters */
    public function events(?int $appId, int $days, array $filters): Builder
    {
        $query = app(PlaybackReports::class)->query($appId, $days, false);
        if (! empty($filters['reference'])) {
            $reference = strtolower($filters['reference']);
            if (str_starts_with($reference, 'd-')) {
                $reference = substr($reference, 2);
            }
            $query->where('session_id', 'like', $reference.'%');
        }
        if (array_intersect_key($filters, array_flip(['engine', 'version', 'model', 'codec']))) {
            $query->where(function ($query) use ($filters, $days) {
                $query->whereExists(function ($match) use ($filters, $days) {
                    $match->selectRaw('1')->from('playback_events as matching')
                        ->whereColumn('matching.app_device_id', 'playback_events.app_device_id')
                        ->whereColumn('matching.session_id', 'playback_events.session_id')
                        ->where('matching.created_at', '>=', now()->subDays($days));
                    $this->filter($match, $filters, 'matching.');
                })->orWhere(function ($legacy) use ($filters) {
                    $legacy->whereNull('session_id');
                    $this->filter($legacy, $filters);
                });
            });
        }

        return $query;
    }

    public function sessions(Builder $events): Builder
    {
        $errors = "'".implode("','", PlaybackReports::ERRORS)."'";

        return (clone $events)->whereNotNull('session_id')->select('app_device_id', 'session_id', 'managed_app_id')
            ->selectRaw('max(version) as version, max(build) as build, max(device_model) as device_model, min(created_at) as first_received, max(created_at) as last_received')
            ->selectRaw("sum(case when category='started' then 1 else 0 end) as starts")
            ->selectRaw("sum(case when category in ($errors) then 1 else 0 end) as errors")
            ->selectRaw("max(case when category in ($errors) then coalesce(sequence,case when category='crash' then 1000001 else 0 end) end) as error_sequence")
            ->selectRaw("max(case when category='playing' then sequence end) as playing_sequence")
            ->groupBy('app_device_id', 'session_id', 'managed_app_id');
    }

    /** @return array{sessions:int, affected:int, recovered:int, playing:int} */
    public function statistics(Builder $events): array
    {
        $rows = DB::query()->fromSub($this->sessions($events), 'sessions')->where('starts', '>', 0);

        return ['sessions' => (clone $rows)->count(), 'affected' => (clone $rows)->where('errors', '>', 0)->count(),
            'playing' => (clone $rows)->whereNotNull('playing_sequence')->count(),
            'recovered' => (clone $rows)->where('errors', '>', 0)->whereColumn('playing_sequence', '>', 'error_sequence')->count()];
    }

    /** @return array<string, mixed> */
    public static function details(?string $value): array
    {
        $decoded = json_decode($value ?? '{}', true);

        return is_array($decoded) ? $decoded : [];
    }

    public static function installation(int $appId, int $deviceId): string
    {
        return 'I-'.strtoupper(substr(hash_hmac('sha256', $appId.'/'.$deviceId, config('app.key')), 0, 10));
    }
}
