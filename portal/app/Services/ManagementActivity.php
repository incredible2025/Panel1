<?php

namespace App\Services;

use App\Models\AppDevice;
use App\Models\AppRelease;
use App\Models\ManagedApp;
use Illuminate\Support\Facades\DB;

class ManagementActivity
{
    public static function record(?int $appId, string $action): void
    {
        DB::table('management_events')->insert([
            'managed_app_id' => $appId, 'user_id' => auth()->id(),
            'action' => $action, 'created_at' => now(),
        ]);
    }

    public function metrics(ManagedApp $app): array
    {
        $devices = AppDevice::where('managed_app_id', $app->id);
        $recent = (clone $devices)->where('last_seen_at', '>=', now()->subDays(30));
        $public = AppRelease::where('managed_app_id', $app->id)->find($app->public_release_id);
        $build = $public?->manifest['versionCode'] ?? null;
        $total = (clone $recent)->count();
        $latest = $build === null ? 0 : (clone $recent)->where('build', $build)->count();

        return [
            'reporting' => $total,
            'latest' => $latest,
            'older' => $build === null ? 0 : (clone $recent)->where('build', '<', $build)->count(),
            'ahead' => $build === null ? 0 : (clone $recent)->where('build', '>', $build)->count(),
            'adoption' => $total && $build !== null ? round($latest / $total * 100, 1) : null,
            'publicBuild' => $build,
            'publicVersion' => $public?->manifest['versionName'] ?? null,
            'online' => (clone $devices)->where('last_seen_at', '>=', now()->subMinutes(3))->count(),
            'today' => (clone $devices)->where('last_seen_at', '>=', now()->startOfDay())->count(),
            'current' => (clone $recent)->where('revision', $app->revision)->count(),
            'pending' => (clone $recent)->where('revision', '<', $app->revision)->count(),
            'stale' => (clone $recent)->where('last_seen_at', '<', now()->subMinutes(3))->count(),
            'versions' => (clone $recent)->select('version', 'build', DB::raw('count(*) as devices'))
                ->groupBy('version', 'build')->orderByDesc('build')->get(),
        ];
    }
}
