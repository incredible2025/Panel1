<x-layouts::app title="Apps">
    <div class="mx-auto max-w-6xl space-y-8">
        <header><p class="mb-2 text-xs uppercase tracking-widest text-cyan-700 dark:text-cyan-400">Control centre</p><flux:heading size="xl">Your apps</flux:heading><flux:text class="mt-2">Manage each brand independently. Publish service settings without rebuilding its app.</flux:text></header>
        @include('management.messages')
        @if (auth()->user()->role === 'owner')
        <div class="flex flex-wrap gap-3"><flux:button :href="route('brands.start')" variant="primary">Set up a new brand</flux:button><flux:button :href="route('operations.bulk')">Bulk actions</flux:button><flux:button :href="route('operations.health')">Health overview</flux:button></div>
        @if ($health && (! $health['fresh'] || ! $health['backupGood'] || ! $health['diskGood'] || $health['failed'] || $health['stalled']))<a href="{{ route('operations.health') }}" class="block rounded-xl bg-amber-500/10 p-4 text-sm text-amber-900 dark:text-amber-200">Management health needs attention. Open the health overview for current job, storage and backup details.</a>@endif
        @endif
        <div class="portal-card p-5 flex flex-wrap gap-8"><div><p class="portal-muted text-sm">Online across apps</p><strong class="text-3xl" data-total="online">{{ collect($metrics)->sum('online') }}</strong></div><div><p class="portal-muted text-sm">Active today</p><strong class="text-3xl" data-total="today">{{ collect($metrics)->sum('today') }}</strong></div>@if (auth()->user()->role === 'owner')<a href="{{ route('management.events') }}" class="self-center text-cyan-700 dark:text-cyan-400">Staff activity log →</a>@endif</div>
        @include('management.activity-refresh')
        <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            @forelse ($apps as $app)
                <a href="{{ route('apps.show', $app) }}" class="portal-card p-6 transition hover:border-cyan-400 focus-visible:outline-2 focus-visible:outline-cyan-400">
                    <div class="flex items-start justify-between gap-3"><flux:heading size="lg">{{ $app->name }}</flux:heading><span class="rounded-full bg-cyan-500/10 px-3 py-1 text-xs text-cyan-800 dark:text-cyan-300">{{ $app->revision ? 'Published' : 'Draft' }}</span></div>
                    <p class="mt-3 text-sm text-slate-600 dark:text-slate-400">{{ $app->package_id }}</p><p class="mt-6 text-sm text-slate-700 dark:text-slate-300">Revision {{ $app->revision }} <span class="float-right text-cyan-700 dark:text-cyan-400">Manage →</span></p>
                    <div class="mt-5" data-activity-app="{{ $app->id }}"><p class="text-sm"><strong data-count="online">{{ $metrics[$app->id]['online'] }}</strong> online · <strong data-count="today">{{ $metrics[$app->id]['today'] }}</strong> active today</p><p class="portal-muted mt-2 text-xs">Reporting devices · {{ config('app.timezone') }}</p></div>
                    <p class="portal-muted mt-3 text-xs">Latest public version: {{ $metrics[$app->id]['adoption'] === null ? 'No adoption data yet' : $metrics[$app->id]['adoption'].'% of reporting devices' }}</p>
                </a>
            @empty
                <div class="rounded-2xl border border-dashed border-slate-200 dark:border-white/10 p-8 text-slate-600 dark:text-slate-400 md:col-span-2">No apps registered yet. Add your first brand below.</div>
            @endforelse
        </div>
        @if (auth()->user()->role === 'owner')
            <details class="max-w-2xl portal-card p-6"><summary class="cursor-pointer font-medium">Advanced app registration</summary>
                <flux:text class="mt-2">Use the setup wizard above for guided branding and managed download links. These identifiers are permanent after creation.</flux:text>
                <form method="POST" action="{{ route('apps.create') }}" class="mt-6 space-y-5">@csrf
                    <flux:input name="name" label="Brand name" :value="old('name')" required />
                    <flux:input name="app_id" label="App identifier" description="Lowercase letters, numbers and dashes. At least three characters." :value="old('app_id')" required />
                    <flux:input name="package_id" label="Android package identifier" :value="old('package_id')" required />
                    @include('management.fields', ['draft' => []])
                    <flux:button type="submit" variant="primary">Create app draft</flux:button>
                </form>
            </details>
        @endif
    </div>
</x-layouts::app>
