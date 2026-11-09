<?php

namespace App\Services;

use App\Models\ConfigRevision;
use App\Models\ManagedApp;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class AppConfiguration
{
    public function __construct(private ConfigSigner $signer) {}

    public function validate(array $input): array
    {
        $data = Validator::make($input, [
            'primary' => ['required', 'string', 'max:2048'],
            'fallback' => ['nullable', 'string', 'max:2048', 'different:primary'],
            'updateManifestUrl' => ['required', 'string', 'max:2048'],
        ])->validate();
        foreach (['primary', 'fallback', 'updateManifestUrl'] as $field) {
            $value = trim($data[$field] ?? '');
            if ($field === 'fallback' && $value === '') {
                $data[$field] = null;

                continue;
            }
            $parts = parse_url($value);
            $schemes = $field === 'updateManifestUrl' ? ['https'] : ['https', 'http'];
            if (! $parts || ! in_array($parts['scheme'] ?? '', $schemes, true)
                || empty($parts['host']) || isset($parts['user']) || isset($parts['pass'])
                || isset($parts['query']) || isset($parts['fragment'])
                || preg_match('/[\x00-\x20\\\\]/', $value)
                || filter_var($value, FILTER_VALIDATE_URL) === false) {
                throw ValidationException::withMessages([$field => 'Enter a valid address without credentials, query parameters or fragments. Update feeds require HTTPS.']);
            }
            $data[$field] = $field === 'updateManifestUrl' ? $value : rtrim($value, '/');
        }
        if ($data['primary'] === $data['fallback']) {
            throw ValidationException::withMessages(['fallback' => 'Choose a different fallback address.']);
        }

        return $data;
    }

    public function create(User $actor, array $input): ManagedApp
    {
        abort_unless($actor->active && $actor->role === 'owner', 403);
        $identity = Validator::make($input, [
            'name' => ['required', 'string', 'max:100'],
            'app_id' => ['required', 'regex:/^[a-z][a-z0-9-]{2,63}$/', 'unique:managed_apps'],
            'package_id' => ['required', 'max:180', 'regex:/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$/', 'unique:managed_apps'],
        ])->validate();

        return ManagedApp::create([...$identity, 'service_id' => (string) Str::uuid(), 'draft' => $this->validate($input)]);
    }

    private function locked(ManagedApp $app): ManagedApp
    {
        return ManagedApp::query()->lockForUpdate()->findOrFail($app->id);
    }

    private function check(User $actor, ManagedApp $app, int $draftVersion): void
    {
        abort_unless($actor->active && in_array($actor->role, ['owner', 'staff'], true), 403);
        if ($app->draft_version !== $draftVersion) {
            throw ValidationException::withMessages(['conflict' => 'Someone changed this app. Reload before saving or publishing.']);
        }
    }

    public function saveDraft(User $actor, ManagedApp $app, array $input, int $version): void
    {
        DB::transaction(function () use ($actor, $app, $input, $version) {
            $locked = $this->locked($app);
            $this->check($actor, $locked, $version);
            $locked->update(['draft' => $this->validate($input), 'draft_version' => $version + 1]);
        });
    }

    public function publish(User $actor, ManagedApp $app, int $version): ConfigRevision
    {
        return DB::transaction(function () use ($actor, $app, $version) {
            $locked = $this->locked($app);
            $this->check($actor, $locked, $version);

            return $this->record($actor, $locked, $this->validate($locked->draft), $locked->service_id, 'publish');
        });
    }

    public function rollback(User $actor, ManagedApp $app, int $revision, int $version): ConfigRevision
    {
        return DB::transaction(function () use ($actor, $app, $revision, $version) {
            $locked = $this->locked($app);
            $this->check($actor, $locked, $version);
            $old = $locked->revisions()->where('revision', $revision)->firstOrFail();
            abort_unless($old->service_id === $locked->service_id || $actor->role === 'owner', 403);

            return $this->record($actor, $locked, $old->configuration, $old->service_id, 'rollback');
        });
    }

    public function replaceService(User $actor, ManagedApp $app, array $input, int $version): ConfigRevision
    {
        abort_unless($actor->role === 'owner', 403);

        return DB::transaction(function () use ($actor, $app, $input, $version) {
            $locked = $this->locked($app);
            $this->check($actor, $locked, $version);

            return $this->record($actor, $locked, $this->validate($input), (string) Str::uuid(), 'replace-service');
        });
    }

    private function record(User $actor, ManagedApp $app, array $draft, string $serviceId, string $action): ConfigRevision
    {
        $revision = $app->revision + 1;
        $payload = [
            'schemaVersion' => 1,
            'appId' => $app->app_id,
            'packageId' => $app->package_id,
            'serviceId' => $serviceId,
            'revision' => $revision,
            'endpoints' => array_values(array_filter([$draft['primary'], $draft['fallback'] ?? null])),
            'updateManifestUrl' => $draft['updateManifestUrl'],
            'issuedAt' => now()->utc()->toIso8601String(),
        ];
        $signed = $this->signer->sign($payload);
        $result = $app->revisions()->create([
            'revision' => $revision, 'service_id' => $serviceId,
            'configuration' => $draft, ...$signed, 'user_id' => $actor->id,
            'action' => $action, 'created_at' => now(),
        ]);
        $app->update(['revision' => $revision, 'service_id' => $serviceId, 'draft' => $draft, 'draft_version' => $app->draft_version + 1]);

        return $result;
    }
}
