<?php

namespace App\Services;

use App\Models\AppRelease;
use Carbon\Carbon;

class DashboardHealth
{
    private function recent(mixed $value, \DateTimeInterface $threshold): bool
    {
        try {
            return is_string($value) && Carbon::parse($value)->gt($threshold);
        } catch (\Throwable) {
            return false;
        }
    }

    public function snapshot(): array
    {
        $path = config('management.release_receipts').'/health.json';
        if (! is_file($path) || filesize($path) > 65536) {
            return [];
        }
        try {
            $data = json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR);

            return is_array($data) && ($data['schemaVersion'] ?? 0) === 1 ? $data : [];
        } catch (\Throwable) {
            return [];
        }
    }

    public function summary(): array
    {
        $data = $this->snapshot();
        $fresh = $this->recent($data['capturedAt'] ?? null, now()->subMinutes(5));
        $backup = $data['backup'] ?? [];
        $backupGood = ($backup['success'] ?? false) && ($backup['integrityVerified'] ?? false)
            && $this->recent($backup['completedAt'] ?? null, now()->subHours(36));
        $disk = $data['disk'] ?? [];
        $diskGood = ($disk['totalBytes'] ?? 0) > 0 && ($disk['freeBytes'] ?? 0) >= 5 * 1024 ** 3
            && $disk['freeBytes'] / $disk['totalBytes'] >= .1;

        return ['fresh' => $fresh, 'snapshot' => $data, 'backupGood' => $backupGood,
            'diskGood' => $diskGood, 'failed' => AppRelease::where('status', 'failed')->count(),
            'stalled' => AppRelease::whereIn('status', ['queued', 'publishing', 'withdrawing'])->where('updated_at', '<', now()->subMinutes(15))->count(),
            'pending' => AppRelease::whereIn('status', ['queued', 'publishing', 'withdrawing'])->count()];
    }
}
