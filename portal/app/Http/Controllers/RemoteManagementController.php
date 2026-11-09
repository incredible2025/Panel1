<?php

namespace App\Http\Controllers;

use App\Models\AppDevice;
use App\Models\AppRelease;
use App\Models\ManagedApp;
use App\Services\ManagementActivity;
use App\Services\ReleaseCentre;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class RemoteManagementController extends Controller
{
    public function metrics(ManagementActivity $activity, ReleaseCentre $releases)
    {
        $apps = ManagedApp::orderBy('name')->get();
        $result = [];
        foreach ($apps as $app) {
            $releases->sync($app);
            $result[$app->id] = $activity->metrics($app);
        }

        return response()->json(['apps' => $result, 'refreshedAt' => now()->toIso8601String(),
            'timezone' => config('app.timezone')])->header('Cache-Control', 'private, no-store');
    }

    public function upload(Request $request, ManagedApp $managedApp, ReleaseCentre $releases)
    {
        $request->validate(['bundle' => ['required', 'file', 'extensions:zip', 'max:409600']]);
        $releases->upload($managedApp, $request->file('bundle'));

        if ($request->expectsJson()) {
            return response()->json(['status' => 'queued'], 201);
        }

        return back()->with('status', 'Uploaded. Verification runs in the background; no users have received this release yet.');
    }

    public function release(Request $request, ManagedApp $managedApp, AppRelease $release, ReleaseCentre $releases)
    {
        abort_unless($request->user()->role === 'owner', 403);
        $data = $request->validate(['action' => ['required', 'in:test,publish,withdraw']]);
        $releases->action($managedApp, $release, $data['action']);

        return back()->with('status', 'Release action saved. Refresh for processing status.');
    }

    public function pair(Request $request, ManagedApp $managedApp)
    {
        abort_unless($request->user()->role === 'owner', 403);
        $data = $request->validate(['code' => ['required', 'digits:6'], 'label' => ['required', 'string', 'max:80']]);
        DB::transaction(function () use ($managedApp, $data) {
            $device = AppDevice::where('managed_app_id', $managedApp->id)->where('pair_hash', hash('sha256', $data['code']))
                ->where('pair_expires_at', '>', now())->lockForUpdate()->first();
            if (! $device) {
                throw ValidationException::withMessages(['code' => 'Code is incorrect, expired or belongs to another app.']);
            }
            $device->update(['tester' => true, 'label' => $data['label'], 'pair_hash' => null, 'pair_expires_at' => null]);
            ManagementActivity::record($managedApp->id, 'Test device paired');
        });

        return back()->with('status', 'Device paired for test releases.');
    }

    public function revoke(Request $request, ManagedApp $managedApp, AppDevice $device)
    {
        abort_unless($request->user()->role === 'owner', 403);
        abort_unless($device->managed_app_id === $managedApp->id, 404);
        $device->update(['tester' => false, 'pair_hash' => null, 'pair_expires_at' => null]);
        ManagementActivity::record($managedApp->id, 'Test device revoked');

        return back()->with('status', 'Test access removed. Installed apps are never downgraded.');
    }

    public function events(Request $request)
    {
        abort_unless($request->user()->role === 'owner', 403);
        $query = DB::table('management_events')->leftJoin('users', 'users.id', '=', 'management_events.user_id')
            ->leftJoin('managed_apps', 'managed_apps.id', '=', 'management_events.managed_app_id')
            ->select('management_events.*', 'users.name as actor', 'managed_apps.name as app_name');
        if ($request->filled('app')) {
            $query->where('managed_app_id', $request->integer('app'));
        }

        return view('management.events', ['events' => $query->orderByDesc('management_events.id')->paginate(30)->withQueryString(),
            'apps' => ManagedApp::orderBy('name')->get()]);
    }
}
