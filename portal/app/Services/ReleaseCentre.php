<?php

namespace App\Services;

use App\Models\AppRelease;
use App\Models\ManagedApp;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class ReleaseCentre
{
    private function queue(array $job): void
    {
        $directory = config('management.upload_inbox');
        if (! is_dir($directory) || ! is_writable($directory)) {
            throw ValidationException::withMessages(['release' => 'Release processing is not configured.']);
        }
        $name = $directory.'/'.$job['ticket'].'.'.$job['operation'];
        $temporary = $directory.'/'.Str::uuid().'.job-upload';
        file_put_contents($temporary, json_encode($job, JSON_THROW_ON_ERROR), LOCK_EX);
        chmod($temporary, 0640);
        rename($temporary, $name.'.ready.json');
    }

    public function upload(ManagedApp $app, UploadedFile $file): AppRelease
    {
        $id = (string) Str::uuid();
        $name = $id.'.zip';
        $directory = config('management.upload_inbox');
        if (! is_dir($directory) || ! is_writable($directory)) {
            throw ValidationException::withMessages(['release' => 'Release processing is not configured.']);
        }
        $checksum = hash_file('sha256', $file->getRealPath());
        $file->move($directory, $name);
        chmod($directory.'/'.$name, 0640);
        $release = AppRelease::create(['id' => $id, 'managed_app_id' => $app->id, 'user_id' => auth()->id()]);
        $this->queue(['operation' => 'prepare', 'ticket' => $id, 'appId' => $app->app_id, 'bundle' => $name, 'sha256' => $checksum]);
        ManagementActivity::record($app->id, 'Release uploaded for verification');

        return $release;
    }

    public function sync(ManagedApp $app): void
    {
        foreach (AppRelease::where('managed_app_id', $app->id)->whereIn('status', ['queued', 'publishing', 'withdrawing'])->get() as $release) {
            $path = config('management.release_receipts').'/'.$release->id.'.json';
            if (! is_file($path)) {
                if ($release->status === 'queued') {
                    $inbox = config('management.upload_inbox');
                    $bundle = $release->id.'.zip';
                    if (is_file($inbox.'/'.$release->id.'.prepare.ready.failed')) {
                        $release->update(['status' => 'failed']);

                        continue;
                    }
                    if (is_file($inbox.'/'.$bundle) && ! is_file($inbox.'/'.$release->id.'.prepare.ready.json')) {
                        $this->queue(['operation' => 'prepare', 'ticket' => $release->id, 'appId' => $app->app_id,
                            'bundle' => $bundle, 'sha256' => hash_file('sha256', $inbox.'/'.$bundle)]);
                    }
                }

                continue;
            }
            $receipt = json_decode(file_get_contents($path), true);
            if (! is_array($receipt) || ($receipt['appId'] ?? null) !== $app->app_id || ($receipt['ticket'] ?? null) !== $release->id) {
                continue;
            }
            $status = $receipt['status'] ?? '';
            if ($status === 'failed') {
                $release->update(['status' => 'failed']);
            } elseif ($release->status === 'queued' && $status === 'ready') {
                $release->update(['status' => 'ready', 'manifest' => $receipt['manifest']]);
            } elseif ($release->status === 'publishing' && $status === 'published') {
                DB::transaction(function () use ($app, $release, $receipt) {
                    $lockedApp = ManagedApp::whereKey($app->id)->lockForUpdate()->firstOrFail();
                    $lockedRelease = AppRelease::whereKey($release->id)->lockForUpdate()->firstOrFail();
                    if ($lockedRelease->status !== 'publishing') {
                        return;
                    }
                    $current = AppRelease::find($lockedApp->public_release_id);
                    if (($current?->manifest['versionCode'] ?? 0) > ($receipt['manifest']['versionCode'] ?? 0)) {
                        $lockedRelease->update(['status' => 'failed']);

                        return;
                    }
                    $lockedApp->update(['public_release_id' => $release->id,
                        'test_release_id' => $lockedApp->test_release_id === $release->id ? null : $lockedApp->test_release_id]);
                    $lockedRelease->update(['status' => 'published', 'manifest' => $receipt['manifest']]);
                    ManagementActivity::record($app->id, 'Release published to everyone');
                });
            } elseif ($release->status === 'withdrawing' && $status === 'withdrawn') {
                $release->update(['status' => 'withdrawn']);
            } elseif (in_array($release->status, ['publishing', 'withdrawing'], true) && $status === 'ready') {
                $operation = $release->status === 'publishing' ? 'promote' : 'retire';
                if (! is_file(config('management.upload_inbox').'/'.$release->id.'.'.$operation.'.ready.json')) {
                    $this->queue(['operation' => $operation, 'ticket' => $release->id, 'appId' => $app->app_id]);
                }
            }
        }
        $app->refresh();
    }

    public function action(ManagedApp $app, AppRelease $release, string $action): void
    {
        abort_unless($release->managed_app_id === $app->id, 404);
        $this->sync($app);
        $release->refresh();
        DB::transaction(function () use ($app, $release, $action) {
            $locked = ManagedApp::whereKey($app->id)->lockForUpdate()->firstOrFail();
            $release = AppRelease::whereKey($release->id)->lockForUpdate()->firstOrFail();
            if ($action === 'test') {
                abort_unless(in_array($release->status, ['ready', 'testing'], true), 422);
                $current = AppRelease::find($locked->public_release_id);
                abort_unless(($release->manifest['versionCode'] ?? 0) > ($current?->manifest['versionCode'] ?? 0), 422);
                if ($locked->test_release_id && $locked->test_release_id !== $release->id) {
                    AppRelease::whereKey($locked->test_release_id)->where('status', 'testing')->update(['status' => 'ready']);
                }
                $locked->update(['test_release_id' => $release->id]);
                $release->update(['status' => 'testing']);
                ManagementActivity::record($app->id, 'Release offered to paired testers');
            } elseif ($action === 'publish') {
                abort_unless(in_array($release->status, ['ready', 'testing'], true), 422);
                abort_if(AppRelease::where('managed_app_id', $app->id)->where('status', 'publishing')->exists(), 409);
                DB::afterCommit(fn () => $this->queue(['operation' => 'promote', 'ticket' => $release->id, 'appId' => $app->app_id]));
                $release->update(['status' => 'publishing']);
                ManagementActivity::record($app->id, 'Public release requested');
            } else {
                abort_unless($action === 'withdraw' && in_array($release->status, ['ready', 'testing'], true), 422);
                if ($locked->test_release_id === $release->id) {
                    $locked->update(['test_release_id' => null]);
                }
                DB::afterCommit(fn () => $this->queue(['operation' => 'retire', 'ticket' => $release->id, 'appId' => $app->app_id]));
                $release->update(['status' => 'withdrawing']);
                ManagementActivity::record($app->id, 'Test release withdrawn');
            }
        });
    }
}
