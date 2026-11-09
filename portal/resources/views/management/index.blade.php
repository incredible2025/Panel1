<x-layouts::app title="Apps">
    <div class="mx-auto max-w-6xl space-y-8">
        <header><p class="mb-2 text-xs uppercase tracking-widest text-cyan-400">Control centre</p><flux:heading size="xl">Your apps</flux:heading><flux:text class="mt-2">Manage each brand independently. Publish service settings without rebuilding its app.</flux:text></header>
        @include('management.messages')
        <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            @forelse ($apps as $app)
                <a href="{{ route('apps.show', $app) }}" class="rounded-2xl border border-zinc-700 bg-zinc-900 p-6 transition hover:border-cyan-400 focus-visible:outline-2 focus-visible:outline-cyan-400">
                    <div class="flex items-start justify-between gap-3"><flux:heading size="lg">{{ $app->name }}</flux:heading><span class="rounded-full bg-cyan-500/10 px-3 py-1 text-xs text-cyan-300">{{ $app->revision ? 'Published' : 'Draft' }}</span></div>
                    <p class="mt-3 text-sm text-zinc-400">{{ $app->package_id }}</p><p class="mt-6 text-sm text-zinc-300">Revision {{ $app->revision }} <span class="float-right text-cyan-400">Manage →</span></p>
                </a>
            @empty
                <div class="rounded-2xl border border-dashed border-zinc-700 p-8 text-zinc-400 md:col-span-2">No apps registered yet. Add your first brand below.</div>
            @endforelse
        </div>
        @if (auth()->user()->role === 'owner')
            <section class="max-w-2xl rounded-2xl border border-zinc-700 bg-zinc-900 p-6">
                <flux:heading size="lg">Register an app</flux:heading><flux:text class="mt-2">App and package identifiers are permanent after creation.</flux:text>
                <form method="POST" action="{{ route('apps.create') }}" class="mt-6 space-y-5">@csrf
                    <flux:input name="name" label="Brand name" :value="old('name')" required />
                    <flux:input name="app_id" label="App identifier" description="Lowercase letters, numbers and dashes. At least three characters." :value="old('app_id')" required />
                    <flux:input name="package_id" label="Android package identifier" :value="old('package_id')" required />
                    @include('management.fields', ['draft' => []])
                    <flux:button type="submit" variant="primary">Create app draft</flux:button>
                </form>
            </section>
        @endif
    </div>
</x-layouts::app>
