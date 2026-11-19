<x-layouts::app title="Playback reports">
    <div class="mx-auto max-w-6xl space-y-6">
        <header><flux:heading size="xl">Playback reports</flux:heading><p class="portal-muted mt-2">Find patterns by device, player and app version. Reports expire after 30 days.</p></header>
        <form method="GET" class="portal-card flex flex-wrap items-end gap-4 p-5">
            <label class="flex flex-col gap-2">App<select name="app" class="rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"><option value="">All apps</option>@foreach ($apps as $app)<option value="{{ $app->id }}" @selected($appId === $app->id)>{{ $app->name }}</option>@endforeach</select></label>
            <label class="flex flex-col gap-2">Period<select name="days" class="rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100">@foreach ([1 => 'Last 24 hours', 7 => 'Last 7 days', 30 => 'Last 30 days'] as $value => $label)<option value="{{ $value }}" @selected($days === $value)>{{ $label }}</option>@endforeach</select></label>
            <flux:button type="submit" variant="primary">Apply filters</flux:button>
        </form>
        <div class="grid grid-cols-2 gap-4"><section class="portal-card p-5"><p class="portal-muted">Reports</p><strong class="text-3xl">{{ $summary['events'] }}</strong></section><section class="portal-card p-5"><p class="portal-muted">Affected installations</p><strong class="text-3xl">{{ $summary['devices'] }}</strong></section></div>
        <p class="portal-muted text-sm">Automatic reports cover player errors, prolonged buffering and caught Android playback exceptions. Picture problems are user-reported. Sudden native process termination may leave no report. Counts describe reporting installations and are not a failure rate.</p>
        <div class="space-y-3">
            @forelse ($summary['groups'] as $group)
                <section class="portal-card p-5">
                    <div class="flex flex-wrap justify-between gap-3"><strong>{{ $categories[$group->category] ?? 'Other playback error' }}</strong><span>{{ $group->events }} reports · {{ $group->devices }} installations</span></div>
                    <p class="mt-2">{{ $group->device_model }} · {{ $group->os_version }} · {{ $group->form_factor === 'tv' ? 'TV' : 'Mobile' }}</p>
                    <p class="portal-muted mt-2 text-sm">{{ ['native' => 'ExoPlayer', 'compatibility' => 'MPV', 'vlc' => 'VLC'][$group->engine] ?? 'Player' }} · {{ ucfirst($group->decoding) }} decoding · Version {{ $group->version }} ({{ $group->build }}) · {{ $group->source === 'user' ? 'User report' : 'Automatic' }}</p>
                    <p class="portal-muted mt-2 text-xs">Last received {{ $group->last_reported }} · {{ config('app.timezone') }}</p>
                </section>
            @empty
                <section class="portal-card p-8"><strong>No playback reports in this period</strong><p class="portal-muted mt-2">Devices need a version of the app with playback reporting. An empty report does not establish that every device is playing successfully.</p></section>
            @endforelse
        </div>
        @if ($summary['groups']->count() === 100)<p class="portal-muted text-sm">Showing the 100 most frequent combinations. Filter by app or a shorter period to narrow the results.</p>@endif
    </div>
</x-layouts::app>
