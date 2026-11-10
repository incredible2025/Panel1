<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\AppConfiguration;
use App\Services\ConfigSigner;
use App\Services\OwnerInvitation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

class ManagementTest extends TestCase
{
    use RefreshDatabase;

    private string $keyPath;

    protected function setUp(): void
    {
        parent::setUp();
        $this->keyPath = tempnam(sys_get_temp_dir(), 'portal-key');
        file_put_contents($this->keyPath, sodium_crypto_sign_secretkey(sodium_crypto_sign_keypair()));
        config(['management.signing_key_path' => $this->keyPath]);
        $this->withoutVite();
    }

    protected function tearDown(): void
    {
        @unlink($this->keyPath);
        parent::tearDown();
    }

    private function owner(): User
    {
        return User::factory()->create(['role' => 'owner', 'two_factor_secret' => encrypt('secret'), 'two_factor_confirmed_at' => now()]);
    }

    private function settings(): array
    {
        return ['name' => 'Example Brand', 'app_id' => 'example-brand', 'package_id' => 'com.example.player', 'primary' => 'https://primary.example.test', 'fallback' => 'http://backup.example.test', 'updateManifestUrl' => 'https://updates.example.test/update.json'];
    }

    public function test_publish_is_signed_and_draft_is_not_public_until_published(): void
    {
        $owner = $this->owner();
        $service = app(AppConfiguration::class);
        $app = $service->create($owner, $this->settings());
        $this->get('/api/v1/apps/example-brand/config')->assertNotFound();
        $revision = $service->publish($owner, $app, 1);
        $response = $this->get('/api/v1/apps/example-brand/config')->assertOk()->assertExactJson($revision->envelope());
        $envelope = $response->json();
        $response->assertCookieMissing(config('session.cookie'));
        $bytes = sodium_base642bin($envelope['payload'], SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING);
        $public = sodium_base642bin(app(ConfigSigner::class)->publicKey(), SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING);
        $this->assertTrue(sodium_crypto_sign_verify_detached(sodium_base642bin($envelope['signature'], SODIUM_BASE64_VARIANT_URLSAFE_NO_PADDING), $bytes, $public));
        $payload = json_decode($bytes, true);
        $this->assertSame('example-brand', $payload['appId']);
        $this->assertSame('com.example.player', $payload['packageId']);
        $this->assertSame(1, $payload['revision']);
        $this->withHeaders(['If-None-Match' => $response->headers->get('ETag')])->get('/api/v1/apps/example-brand/config')->assertStatus(304);
        $this->flushHeaders();
        $service->saveDraft($owner, $app, [...$this->settings(), 'primary' => 'https://moved.example.test'], 2);
        $this->get('/api/v1/apps/example-brand/config')->assertJsonPath('payload', $envelope['payload']);
    }

    public function test_rollback_creates_new_revision_and_preserves_service_identity(): void
    {
        $owner = $this->owner();
        $service = app(AppConfiguration::class);
        $app = $service->create($owner, $this->settings());
        $first = $service->publish($owner, $app, 1);
        $service->saveDraft($owner, $app, [...$this->settings(), 'primary' => 'https://moved.example.test'], 2);
        $service->publish($owner, $app, 3);
        $rollback = $service->rollback($owner, $app, 1, 4);
        $this->assertSame(3, $rollback->revision);
        $this->assertSame($first->service_id, $rollback->service_id);
        $this->assertSame($first->configuration, $rollback->configuration);
    }

    public function test_stale_edit_cannot_overwrite_a_newer_draft(): void
    {
        $owner = $this->owner();
        $service = app(AppConfiguration::class);
        $app = $service->create($owner, $this->settings());
        $service->saveDraft($owner, $app, $this->settings(), 1);
        $this->expectException(ValidationException::class);
        $service->publish($owner, $app, 1);
    }

    public function test_apps_are_isolated_and_replacing_service_changes_only_its_identity(): void
    {
        $owner = $this->owner();
        $service = app(AppConfiguration::class);
        $one = $service->create($owner, $this->settings());
        $two = $service->create($owner, [...$this->settings(), 'app_id' => 'other-brand', 'package_id' => 'com.example.other']);
        $service->publish($owner, $one, 1);
        $other = $service->publish($owner, $two, 1);
        $replacement = $service->replaceService($owner, $one, $this->settings(), 2);
        $this->assertNotSame($one->service_id, $replacement->service_id);
        $this->assertSame(2, $replacement->revision);
        $this->assertSame(1, $two->fresh()->revision);
        $this->get('/api/v1/apps/other-brand/config')->assertExactJson($other->envelope());
    }

