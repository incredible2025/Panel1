<?php

namespace Tests\Feature;

use App\Models\AppDevice;
use App\Models\AppRelease;
use App\Models\ManagedApp;
use App\Models\User;
use App\Services\AppConfiguration;
use App\Services\ManagementActivity;
use App\Services\ReleaseCentre;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Str;
use Tests\TestCase;

class RemoteManagementTest extends TestCase
{
    use RefreshDatabase;

    private string $temporary;

    private User $owner;

    private ManagedApp $brand;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->temporary = sys_get_temp_dir().'/management-'.Str::uuid();
        mkdir($this->temporary);
        mkdir($this->temporary.'/inbox');
        mkdir($this->temporary.'/receipts');
        file_put_contents($this->temporary.'/key', sodium_crypto_sign_secretkey(sodium_crypto_sign_keypair()));
        config(['management.signing_key_path' => $this->temporary.'/key', 'management.upload_inbox' => $this->temporary.'/inbox',
            'management.release_receipts' => $this->temporary.'/receipts']);
        $this->owner = User::factory()->create(['role' => 'owner']);
        $this->brand = app(AppConfiguration::class)->create($this->owner, [
            'name' => 'Example Player', 'app_id' => 'example-player', 'package_id' => 'com.example.player',
            'primary' => 'https://service.example.test', 'updateManifestUrl' => 'https://updates.example.test/update.json',
        ]);
        app(AppConfiguration::class)->publish($this->owner, $this->brand, 1);
        $this->brand->refresh();
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->temporary);
        parent::tearDown();
    }

    private function beat(string $secret = 'a'): void
    {
        $this->withToken(str_repeat($secret, 64))->postJson('/api/v1/apps/example-player/activity',
            ['version' => '1.0.0', 'build' => 44, 'revision' => $this->brand->revision])->assertNoContent();
    }

    private function release(int $build, string $status = 'ready'): AppRelease
    {
        return AppRelease::create(['id' => (string) Str::uuid(), 'managed_app_id' => $this->brand->id,
            'status' => $status, 'manifest' => ['schemaVersion' => 1, 'applicationId' => $this->brand->package_id,
                'versionCode' => $build, 'versionName' => '1.0.'.$build, 'apkUrl' => 'https://downloads.example.test/player-'.$build.'.apk',
                'sizeBytes' => 100, 'minSdk' => 24, 'sha256' => str_repeat('a', 64), 'releaseNotes' => '- Improved playback.\n- Improved navigation.']]);
    }

    public function test_heartbeats_deduplicate_and_do_not_store_customer_information(): void
    {
        $this->beat();
        $this->beat();
        $this->assertDatabaseCount('app_devices', 1);
        $device = AppDevice::first();
        $this->assertSame(hash('sha256', str_repeat('a', 64)), $device->secret_hash);
        $this->assertArrayNotHasKey('secret_hash', $device->toArray());
        $this->assertNull($device->getAttribute('ip'));
        $this->assertSame(1, app(ManagementActivity::class)->metrics($this->brand)['online']);
        $this->travel(4)->minutes();
        $metrics = app(ManagementActivity::class)->metrics($this->brand);
        $this->assertSame(0, $metrics['online']);
        $this->assertSame(1, $metrics['today']);
    }

    public function test_daily_counts_and_housekeeping_expire_records(): void
    {
        $this->travelTo(now()->startOfDay()->addHour());
        $this->beat();
        $this->travel(1)->days();
        $this->assertSame(0, app(ManagementActivity::class)->metrics($this->brand)['today']);
        $this->travel(30)->days();
        $this->artisan('management:housekeeping')->assertSuccessful();
        $this->assertDatabaseCount('app_devices', 0);
    }

    public function test_revision_acknowledgement_is_bounded_and_tracks_pending_settings(): void
    {
        $this->beat();
        $this->brand->update(['revision' => 2]);
        $metrics = app(ManagementActivity::class)->metrics($this->brand);
        $this->assertSame(0, $metrics['current']);
        $this->assertSame(1, $metrics['pending']);
        $this->withToken(str_repeat('b', 64))->postJson('/api/v1/apps/example-player/activity',
            ['version' => '1', 'build' => 44, 'revision' => 100])->assertUnprocessable();
    }

    public function test_pairing_is_owner_only_one_use_and_app_scoped(): void
    {
        $this->beat();
        $code = $this->withToken(str_repeat('a', 64))->postJson('/api/v1/apps/example-player/pair')->assertOk()->json('code');
        $staff = User::factory()->create(['role' => 'staff']);
        $this->actingAs($staff)->post(route('devices.pair', $this->brand), ['code' => $code, 'label' => 'TV'])->assertForbidden();
        $this->actingAs($this->owner)->post(route('devices.pair', $this->brand), ['code' => $code, 'label' => 'Living room TV'])->assertRedirect();
        $this->assertTrue(AppDevice::first()->tester);
        $this->post(route('devices.pair', $this->brand), ['code' => $code, 'label' => 'Other'])->assertSessionHasErrors('code');
        $this->post(route('devices.revoke', [$this->brand, AppDevice::first()]))->assertRedirect();
        $this->assertFalse(AppDevice::first()->tester);
    }

    public function test_pairing_expires_and_heartbeats_are_rate_limited(): void
    {
        $this->beat();
        $code = $this->withToken(str_repeat('a', 64))->postJson('/api/v1/apps/example-player/pair')->json('code');
        $this->travel(11)->minutes();
        $this->actingAs($this->owner)->post(route('devices.pair', $this->brand), ['code' => $code, 'label' => 'TV'])->assertSessionHasErrors('code');
        for ($i = 0; $i < 6; $i++) {
            $this->beat('b');
        }
        $this->withToken(str_repeat('b', 64))->postJson('/api/v1/apps/example-player/activity', ['version' => '1', 'build' => 44, 'revision' => 1])->assertStatus(429);
    }

    public function test_test_feed_is_private_and_public_feed_remains_compatible(): void
    {
        $public = $this->release(44, 'published');
        $test = $this->release(45, 'testing');
        $this->brand->update(['public_release_id' => $public->id, 'test_release_id' => $test->id]);
        $this->getJson('/api/v1/apps/example-player/updates')->assertOk()->assertJsonPath('versionCode', 44)
            ->assertHeader('Vary', 'Authorization');
        $this->beat();
        AppDevice::first()->update(['tester' => true]);
        $this->withToken(str_repeat('a', 64))->getJson('/api/v1/apps/example-player/updates')->assertJsonPath('versionCode', 45);
        AppDevice::first()->update(['tester' => false]);
        $this->getJson('/api/v1/apps/example-player/updates')->assertJsonPath('versionCode', 44);
        $this->assertStringContainsString('no-store', $this->getJson('/api/v1/apps/example-player/updates')->headers->get('Cache-Control'));
    }

    public function test_staff_can_upload_but_cannot_publish_releases_or_read_audit_log(): void
    {
        $staff = User::factory()->create(['role' => 'staff']);
        $this->actingAs($staff)->post(route('releases.upload', $this->brand), ['bundle' => UploadedFile::fake()->create('package.zip', 1, 'application/zip')])->assertRedirect();
        $this->assertDatabaseCount('app_releases', 1);
        $this->assertCount(1, glob($this->temporary.'/inbox/*.ready.json'));
        $release = $this->release(44);
        $this->post(route('releases.action', [$this->brand, $release]), ['action' => 'publish'])->assertForbidden();
        $this->get(route('management.events'))->assertForbidden();
    }

    public function test_release_preparation_and_publication_receipts_are_scoped_and_recoverable(): void
    {
        $release = $this->release(44, 'queued');
        $path = $this->temporary.'/receipts/'.$release->id.'.json';
        $receipt = ['ticket' => $release->id, 'appId' => 'wrong-brand', 'status' => 'ready', 'manifest' => $release->manifest];
        file_put_contents($path, json_encode($receipt));
        app(ReleaseCentre::class)->sync($this->brand);
        $this->assertSame('queued', $release->fresh()->status);
        $receipt['appId'] = $this->brand->app_id;
        file_put_contents($path, json_encode($receipt));
        app(ReleaseCentre::class)->sync($this->brand);
        $this->assertSame('ready', $release->fresh()->status);
        $release->update(['test_result' => 'passed']);
        $this->actingAs($this->owner)->post(route('releases.action', [$this->brand, $release]), ['action' => 'publish', 'reviewed' => 1])->assertRedirect();
        $this->assertSame('publishing', $release->fresh()->status);
        $this->assertNull($this->brand->fresh()->public_release_id);
        $receipt['status'] = 'published';
        file_put_contents($path, json_encode($receipt));
        app(ReleaseCentre::class)->sync($this->brand);
        $this->assertSame($release->id, $this->brand->fresh()->public_release_id);
    }

    public function test_dashboard_and_audit_render_without_leaking_device_secrets(): void
    {
        $this->beat();
        $this->actingAs($this->owner)->get(route('dashboard'))->assertOk()->assertSee('Online across apps')->assertDontSee(str_repeat('a', 64));
        $this->get(route('apps.show', $this->brand))->assertOk()->assertSee('Release centre')->assertSee('Reported versions');
        $this->get(route('activity.metrics'))->assertOk()->assertJsonPath('apps.'.$this->brand->id.'.online', 1);
        $this->get(route('management.events'))->assertOk()->assertDontSee('service.example.test');
    }

    public function test_notice_and_support_are_signed_and_published_with_configuration(): void
    {
        $service = app(AppConfiguration::class);
        $draft = [...$this->brand->draft, 'noticeTitle' => 'Scheduled maintenance', 'noticeBody' => 'We will return shortly.',
            'noticeExpiresAt' => now()->addHour()->toIso8601String(), 'supportEmail' => 'help@example.test', 'supportWebsite' => 'https://help.example.test', 'supportMessage' => 'Contact our team.'];
        $service->saveDraft($this->owner, $this->brand, $draft, 2);
        $revision = $service->publish($this->owner, $this->brand, 3);
        $data = json_decode(sodium_base642bin($revision->payload, SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING), true);
        $this->assertSame('Scheduled maintenance', $data['notice']['title']);
        $this->assertSame('help@example.test', $data['support']['email']);
    }

    public function test_failed_inbox_jobs_without_receipts_do_not_loop_forever(): void
    {
        $release = $this->release(44, 'queued');
        file_put_contents($this->temporary.'/inbox/'.$release->id.'.prepare.ready.failed', '{}');
        app(ReleaseCentre::class)->sync($this->brand);
        $this->assertSame('failed', $release->fresh()->status);
        $this->assertCount(0, glob($this->temporary.'/inbox/*.ready.json'));
    }
}
