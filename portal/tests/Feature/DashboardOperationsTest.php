<?php

namespace Tests\Feature;

use App\Models\AppDevice;
use App\Models\AppRelease;
use App\Models\ManagedApp;
use App\Models\User;
use App\Services\AppConfiguration;
use App\Services\DashboardHealth;
use App\Services\ManagementActivity;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\Str;
use Tests\TestCase;

class DashboardOperationsTest extends TestCase
{
    use RefreshDatabase;

    private string $temp;

    private User $owner;

    private ManagedApp $brand;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        Storage::fake('local');
        URL::forceScheme('https');
        $this->temp = sys_get_temp_dir().'/dashboard-'.Str::uuid();
        mkdir($this->temp);
        mkdir($this->temp.'/inbox');
        mkdir($this->temp.'/receipts');
        file_put_contents($this->temp.'/key', sodium_crypto_sign_secretkey(sodium_crypto_sign_keypair()));
        config(['management.signing_key_path' => $this->temp.'/key', 'management.upload_inbox' => $this->temp.'/inbox', 'management.release_receipts' => $this->temp.'/receipts']);
        $this->owner = User::factory()->create(['role' => 'owner']);
        $this->brand = $this->brand('alpha');
        $this->actingAs($this->owner);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->temp);
        parent::tearDown();
    }

    private function brand(string $name): ManagedApp
    {
        $service = app(AppConfiguration::class);
        $app = $service->create($this->owner, ['name' => ucfirst($name).' Player', 'app_id' => $name.'-player', 'package_id' => 'com.example.'.$name,
            'primary' => 'https://'.$name.'.example.test', 'updateManifestUrl' => 'https://updates.example.test/'.$name.'.json']);
        $service->publish($this->owner, $app, 1);

        return $app->fresh();
    }

    private function release(ManagedApp $app, int $code, string $status = 'ready'): AppRelease
    {
        return AppRelease::create(['id' => (string) Str::uuid(), 'managed_app_id' => $app->id, 'status' => $status,
            'manifest' => ['applicationId' => $app->package_id, 'versionName' => '1.0.'.$code, 'versionCode' => $code,
                'releaseNotes' => '- Improved playback.\n- Improved navigation.']])->fresh();
    }

    private function notice(array $ids, string $operation = 'notice-draft'): array
    {
        return ['app_ids' => $ids, 'operation' => $operation, 'noticeTitle' => 'Maintenance',
            'noticeBody' => 'Back shortly.', 'noticeExpiresAt' => now()->addHour()->toIso8601String()];
    }

    public function test_bulk_notice_changes_only_selected_apps_after_review(): void
    {
        $beta = $this->brand('beta');
        $gamma = $this->brand('gamma');
        $response = $this->post(route('operations.bulk.prepare'), $this->notice([$this->brand->id, $beta->id]));
        $response->assertRedirect();
        $url = $response->headers->get('Location');
        $this->get($url)->assertOk()->assertSee('Review 2 selected apps')->assertSee('Alpha Player')->assertSee('Beta Player')->assertDontSee('Gamma Player');
        $this->assertArrayNotHasKey('noticeTitle', $this->brand->fresh()->draft);
        $this->post($url, ['reviewed' => 1])->assertRedirect(route('dashboard'));
        foreach ([$this->brand, $beta] as $app) {
            $fresh = $app->fresh();
            $this->assertSame('Maintenance', $fresh->draft['noticeTitle']);
            $this->assertSame($app->draft['primary'], $fresh->draft['primary']);
            $this->assertSame(1, $fresh->revision);
        }
        $this->assertSame($gamma->draft, $gamma->fresh()->draft);
        $this->post($url, ['reviewed' => 1])->assertSessionHasErrors('review');
    }

    public function test_stale_bulk_review_changes_nothing_on_other_selected_apps(): void
    {
        $beta = $this->brand('beta');
        $url = $this->post(route('operations.bulk.prepare'), $this->notice([$this->brand->id, $beta->id]))->headers->get('Location');
        app(AppConfiguration::class)->saveDraft($this->owner, $beta, [...$beta->draft, 'supportMessage' => 'New help text'], $beta->draft_version);
        $this->post($url, ['reviewed' => 1])->assertStatus(409);
        $this->assertSame($this->brand->draft, $this->brand->fresh()->draft);
    }

    public function test_bulk_publication_refuses_unrelated_pending_changes(): void
    {
        app(AppConfiguration::class)->saveDraft($this->owner, $this->brand, [...$this->brand->draft, 'supportMessage' => 'Not ready to publish'], 2);
        $this->post(route('operations.bulk.prepare'), $this->notice([$this->brand->id], 'notice-publish'))->assertSessionHasErrors('app_ids');
        $this->assertSame(1, $this->brand->fresh()->revision);
    }

    public function test_single_publication_previews_and_consumes_the_review(): void
    {
        app(AppConfiguration::class)->saveDraft($this->owner, $this->brand, [...$this->brand->draft, 'supportMessage' => 'Help changed'], 2);
        $response = $this->post(route('apps.publish', $this->brand), ['draft_version' => 3]);
        $url = $response->headers->get('Location');
        $this->assertSame(1, $this->brand->fresh()->revision);
        $this->get($url)->assertOk()->assertSee('Help changed')->assertSee('existing sign-ins');
        $this->post($url, ['reviewed' => 1])->assertRedirect();
        $this->assertSame(2, $this->brand->fresh()->revision);
    }

    public function test_expired_review_does_not_publish(): void
    {
        $url = $this->post(route('apps.publish', $this->brand), ['draft_version' => 2])->headers->get('Location');
        $this->travel(16)->minutes();
        $this->post($url, ['reviewed' => 1])->assertSessionHasErrors('review');
        $this->assertSame(1, $this->brand->fresh()->revision);
    }

    public function test_replacement_preview_warns_about_sign_in_before_any_service_change(): void
    {
        $previous = $this->brand->service_id;
        $response = $this->withSession(['auth.password_confirmed_at' => time()])->post(route('apps.replace', $this->brand),
            [...$this->brand->draft, 'primary' => 'https://replacement.example.test', 'confirmation' => 'REPLACE', 'draft_version' => 2]);
        $response->assertRedirect();
        $this->get($response->headers->get('Location'))->assertOk()->assertSee('Users will need to sign in again.');
        $this->assertSame($previous, $this->brand->fresh()->service_id);
        $this->post($response->headers->get('Location'), ['reviewed' => 1])->assertRedirect();
        $this->assertNotSame($previous, $this->brand->fresh()->service_id);
    }

    public function test_review_ticket_cannot_be_used_by_another_account(): void
    {
        $url = $this->post(route('apps.publish', $this->brand), ['draft_version' => 2])->headers->get('Location');
        $this->actingAs(User::factory()->create(['role' => 'owner']));
        $this->get($url)->assertSessionHasErrors('review');
        $this->assertSame(1, $this->brand->fresh()->revision);
    }

    public function test_reseller_records_are_owner_only_and_never_in_signed_settings(): void
    {
        $this->post(route('operations.reseller', $this->brand), ['reseller_name' => 'Example Reseller', 'reseller_email' => 'private@example.test', 'downloader_code' => '123456'])->assertRedirect();
        $this->assertSame('123456', $this->brand->fresh()->downloader_code);
        $revision = $this->brand->revisions()->first();
        $payload = sodium_base642bin($revision->payload, SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING);
        $this->assertStringNotContainsString('private@example.test', $payload);
        $this->assertStringNotContainsString('123456', $payload);
        $staff = User::factory()->create(['role' => 'staff']);
        $this->actingAs($staff)->post(route('operations.reseller', $this->brand), ['downloader_code' => '9'])->assertForbidden();
        $this->get(route('apps.show', $this->brand))->assertOk()->assertDontSee('private@example.test');
    }

    public function test_adoption_counts_exact_public_versions_separately_from_test_versions(): void
    {
        $public = $this->release($this->brand, 44, 'published');
        $this->brand->update(['public_release_id' => $public->id]);
        foreach ([43, 44, 44, 45] as $index => $code) {
            AppDevice::create(['managed_app_id' => $this->brand->id, 'secret_hash' => hash('sha256', (string) $index), 'version' => '1', 'build' => $code, 'revision' => 1, 'last_seen_at' => now()]);
        }
        $metrics = app(ManagementActivity::class)->metrics($this->brand);
        $this->assertSame(50.0, $metrics['adoption']);
        $this->assertSame(1, $metrics['older']);
        $this->assertSame(1, $metrics['ahead']);
    }

    public function test_failed_testing_blocks_publication_and_staff_cannot_waive(): void
    {
        $release = $this->release($this->brand, 44);
        $this->post(route('releases.result', [$this->brand, $release]), ['test_result' => 'failed'])->assertRedirect();
        $this->post(route('releases.action', [$this->brand, $release]), ['action' => 'publish', 'reviewed' => 1])->assertSessionHasErrors('release');
        $staff = User::factory()->create(['role' => 'staff']);
        $this->actingAs($staff)->post(route('releases.result', [$this->brand, $release]), ['test_result' => 'not_required', 'test_note' => 'Urgent'])->assertForbidden();
    }

    public function test_bulk_release_review_rejects_changed_test_results(): void
    {
        $release = $this->release($this->brand, 44);
        $this->post(route('releases.result', [$this->brand, $release]), ['test_result' => 'passed'])->assertRedirect();
        $url = $this->post(route('operations.bulk.prepare'), ['app_ids' => [$this->brand->id], 'operation' => 'release-publish', 'releases' => [$this->brand->id => $release->id]])->headers->get('Location');
        $this->post(route('releases.result', [$this->brand, $release]), ['test_result' => 'failed'])->assertRedirect();
        $this->post($url, ['reviewed' => 1])->assertStatus(409);
        $this->assertSame('ready', $release->fresh()->status);
    }

    public function test_health_distinguishes_unknown_stale_and_verified_backup(): void
    {
        $health = app(DashboardHealth::class);
        $this->assertFalse($health->summary()['fresh']);
        file_put_contents($this->temp.'/receipts/health.json', json_encode(['schemaVersion' => 1, 'capturedAt' => now()->toIso8601String(),
            'disk' => ['freeBytes' => 20 * 1024 ** 3, 'totalBytes' => 100 * 1024 ** 3], 'backup' => ['success' => true, 'integrityVerified' => true, 'completedAt' => now()->toIso8601String()]]));
        $this->assertTrue($health->summary()['backupGood']);
        $this->assertTrue($health->summary()['diskGood']);
        $this->travel(6)->minutes();
        $this->assertFalse($health->summary()['fresh']);
        $this->get(route('operations.health'))->assertOk()->assertSee('status is unknown');
    }

    private function logo(): UploadedFile
    {
        $chunk = fn ($type, $data) => pack('N', strlen($data)).$type.$data.pack('N', crc32($type.$data));
        $png = "\x89PNG\r\n\x1a\n".$chunk('IHDR', pack('NNCCCCC', 256, 256, 8, 2, 0, 0, 0))
            .$chunk('IDAT', gzcompress(str_repeat("\0".str_repeat("\x20\x90\xcb", 256), 256))).$chunk('IEND', '');

        return UploadedFile::fake()->createWithContent('logo.png', $png);
    }

    public function test_wizard_creates_only_after_review_and_exports_no_service_settings_in_brand_kit(): void
    {
        $response = $this->post(route('brands.prepare'), ['name' => 'New Example', 'primary' => 'https://new.example.test', 'reseller_email' => 'private@example.test', 'logo' => $this->logo()]);
        $response->assertRedirect();
        $this->assertDatabaseCount('managed_apps', 1);
        $url = $response->headers->get('Location');
        $this->get($url)->assertOk()->assertSee('Review New Example');
        $this->post($url, ['reviewed' => 1])->assertRedirect();
        $brand = ManagedApp::where('name', 'New Example')->firstOrFail();
        $this->assertSame(0, $brand->revision);
        $this->assertStringStartsWith('brand-new-example-', $brand->app_id);
        $this->assertStringStartsWith('https://', $brand->draft['updateManifestUrl']);
        $download = $this->get(route('brands.kit', $brand))->assertOk();
        $path = $download->baseResponse->getFile()->getPathname();
        $zip = new \ZipArchive;
        $zip->open($path);
        $this->assertSame(2, $zip->numFiles);
        $spec = $zip->getFromName('brand.json');
        $this->assertStringNotContainsString('new.example.test', $spec);
        $this->assertStringNotContainsString('private@example.test', $spec);
        $zip->close();
        @unlink($path);
    }

    public function test_staff_cannot_access_owner_operations_or_brand_wizard(): void
    {
        $this->actingAs(User::factory()->create(['role' => 'staff']));
        foreach (['operations.bulk', 'operations.health', 'brands.start'] as $route) {
            $this->get(route($route))->assertForbidden();
        }
        $this->post(route('operations.bulk.prepare'), $this->notice([$this->brand->id]))->assertForbidden();
    }
}
