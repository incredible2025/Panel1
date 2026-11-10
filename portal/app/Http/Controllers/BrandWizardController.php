<?php

namespace App\Http\Controllers;

use App\Models\ManagedApp;
use App\Services\AppConfiguration;
use App\Services\DashboardReview;
use App\Services\ManagementActivity;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class BrandWizardController extends Controller
{
    private function owner(Request $request): void
    {
        abort_unless($request->user()->role === 'owner', 403);
    }

    private function logoRules(): array
    {
        return ['image', 'mimes:png,jpg,jpeg,webp', 'max:4096', 'dimensions:min_width=256,min_height=256,max_width=2048,max_height=2048'];
    }

    private function logo($file): string
    {
        return $file->storeAs('brand-assets', Str::uuid().'.'.$file->extension(), 'local');
    }

    public function start(Request $request)
    {
        $this->owner($request);

        return view('management.wizard');
    }

    public function prepare(Request $request)
    {
        $this->owner($request);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:48', 'regex:/^[^\x00-\x1f\x7f]+$/u'],
            'title' => ['nullable', 'string', 'max:24', 'regex:/^[^\x00-\x1f\x7f]+$/u'],
            'subtitle' => ['nullable', 'string', 'max:23', 'regex:/^[^\x00-\x1f\x7f]+$/u'],
            'logo' => ['nullable', ...$this->logoRules()],
            ...DashboardOperationsController::resellerRules(),
        ]);
        $id = 'brand-'.substr(Str::slug($data['name']) ?: 'player', 0, 36).'-'.Str::lower(Str::random(6));
        $package = 'com.streamline.brand.b'.Str::lower(Str::random(12));
        $settings = app(AppConfiguration::class)->validate([
            ...$request->all(), 'updateManifestUrl' => route('device.updates', ['appId' => $id]),
        ]);
        $stable = (substr(Str::slug($data['name']) ?: $id, 0, 60)).'.apk';
        $title = ($data['title'] ?? null) ?: Str::upper(Str::substr($data['name'], 0, 24));
        $subtitle = ($data['subtitle'] ?? null) ?: 'PLAYER';
        $logo = $request->hasFile('logo') ? $this->logo($request->file('logo')) : null;
        $spec = ['appId' => $id, 'packageId' => $package, 'name' => $data['name'], 'title' => $title,
            'subtitle' => $subtitle, 'wordmark' => $title.' '.$subtitle, 'versionName' => '1.0.0', 'versionCode' => 1,
            'stableApkName' => $stable, 'logo' => 'logo.'.($logo ? pathinfo($logo, PATHINFO_EXTENSION) : 'png')];
        $contacts = array_intersect_key($data, DashboardOperationsController::resellerRules());
        $ticket = app(DashboardReview::class)->store($request, 'wizard', compact('settings', 'spec', 'contacts', 'logo'));

        return redirect()->route('brands.review', $ticket);
    }

    private function plan(Request $request, string $ticket): array
    {
        $this->owner($request);
        $plan = app(DashboardReview::class)->get($request, $ticket);
        abort_unless($plan['kind'] === 'wizard', 404);

        return $plan['data'];
    }

    public function review(Request $request, string $ticket)
    {
        return view('management.wizard-review', ['plan' => $this->plan($request, $ticket), 'ticket' => $ticket]);
    }

    public function previewLogo(Request $request, string $ticket)
    {
        $data = $this->plan($request, $ticket);
        abort_unless($data['logo'] && Storage::disk('local')->exists($data['logo']), 404);

        return Storage::disk('local')->response($data['logo'], null, ['X-Content-Type-Options' => 'nosniff']);
    }

    public function create(Request $request, string $ticket)
    {
        $data = $this->plan($request, $ticket);
        $request->validate(['reviewed' => ['accepted']]);
        $brand = DB::transaction(function () use ($request, $data) {
            $app = app(AppConfiguration::class)->create($request->user(), [...$data['settings'],
                'name' => $data['spec']['name'], 'app_id' => $data['spec']['appId'], 'package_id' => $data['spec']['packageId']]);
            $app->update([...$data['contacts'], 'brand_spec' => $data['spec'], 'brand_logo' => $data['logo']]);
            ManagementActivity::record($app->id, 'Brand setup wizard completed');

            return $app;
        });
        app(DashboardReview::class)->forget($request, $ticket);

        return redirect()->route('apps.show', $brand)->with('status', 'Brand draft created. Follow the first-build checklist to produce its APK.');
    }

    public function uploadLogo(Request $request, ManagedApp $managedApp)
    {
        $this->owner($request);
        abort_unless($managedApp->brand_spec, 422);
        $request->validate(['logo' => ['required', ...$this->logoRules()]]);
        $path = $this->logo($request->file('logo'));
        $spec = $managedApp->brand_spec;
        $spec['logo'] = 'logo.'.pathinfo($path, PATHINFO_EXTENSION);
        $managedApp->update(['brand_logo' => $path, 'brand_spec' => $spec]);
        ManagementActivity::record($managedApp->id, 'Build artwork updated');

        return back()->with('status', 'Build artwork saved. Installed app icons change only through a new branded APK.');
    }

    public function kit(Request $request, ManagedApp $managedApp)
    {
        $this->owner($request);
        abort_unless($managedApp->brand_spec && $managedApp->brand_logo && Storage::disk('local')->exists($managedApp->brand_logo), 422, 'Add build artwork before downloading the branding kit.');
        $temp = tempnam(storage_path('app/private'), 'brand-kit-');
        $zip = new \ZipArchive;
        if ($zip->open($temp, \ZipArchive::CREATE | \ZipArchive::OVERWRITE) !== true) {
            @unlink($temp);
            abort(500, 'Branding download could not be prepared.');
        }
        $zip->addFromString('brand.json', json_encode($managedApp->brand_spec, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));
        $zip->addFile(Storage::disk('local')->path($managedApp->brand_logo), $managedApp->brand_spec['logo']);
        $zip->close();

        return response()->download($temp, $managedApp->app_id.'-initial-branding.zip', ['Cache-Control' => 'private, no-store'])->deleteFileAfterSend(true);
    }
}
