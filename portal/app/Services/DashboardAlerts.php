<?php

namespace App\Services;

use App\Models\AppRelease;
use App\Models\ManagedApp;

class DashboardAlerts
{
    /** @param array<string, mixed> $metrics
     * @param  array<string, mixed>  $health
     * @return list<string>
     */
    public function forApp(ManagedApp $app, array $metrics, array $health): array
    {
        $alerts = [];
        $status = $health['snapshot']['apps'][$app->app_id] ?? [];
        if ($health['fresh'] && ($status['download']['checked'] ?? false) && ! ($status['download']['ok'] ?? false)) {
            $alerts[] = 'APK download check failed';
        }
        $days = $status['certificate']['daysRemaining'] ?? null;
        if ($health['fresh'] && ($status['certificate']['checked'] ?? false)) {
            if (! ($status['certificate']['ok'] ?? false)) {
                $alerts[] = 'Download certificate check failed';
            } elseif (is_numeric($days) && $days <= 21) {
                $alerts[] = 'Download certificate expires within 21 days';
            }
        }
        $jobs = AppRelease::where('managed_app_id', $app->id)->where(function ($query) {
            $query->where(function ($failed) {
                $failed->where('status', 'failed')->where('updated_at', '>=', now()->subDays(7));
            })->orWhere(function ($stalled) {
                $stalled->whereIn('status', ['queued', 'publishing', 'withdrawing'])->where('updated_at', '<', now()->subMinutes(15));
            });
        })->count();
        if ($jobs) {
            $alerts[] = $jobs.' failed or stalled release jobs';
        }
        $public = AppRelease::where('managed_app_id', $app->id)->find($app->public_release_id);
        if ($metrics['older'] && $public && $public->updated_at->lte(now()->subDays(7))) {
            $alerts[] = $metrics['older'].' reporting devices still on older builds';
        }
        $reports = app(PlaybackReports::class)->query($app->id, 1);
        $events = (clone $reports)->count();
        if ($events >= 5) {
            $devices = (clone $reports)->distinct()->count('app_device_id');
            $alerts[] = $events.' playback reports from '.$devices.' installations in 24 hours';
        }

        return $alerts;
    }
}