    public function test_staff_cannot_create_apps_replace_services_or_manage_staff(): void
    {
        $staff = User::factory()->create(['two_factor_secret' => encrypt('secret'), 'two_factor_confirmed_at' => now()]);
        $app = app(AppConfiguration::class)->create($this->owner(), $this->settings());
        $this->actingAs($staff)->post('/apps', $this->settings())->assertForbidden();
        $this->get('/staff')->assertForbidden();
        $this->withSession(['auth.password_confirmed_at' => time()])->post('/apps/'.$app->id.'/replace', [...$this->settings(), 'confirmation' => 'REPLACE', 'draft_version' => 1])->assertForbidden();
        $review = $this->post('/apps/'.$app->id.'/publish', ['draft_version' => 1])->assertRedirect();
        $this->assertSame(0, $app->fresh()->revision);
        $this->post($review->headers->get('Location'), ['reviewed' => 1])->assertRedirect();
        $this->assertSame(1, $app->fresh()->revision);
    }

    public function test_inactive_staff_and_staff_without_two_factor_cannot_manage_apps(): void
    {
        config(['management.require_two_factor' => true]);
        $staff = User::factory()->create();
        $this->actingAs($staff)->get('/dashboard')->assertRedirect(route('security.edit'));
        $staff->forceFill(['active' => false])->save();
        $this->actingAs($staff)->get('/dashboard')->assertForbidden();
        $this->get('/register')->assertNotFound();
        $this->post('/register', [])->assertNotFound();
    }

    public function test_dashboard_and_details_render_for_enrolled_owner(): void
    {
        $owner = $this->owner();
        $app = app(AppConfiguration::class)->create($owner, $this->settings());
        $this->actingAs($owner)->get('/dashboard')->assertOk()->assertSee('Example Brand');
        $this->get('/apps/'.$app->id)->assertOk()->assertSee('Review saved draft');
        $this->get('/staff')->assertOk();
    }

    public function test_two_factor_is_optional_when_not_required_by_the_operator(): void
    {
        config(['management.require_two_factor' => false]);
        $owner = User::factory()->create(['role' => 'owner']);
        $this->actingAs($owner)->get('/dashboard')->assertOk();
        $this->post('/apps', $this->settings())->assertRedirect();
    }

    public function test_invalid_urls_and_insecure_update_feed_are_rejected(): void
    {
        $service = app(AppConfiguration::class);
        foreach (['https://user:password@example.test', 'ftp://example.test', 'https://example.test/?token=secret', 'https://example.test/#secret'] as $bad) {
            try {
                $service->validate([...$this->settings(), 'primary' => $bad]);
                $this->fail('Invalid address accepted');
            } catch (ValidationException $e) {
                $this->assertArrayHasKey('primary', $e->errors());
            }
        }
        $this->expectException(ValidationException::class);
        $service->validate([...$this->settings(), 'updateManifestUrl' => 'http://updates.example.test/update.json']);
    }

    public function test_first_owner_invitation_is_single_use_and_expires(): void
    {
        $invite = app(OwnerInvitation::class);
        $directory = storage_path('app/private');
        if (! is_dir($directory)) {
            mkdir($directory, 0700, true);
        }
        $token = bin2hex(random_bytes(32));
        file_put_contents($invite->path(), json_encode(['hash' => hash('sha256', $token), 'expires' => time() + 60]));
        try {
            $this->get('/owner-setup/'.str_repeat('0', 64))->assertNotFound();
            $this->get('/owner-setup/'.$token)->assertOk();
            $this->post('/owner-setup/'.$token, ['name' => 'Owner', 'email' => 'owner@example.test', 'password' => 'ExamplePassword1234', 'password_confirmation' => 'ExamplePassword1234'])->assertRedirect(route('login'));
            $this->assertSame('owner', User::first()->role);
            $this->assertFalse($invite->valid($token));
            $this->get('/owner-setup/'.$token)->assertNotFound();
        } finally {
            @unlink($invite->path());
            @unlink($invite->path().'.lock');
        }
    }
}
