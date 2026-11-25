@if (auth()->user()->role === 'owner' && $app->brand_spec)
<section class="portal-card p-6 space-y-4"><flux:heading size="lg">First-build checklist</flux:heading>
    <ol class="list-decimal space-y-2 pl-5 text-sm"><li>Review and publish the connection settings below. {{ $app->revision ? '✓ Published' : 'Pending' }}</li><li>Add build artwork and download the initial branding kit. {{ $app->brand_logo ? '✓ Artwork saved' : 'Artwork pending' }}</li><li>Download the build profile, then have the developer build and register this app's first package.</li><li>Upload the verified ZIP, pair a test device, record results and publish when ready. {{ $app->public_release_id ? '✓ Public package registered' : 'First package pending' }}</li></ol>
    <p class="portal-muted text-sm">An app draft alone is not an installable app. This kit is for the initial build; later versions are prepared from the brand's maintained project files.</p>
    <form method="POST" enctype="multipart/form-data" action="{{ route('brands.artwork', $app) }}" class="space-y-3">@csrf<label class="block text-sm">Build artwork<input type="file" name="logo" accept="image/png,image/jpeg,image/webp" required class="mt-2 block w-full"></label><flux:button type="submit">Save build artwork</flux:button></form>
    @if ($app->brand_logo)<flux:button :href="route('brands.kit', $app)">Download initial branding kit</flux:button>@endif
    <p class="portal-muted break-all text-xs">Planned permanent download link (available after the first package is registered): {{ url('/downloads/'.$app->app_id.'/'.$app->brand_spec['stableApkName']) }}</p>
</section>
@endif
