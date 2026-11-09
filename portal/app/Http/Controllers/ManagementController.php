<?php

namespace App\Http\Controllers;

use App\Models\AppDevice;
use App\Models\AppRelease;
use App\Models\ManagedApp;
use App\Models\User;
use App\Services\AppConfiguration;
use App\Services\ConfigSigner;
use App\Services\ManagementActivity;
use App\Services\ReleaseCentre;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rules\Password;

class ManagementController extends Controller
{
    public function index()
    {
        $apps = ManagedApp::orderBy('name')->get();
        $metrics = [];
        foreach ($apps as $app) {
            app(ReleaseCentre::class)->sync($app);
            $metrics[$app->id] = app(ManagementActivity::class)->metrics($app);
        }

        return view('management.index', compact('apps', 'metrics'));
    }

    public function show(ManagedApp $managedApp)
    {
        app(ReleaseCentre::class)->sync($managedApp);

        return view('management.app', ['app' => $managedApp, 'history' => $managedApp->revisions()->with('actor')->orderByDesc('revision')->paginate(20),
            'metrics' => app(ManagementActivity::class)->metrics($managedApp),
            'releases' => AppRelease::where('managed_app_id', $managedApp->id)->latest()->get(),
            'devices' => AppDevice::where('managed_app_id', $managedApp->id)->where('tester', true)->get()]);
    }

    public function create(Request $request, AppConfiguration $configuration)
    {
        $app = $configuration->create($request->user(), $request->all());

        return redirect()->route('apps.show', $app)->with('status', 'App created. Review and publish its first configuration.');
    }

    private function version(Request $request): int
    {
        return (int) $request->validate(['draft_version' => ['required', 'integer', 'min:1']])['draft_version'];
    }

    public function save(Request $request, ManagedApp $managedApp, AppConfiguration $configuration)
    {
        $configuration->saveDraft($request->user(), $managedApp, $request->all(), $this->version($request));

        return back()->with('status', 'Draft saved. Publish when ready to send it to this app.');
    }

    public function publish(Request $request, ManagedApp $managedApp, AppConfiguration $configuration)
    {
        $configuration->publish($request->user(), $managedApp, $this->version($request));

        return back()->with('status', 'Configuration published.');
    }

    public function rollback(Request $request, ManagedApp $managedApp, int $revision, AppConfiguration $configuration)
    {
        $configuration->rollback($request->user(), $managedApp, $revision, $this->version($request));

        return back()->with('status', 'Previous settings published as a new revision.');
    }

    public function replace(Request $request, ManagedApp $managedApp, AppConfiguration $configuration)
    {
        $request->validate(['confirmation' => ['required', 'in:REPLACE']]);
        $configuration->replaceService($request->user(), $managedApp, $request->all(), $this->version($request));

        return back()->with('status', 'Service replaced. Connected apps will require a new sign-in.');
    }

    public function profile(ManagedApp $managedApp, ConfigSigner $signer)
    {
        $revision = $managedApp->revisions()->where('revision', $managedApp->revision)->firstOrFail();
        $profile = [
            'appId' => $managedApp->app_id,
            'packageId' => $managedApp->package_id,
            'configUrl' => route('config.show', ['appId' => $managedApp->app_id]),
            'verificationKey' => $signer->publicKey(),
            'bootstrap' => $revision->envelope(),
        ];
        abort_unless(str_starts_with($profile['configUrl'], 'https://'), 422, 'Configure HTTPS before exporting a build profile.');

        return response()->json($profile)->header('Content-Disposition', 'attachment; filename="'.$managedApp->app_id.'-profile.json"')->header('Cache-Control', 'private, no-store');
    }

    public function staff(Request $request)
    {
        abort_unless($request->user()->role === 'owner', 403);

        return view('management.staff', ['staff' => User::orderBy('name')->get()]);
    }

    public function addStaff(Request $request)
    {
        abort_unless($request->user()->role === 'owner', 403);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'email' => ['required', 'email', 'max:255', 'unique:users'],
            'password' => ['required', 'confirmed', Password::min(14)->letters()->numbers()],
        ]);
        $user = new User($data);
        $user->role = 'staff';
        $user->email_verified_at = now();
        $user->save();

        ManagementActivity::record(null, 'Staff account created');

        return back()->with('status', 'Staff account created. Share the initial login details privately.');
    }

    public function toggleStaff(Request $request, User $user)
    {
        abort_unless($request->user()->role === 'owner' && $user->role === 'staff', 403);
        DB::transaction(function () use ($user) {
            $user->active = ! $user->active;
            $user->remember_token = null;
            $user->save();
            DB::table('sessions')->where('user_id', $user->id)->delete();
            ManagementActivity::record(null, 'Staff access updated');
        });

        return back()->with('status', 'Staff access updated.');
    }
}
