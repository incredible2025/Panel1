<section class="portal-card p-6 space-y-5">
    <flux:heading size="lg">Release centre</flux:heading>
    <p class="portal-muted text-sm">Upload a verified branded ZIP (up to 400 MiB). Uploading prepares a release; it never sends it to users automatically. Refresh this page for processing results.</p>
    <form method="POST" enctype="multipart/form-data" action="{{ route('releases.upload', $app) }}" class="space-y-3"
          x-data="{ busy: false, progress: 0, error: '' }"
          x-on:submit.prevent="if (busy) return; const form = new FormData($el); busy = true; error = ''; progress = 0; const xhr = new XMLHttpRequest(); xhr.open('POST', $el.action); xhr.setRequestHeader('Accept', 'application/json'); xhr.upload.onprogress = e => { if (e.lengthComputable) progress = Math.round(e.loaded / e.total * 100); }; xhr.onload = () => { if (xhr.status === 201) { location.reload(); return; } busy = false; error = xhr.status === 413 ? 'Package exceeds the upload limit.' : 'Upload failed. Check the selected ZIP and your sign-in session, then retry.'; }; xhr.onerror = () => { busy = false; error = 'Connection interrupted. Retry the upload.'; }; xhr.send(form);">
        @csrf<input aria-label="Branded update ZIP" type="file" name="bundle" accept=".zip" required class="block w-full text-sm">
        <flux:button type="submit" x-bind:disabled="busy">Upload for verification</flux:button>
        <div x-show="busy" x-cloak role="status"><progress class="w-full" max="100" x-bind:value="progress"></progress><p class="portal-muted text-sm" x-text="progress + '% uploaded — verification begins after upload.'"></p></div>
        <p x-show="error" x-cloak x-text="error" role="alert" class="text-sm text-red-700 dark:text-red-300"></p>
    </form>
    @forelse ($releases as $release)
        <article class="rounded-xl border border-slate-200 dark:border-white/10 p-4 space-y-3">
            <div class="flex flex-wrap justify-between gap-2"><strong>{{ $release->manifest['versionName'] ?? 'New upload' }} @if ($release->manifest) ({{ $release->manifest['versionCode'] }}) @endif</strong><span class="portal-muted">{{ ucfirst($release->status) }}</span></div>
            @if ($release->manifest)<p class="whitespace-pre-line text-sm">{{ $release->manifest['releaseNotes'] }}</p>@endif
            @if ($release->status === 'failed')<p class="text-sm text-red-700 dark:text-red-300">Verification or processing failed. Existing releases remain available. Contact the deployment operator to inspect the retained upload.</p>@endif
            @if (auth()->user()->role === 'owner' && in_array($release->status, ['ready', 'testing']))
                <div class="flex flex-wrap gap-3">
                    @foreach (['test' => 'Offer to testers', 'publish' => 'Publish to everyone', 'withdraw' => 'Withdraw candidate'] as $action => $label)
                        <form method="POST" action="{{ route('releases.action', [$app, $release]) }}" @if ($action === 'publish') onsubmit="return confirm('Publish this release to everyone using this app?')" @endif>@csrf<input type="hidden" name="action" value="{{ $action }}"><flux:button type="submit" :variant="$action === 'publish' ? 'primary' : 'outline'">{{ $label }}</flux:button></form>
                    @endforeach
                </div>
            @endif
        </article>
    @empty<p class="portal-muted">No packages registered yet.</p>@endforelse
</section>
@if (auth()->user()->role === 'owner')
<section class="portal-card p-6 space-y-5">
    <flux:heading size="lg">Test devices</flux:heading><p class="portal-muted text-sm">In the app, open Settings → Management &amp; support → Link test device. Enter its ten-minute code here. Testers only receive releases offered to this app.</p>
    <form method="POST" action="{{ route('devices.pair', $app) }}" class="grid gap-4 sm:grid-cols-3 items-end">@csrf<flux:input name="code" label="Six-digit code" inputmode="numeric" maxlength="6" required /><flux:input name="label" label="Device name" maxlength="80" required /><flux:button type="submit">Pair device</flux:button></form>
    @forelse ($devices as $device)<div class="flex flex-wrap items-center justify-between gap-3 border-t border-slate-200 dark:border-white/10 pt-4"><div><strong>{{ $device->label }}</strong><p class="portal-muted text-sm">{{ $device->version }} ({{ $device->build }}) · Last seen {{ $device->last_seen_at->diffForHumans() }}</p></div><form method="POST" action="{{ route('devices.revoke', [$app, $device]) }}">@csrf<flux:button type="submit">Remove test access</flux:button></form></div>@empty<p class="portal-muted text-sm">No paired devices.</p>@endforelse
</section>
@endif
