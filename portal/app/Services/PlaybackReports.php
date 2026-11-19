<?php

namespace App\Services;

use Illuminate\Database\Query\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class PlaybackReports
{
    public const CATEGORIES = [
        'connection' => 'Connection or service error',
        'decoder' => 'Decoder or codec error',
        'timeout' => 'Playback start timed out',
        'certificate' => 'Secure connection error',
        'buffering' => 'Buffering for at least 20 seconds',
        'green_screen' => 'Green screen reported by user',
        'no_picture' => 'Audio without picture reported by user',
        'pixelation' => 'Pixelation reported by user',
        'crash' => 'Uncaught Android playback exception',
        'unknown' => 'Other playback error',
    ];

    public function query(?int $appId = null, int $days = 7): Builder
    {
        return DB::table('playback_events')->where('created_at', '>=', now()->subDays($days))
            ->when($appId !== null, fn ($query) => $query->where('managed_app_id', $appId));
    }

    /** @return array{events: int, devices: int, groups: Collection<int, \stdClass>} */
    public function summary(?int $appId = null, int $days = 7): array
    {
        $query = $this->query($appId, $days);

        return ['events' => (clone $query)->count(),
            'devices' => (clone $query)->distinct()->count('app_device_id'),
            'groups' => (clone $query)->select('device_model', 'os_version', 'form_factor', 'engine', 'decoding', 'category', 'source', 'version', 'build',
                DB::raw('count(*) as events'), DB::raw('count(distinct app_device_id) as devices'), DB::raw('max(created_at) as last_reported'))
                ->groupBy('device_model', 'os_version', 'form_factor', 'engine', 'decoding', 'category', 'source', 'version', 'build')
                ->orderByDesc('events')->limit(100)->get()];
    }
}
