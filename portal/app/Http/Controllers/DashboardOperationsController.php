<?php

namespace App\Http\Controllers;

use App\Models\AppRelease;
use App\Models\ManagedApp;
use App\Services\AppConfiguration;
use App\Services\ConfigurationPreview;
use App\Services\DashboardHealth;
use App\Services\DashboardReview;
use App\Services\ManagementActivity;
use App\Services\ReleaseCentre;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class DashboardOperationsController extends Controller
{
    public function health(Request $request, DashboardHealth $health)
    {
        abort_unless($request->user()->role === 'owner', 403);

        return view('management.health', ['health' => $health->summary(),
            'issues' => AppRelease::with('app')->where(function ($query) {
                $query->where('status', 'failed')->orWhere(function ($pending) {
                    $pending->whereIn('status', ['queued', 'publishing', 'withdrawing'])->where('updated_at', '<', now()->subMinutes(15));
                });
            })->latest()->limit(30)->get()]);
    }

    public function reseller(Request $request, ManagedApp $managedApp)
    {
        abort_unless($request->user()->role === 'owner', 403);
        $data = $request->validate(self::resellerRules());
        $managedApp->update($data);
        ManagementActivity::record($managedApp->id, 'Reseller record updated');

        return back()->with('status', 'Private reseller record saved.');
    }

    public static function resellerRules(): array
    {
        return ['reseller_name' => ['nullable', 'string', 'max:100'], 'reseller_email' => ['nullable', 'email:rfc', 'max:180'],
            'reseller_contact' => ['nullable', 'string', 'max:240'], 'downloader_code' => ['nullable', 'regex:/^[0-9]{1,20}$/D']];
    }

    public function result(Request $request, ManagedApp $managedApp, AppRelease $release)
    {
        abort_unless($release->managed_app_id === $managedApp->id, 404);
        $data = $request->validate(['test_result' => ['required', 'in:passed,failed,not_required'], 'test_note' => ['nullable', 'string', 'max:240', 'required_if:test_result,not_required']]);
        abort_if($data['test_result'] === 'not_required' && $request->user()->role !== 'owner', 403);
        DB::transaction(function () use ($request, $managedApp, $release, $data) {
            $locked = AppRelease::whereKey($release->id)->lockForUpdate()->firstOrFail();
            abort_unless(in_array($locked->status, ['ready', 'testing'], true), 422);
            $locked->update([...$data, 'tested_by' => $request->user()->id, 'tested_at' => now(), 'review_version' => $locked->review_version + 1]);
            ManagementActivity::record($managedApp->id, 'Release test result recorded');
        });

        return back()->with('status', 'Test result saved. This does not publish the release.');
    }

    public function prepareSingle(Request $request, ManagedApp $app, string $kind)
    {
        abort_unless(in_array($kind, ['publish', 'replace', 'rollback'], true), 404);
        $version = (int) $request->validate(['draft_version' => ['required', 'integer', 'min:1']])['draft_version'];
        abort_unless($app->draft_version === $version, 409, 'Settings changed. Reload before reviewing.');
        $service = app(AppConfiguration::class);
        $targetService = $app->service_id;
        $revision = null;
        if ($kind === 'replace') {
            abort_unless($request->user()->role === 'owner', 403);
            $request->validate(['confirmation' => ['required', 'in:REPLACE']]);
            $candidate = $service->validate($request->all());
            $targetService = 'replacement';
        } elseif ($kind === 'rollback') {
            $revision = (int) $request->route('revision');
            $old = $app->revisions()->where('revision', $revision)->firstOrFail();
            abort_unless($old->service_id === $app->service_id || $request->user()->role === 'owner', 403);
            $candidate = $old->configuration;
            $targetService = $old->service_id;
        } else {
            $candidate = $service->validate($app->draft);
        }
        $item = ['id' => $app->id, 'name' => $app->name, 'version' => $version, 'candidate' => $candidate,
            'revision' => $revision, 'preview' => app(ConfigurationPreview::class)->describe($app, $candidate, $targetService)];
        $ticket = app(DashboardReview::class)->store($request, $kind, ['items' => [$item]]);

        return redirect()->route('operations.review', $ticket);
    }

    public function bulk(Request $request)
    {
        abort_unless($request->user()->role === 'owner', 403);

        $apps = ManagedApp::orderBy('name')->get();
        foreach ($apps as $app) {
            app(ReleaseCentre::class)->sync($app);
        }

        return view('management.bulk', ['apps' => $apps,
            'releases' => AppRelease::whereIn('status', ['ready', 'testing'])->latest()->get()->groupBy('managed_app_id')]);
    }

    public function prepareBulk(Request $request)
    {
        abort_unless($request->user()->role === 'owner', 403);
        $data = $request->validate(['app_ids' => ['required', 'array', 'min:1', 'max:50'], 'app_ids.*' => ['required', 'integer', 'distinct', 'exists:managed_apps,id'],
            'operation' => ['required', 'in:notice-draft,notice-publish,release-test,release-publish'], 'releases' => ['nullable', 'array'],
            'noticeTitle' => ['nullable', 'string', 'max:80'], 'noticeBody' => ['nullable', 'string', 'max:500'], 'noticeExpiresAt' => ['nullable', 'date']]);
        $items = [];
        foreach (ManagedApp::whereIn('id', $data['app_ids'])->orderBy('id')->get() as $app) {
            $item = ['id' => $app->id, 'name' => $app->name, 'version' => $app->draft_version, 'public' => $app->public_release_id, 'test' => $app->test_release_id];
            if (str_starts_with($data['operation'], 'notice-')) {
                $published = $app->revisions()->where('revision', $app->revision)->first();
                if ($data['operation'] === 'notice-publish' && (! $published || app(ConfigurationPreview::class)->changes($published->configuration, $app->draft))) {
                    throw ValidationException::withMessages(['app_ids' => $app->name.' has unpublished settings or no initial publication. Save a notice draft, or review that app separately.']);
                }
                $base = $data['operation'] === 'notice-publish' ? $published->configuration : $app->draft;
                $candidate = app(AppConfiguration::class)->validate([...$base,
                    'noticeTitle' => $data['noticeTitle'] ?? null, 'noticeBody' => $data['noticeBody'] ?? null, 'noticeExpiresAt' => $data['noticeExpiresAt'] ?? null]);
                $item['candidate'] = $candidate;
                $item['preview'] = ['changes' => app(ConfigurationPreview::class)->changes($base, $candidate), 'signInRequired' => false, 'firstPublication' => false];
            } else {
                $release = AppRelease::where('managed_app_id', $app->id)->findOrFail($data['releases'][$app->id] ?? '');
                abort_unless(in_array($release->status, ['ready', 'testing'], true), 409);
                if ($data['operation'] === 'release-publish') {
                    app(ReleaseCentre::class)->assertPublishable($app, $release);
                }
                $item += ['release_id' => $release->id, 'release_status' => $release->status, 'review_version' => $release->review_version,
                    'release_version' => $release->manifest['versionName'].' ('.$release->manifest['versionCode'].')', 'test_result' => $release->test_result];
            }
            $items[] = $item;
        }
        $ticket = app(DashboardReview::class)->store($request, $data['operation'], ['items' => $items]);

        return redirect()->route('operations.review', $ticket);
    }

    public function review(Request $request, string $ticket)
    {
        $plan = app(DashboardReview::class)->get($request, $ticket);
        abort_unless(in_array($plan['kind'], ['publish', 'rollback', 'replace', 'notice-draft', 'notice-publish', 'release-test', 'release-publish'], true), 404);

        return view('management.review', compact('plan', 'ticket'));
    }

    public function confirm(Request $request, string $ticket)
    {
        $request->validate(['reviewed' => ['accepted']]);
        $plan = app(DashboardReview::class)->get($request, $ticket);
        $kind = $plan['kind'];
        abort_unless(in_array($kind, ['publish', 'rollback', 'replace', 'notice-draft', 'notice-publish', 'release-test', 'release-publish'], true), 404);
        if (! in_array($kind, ['publish', 'rollback'], true)) {
            abort_unless($request->user()->role === 'owner', 403);
        }
        if ($kind === 'replace') {
            abort_if(now()->timestamp - $request->session()->get('auth.password_confirmed_at', 0) > config('auth.password_timeout', 10800), 403, 'Confirm your password again before replacing a service.');
        }
        DB::transaction(function () use ($request, $plan, $kind) {
            $locked = [];
            foreach ($plan['data']['items'] as $item) {
                $app = ManagedApp::whereKey($item['id'])->lockForUpdate()->firstOrFail();
                abort_unless($app->draft_version === $item['version'], 409, 'An app changed after review. Prepare a fresh review.');
                if (str_starts_with($kind, 'release-')) {
                    $release = AppRelease::where('managed_app_id', $app->id)->whereKey($item['release_id'])->lockForUpdate()->firstOrFail();
                    abort_unless($release->status === $item['release_status'] && $release->review_version === $item['review_version']
                        && $app->public_release_id === $item['public'] && $app->test_release_id === $item['test'], 409, 'Release state changed. Prepare a fresh review.');
                    if ($kind === 'release-publish') {
                        app(ReleaseCentre::class)->assertPublishable($app, $release);
                    }
                }
                $locked[] = [$app, $item];
            }
            foreach ($locked as [$app, $item]) {
                $service = app(AppConfiguration::class);
                if (str_starts_with($kind, 'release-')) {
                    app(ReleaseCentre::class)->action($app, AppRelease::findOrFail($item['release_id']), $kind === 'release-test' ? 'test' : 'publish');
                } elseif ($kind === 'publish') {
                    $service->publish($request->user(), $app, $app->draft_version);
                } elseif ($kind === 'rollback') {
                    $service->rollback($request->user(), $app, $item['revision'], $app->draft_version);
                } elseif ($kind === 'replace') {
                    $service->replaceService($request->user(), $app, $item['candidate'], $app->draft_version);
                } else {
                    $service->saveDraft($request->user(), $app, $item['candidate'], $app->draft_version);
                    if ($kind === 'notice-publish') {
                        $service->publish($request->user(), $app->fresh(), $app->fresh()->draft_version);
                    }
                }
            }
            ManagementActivity::record(null, 'Reviewed dashboard operation applied');
        });
        app(DashboardReview::class)->forget($request, $ticket);

        return redirect()->route('dashboard')->with('status', 'Reviewed changes applied to the selected apps.');
    }
}
