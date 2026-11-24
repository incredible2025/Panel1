<?php

namespace Tests\Feature;

use App\Models\AppDevice;
use App\Models\AppRelease;
use App\Models\ManagedApp;
use App\Models\User;
use App\Services\AppConfiguration;
use App\Services\DashboardAlerts;
use App\Services\ManagementActivity;
use App\Services\PlaybackReports;
use App\Services\PlaybackSessions;
use App\Services\ReleaseCentre;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
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

    private function playback(array $changes = []): array
    {
        return array_replace(['event_id' => (string) Str::uuid(), 'version' => '1.0.0', 'build' => 44,
            'device_model' => 'Example TV', 'os_version' => 'Android 14', 'form_factor' => 'tv',
            'engine' => 'vlc', 'decoding' => 'hardware', 'kind' => 'live', 'category' => 'decoder', 'source' => 'automatic'], $changes);
    }

    public function test_playback_reports_are_deduplicated_and_store_only_allowed_fields(): void
    {
        $this->beat();
        $data = $this->playback();
        $data['url'] = 'https://private.example.test/secret';
        $data['error'] = 'private-error';
        $url = '/api/v1/apps/example-player/playback';
        $this->withToken(str_repeat('a', 64))->postJson($url, $data)->assertNoContent();
        $this->postJson($url, $data)->assertNoContent();
        $this->assertDatabaseCount('playback_events', 1);
        $stored = (array) DB::table('playback_events')->first();
        $this->assertArrayNotHasKey('url', $stored);
        $this->assertArrayNotHasKey('error', $stored);
        $this->actingAs($this->owner)->get(route('playback.index'))->assertOk()->assertSee('Example TV')->assertSee('Decoder or codec error');
    }

    public function test_playback_reports_reject_cross_app_devices_raw_errors_and_false_manual_sources(): void
    {
        $this->beat();
        $url = '/api/v1/apps/example-player/playback';
        $this->withToken(str_repeat('b', 64))->postJson($url, $this->playback())->assertNotFound();
        $this->withToken(str_repeat('a', 64))->postJson($url, $this->playback(['category' => 'https://private.example.test']))->assertUnprocessable();
        $this->postJson($url, $this->playback(['category' => 'green_screen']))->assertUnprocessable();
        $this->postJson($url, $this->playback(['device_model' => 'https://private.example.test']))->assertUnprocessable();
        $this->postJson($url, $this->playback(['category' => 'green_screen', 'source' => 'user']))->assertNoContent();
        $this->assertDatabaseCount('playback_events', 1);
        $this->get(route('playback.index'))->assertRedirect(route('login'));
    }

    public function test_playback_reports_expire_and_alert_filter_finds_affected_apps(): void
    {
        $this->beat();
        for ($i = 0; $i < 5; $i++) {
            $this->withToken(str_repeat('a', 64))->postJson('/api/v1/apps/example-player/playback', $this->playback())->assertNoContent();
        }
        $this->actingAs($this->owner)->get(route('dashboard', ['attention' => 1]))->assertOk()->assertSee('5 playback reports from 1 installations');
        $this->get(route('dashboard', ['q' => 'missing']))->assertOk()->assertSee('No apps match these filters.');
        $this->travel(31)->days();
        $this->artisan('management:housekeeping')->assertSuccessful();
        $this->assertDatabaseCount('playback_events', 0);
    }

    public function test_playback_rate_limit_and_stale_health_do_not_claim_current_failures(): void
    {
        $this->beat();
        for ($i = 0; $i < 12; $i++) {
            $this->withToken(str_repeat('a', 64))->postJson('/api/v1/apps/example-player/playback', $this->playback())->assertNoContent();
        }
        $this->postJson('/api/v1/apps/example-player/playback', $this->playback())->assertStatus(429);
        $metrics = app(ManagementActivity::class)->metrics($this->brand);
        $health = ['fresh' => false, 'snapshot' => ['apps' => ['example-player' => ['download' => ['checked' => true, 'ok' => false]]]]];
        $alerts = app(DashboardAlerts::class)->forApp($this->brand, $metrics, $health);
        $this->assertNotContains('APK download check failed', $alerts);
    }

    public function test_operational_alerts_cover_expiring_certificates_and_delayed_adoption(): void
    {
        $release = $this->release(45, 'published');
        $this->brand->update(['public_release_id' => $release->id]);
        $this->beat();
        $health = ['fresh' => true, 'snapshot' => ['apps' => ['example-player' => [
            'download' => ['checked' => true, 'ok' => false],
            'certificate' => ['checked' => true, 'ok' => true, 'daysRemaining' => 12],
        ]]]];
        $metrics = app(ManagementActivity::class)->metrics($this->brand);
        $alerts = app(DashboardAlerts::class)->forApp($this->brand, $metrics, $health);
        $this->assertContains('APK download check failed', $alerts);
        $this->assertContains('Download certificate expires within 21 days', $alerts);
        $this->assertCount(2, $alerts);
        $this->travel(8)->days();
        $alerts = app(DashboardAlerts::class)->forApp($this->brand, $metrics, $health);
        $this->assertContains('1 reporting devices still on older builds', $alerts);
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

    private function richEvent(string $session, int $sequence, string $category, array $details = [], string $engine = 'native'): array
    {
        return $this->playback(['schema_version' => 2, 'session_id' => $session, 'sequence' => $sequence,
            'elapsed_ms' => $sequence * 1000, 'occurred_at' => now()->toIso8601String(), 'category' => $category, 'engine' => $engine, 'details' => $details]);
    }

    public function test_rich_timeline_orders_events_and_counts_recovery_across_players(): void
    {
        $this->beat();
        $session = (string) Str::uuid();
        $url = '/api/v1/apps/example-player/playback';
        foreach ([
            $this->richEvent($session, 2, 'decoder', ['cause' => 'decoder', 'native_code' => 'ERROR_CODE_DECODER_INIT_FAILED', 'video_codec' => 'hevc']),
            $this->richEvent($session, 1, 'started'),
            $this->richEvent($session, 3, 'playing', ['actual_decoding' => 'software'], 'compatibility'),
        ] as $event) {
            $this->withToken(str_repeat('a', 64))->postJson($url, $event)->assertNoContent();
        }
        $this->postJson($url, $this->richEvent($session, 2, 'decoder'))->assertNoContent();
        $this->assertDatabaseCount('playback_events', 3);
        $this->actingAs($this->owner)->get(route('playback.index', ['engine' => 'native', 'codec' => 'hevc', 'outcome' => 'recovered']))
            ->assertOk()->assertSee('Recovery observed')->assertSee('ERROR_CODE_DECODER_INIT_FAILED');
        $sessions = app(PlaybackSessions::class);
        $stats = $sessions->statistics($sessions->events($this->brand->id, 7, ['codec' => 'hevc', 'engine' => 'native']));
        $this->assertSame(['sessions' => 1, 'affected' => 1, 'playing' => 1, 'recovered' => 1], $stats);
        $device = AppDevice::first();
        $page = $this->get(route('playback.session', [$device->id, $session]))->assertOk();
        $page->assertSeeInOrder(['Playback attempt started', 'Decoder or codec error', 'Playback progress observed']);
        $this->beat('b');
        $other = AppDevice::where('secret_hash', hash('sha256', str_repeat('b', 64)))->first();
        $this->get(route('playback.session', [$other->id, $session]))->assertNotFound();
    }

    public function test_rich_evidence_rejects_private_payloads_and_non_error_events_do_not_raise_alerts(): void
    {
        $this->beat();
        $session = (string) Str::uuid();
        $url = '/api/v1/apps/example-player/playback';
        $this->withToken(str_repeat('a', 64))->postJson($url, $this->richEvent($session, 1, 'decoder', ['url' => 'https://private.example.test']))->assertUnprocessable();
        $this->postJson($url, $this->richEvent($session, 2, 'decoder', ['decoder' => 'https://private.example.test']))->assertUnprocessable();
        for ($i = 1; $i <= 6; $i++) {
            $this->postJson($url, $this->richEvent($session, $i, 'started'))->assertNoContent();
        }
        $this->assertSame(0, app(PlaybackReports::class)->summary($this->brand->id)['events']);
        $alerts = app(DashboardAlerts::class)->forApp($this->brand, app(ManagementActivity::class)->metrics($this->brand), ['fresh' => false]);
        $this->assertSame([], $alerts);
    }

    public function test_user_diagnosis_is_searchable_and_its_nested_fields_are_validated(): void
    {
        $this->beat();
        $session = (string) Str::uuid();
        $event = $this->richEvent($session, 1, 'diagnosis', ['checks' => [['stage' => 'dns', 'code' => 'DNS_TIMEOUT', 'status' => 'failed', 'elapsed_ms' => 8000]]]);
        $event = array_replace($event, ['source' => 'user', 'engine' => 'none', 'decoding' => 'none', 'kind' => 'none']);
        $this->withToken(str_repeat('a', 64))->postJson('/api/v1/apps/example-player/playback', $event)->assertNoContent();
        $this->actingAs($this->owner)->get(route('playback.index', ['reference' => 'D-'.strtoupper(substr($session, 0, 8))]))->assertOk()->assertSee('Example TV');
        $device = AppDevice::first();
        $this->get(route('playback.session', [$device->id, $session]))->assertOk()->assertSee('DNS TIMEOUT');
        $event['details']['checks'][0]['message'] = 'private';
        $this->withToken(str_repeat('a', 64))->postJson('/api/v1/apps/example-player/playback', $event)->assertUnprocessable();
    }

    public function test_a_wrong_device_clock_does_not_discard_the_failure_report(): void
    {
        $this->beat();
        $event = $this->richEvent((string) Str::uuid(), 1, 'certificate', ['cause' => 'tls']);
        $event['occurred_at'] = now()->addYear()->toIso8601String();
        $this->withToken(str_repeat('a', 64))->postJson('/api/v1/apps/example-player/playback', $event)->assertNoContent();
        $row = DB::table('playback_events')->first();
        $this->assertNull($row->occurred_at);
        $this->assertTrue(json_decode($row->details, true)['device_clock_untrusted']);
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
