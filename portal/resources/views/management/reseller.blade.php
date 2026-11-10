@if (auth()->user()->role === 'owner')
<section class="portal-card p-6 space-y-4"><flux:heading size="lg">Private reseller record</flux:heading><p class="portal-muted text-sm">These business contact details and the Downloader code stay in management. They are not sent to app users. Never enter account passwords here.</p>
    <form method="POST" action="{{ route('operations.reseller', $app) }}" class="grid gap-4 sm:grid-cols-2">@csrf
        <flux:input name="reseller_name" label="Reseller / company" maxlength="100" :value="old('reseller_name', $app->reseller_name)" />
        <flux:input name="reseller_email" label="Contact email" type="email" maxlength="180" :value="old('reseller_email', $app->reseller_email)" />
        <flux:input name="reseller_contact" label="Other business contact" maxlength="240" :value="old('reseller_contact', $app->reseller_contact)" />
        <flux:input name="downloader_code" label="Downloader code" inputmode="numeric" maxlength="20" :value="old('downloader_code', $app->downloader_code)" />
        <div><flux:button type="submit">Save reseller record</flux:button></div>
    </form>
    @if ($download)<p class="break-all text-sm">Permanent APK link: <a href="{{ $download }}" class="text-cyan-700 dark:text-cyan-400">{{ $download }}</a></p>@endif
</section>
@endif
