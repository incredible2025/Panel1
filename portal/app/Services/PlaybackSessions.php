<?php

namespace App\Services;

use Illuminate\Contracts\Encryption\DecryptException;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\Crypt;

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

    public static function username(?string $value): ?string
    {
        if ($value === null) {
            return null;
        }
        try {
            return Crypt::decryptString($value);
        } catch (DecryptException) {
            return null;
        }
    }
}
