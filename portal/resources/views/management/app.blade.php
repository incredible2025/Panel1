<x-layouts::app :title="$app->name">
    <div class="mx-auto max-w-6xl space-y-8">
        <header><a href="{{ route('dashboard') }}" class="text-sm text-cyan-400">← All apps</a><flux:heading size="xl" class="mt-3">{{ $app->name }}</flux:heading><flux:text class="mt-2">{{ $app->package_id }} · Published revision {{ $app->revision }}</flux:text></header>
        @include('management.messages')
        <div class="grid gap-6 lg:grid-cols-2">
            <section class="rounded-2xl border border-zinc-700 bg-zinc-900 p-6">
                <flux:heading size="lg">Draft settings</flux:heading><flux:text class="mt-2">Use these fields when addresses move for the same service. Existing accounts remain signed in.</flux:text>
                <form method="POST" action="{{ route('apps.save', $app) }}" class="mt-6 space-y-5">@csrf
                    <input type="hidden" name="draft_version" value="{{ $app->draft_version }}">
                    @include('management.fields', ['draft' => $app->draft])
                    <flux:button type="submit">Save draft</flux:button>
                </form>
            </section>
            <section class="rounded-2xl border border-zinc-700 bg-zinc-900 p-6">
                <flux:heading size="lg">Publish to this app</flux:heading><flux:text class="mt-2">Save changes first, then publish the saved draft. Connected apps pick it up on their next configuration check.</flux:text>
                <dl class="my-6 space-y-3 break-all text-sm"><dt class="text-zinc-400">Saved primary</dt><dd>{{ $app->draft['primary'] }}</dd><dt class="text-zinc-400">Saved fallback</dt><dd>{{ $app->draft['fallback'] ?? 'None' }}</dd><dt class="text-zinc-400">Saved update feed</dt><dd>{{ $app->draft['updateManifestUrl'] }}</dd></dl>
                <form method="POST" action="{{ route('apps.publish', $app) }}">@csrf<input type="hidden" name="draft_version" value="{{ $app->draft_version }}"><flux:button type="submit" variant="primary">Publish saved draft</flux:button></form>
                @if ($app->revision)
                    <div class="mt-8 border-t border-zinc-700 pt-6"><flux:heading>Build profile</flux:heading><flux:text class="my-3">Download the signed bootstrap and public verification key for this brand’s Android build.</flux:text><flux:button :href="route('apps.profile', $app)">Download build profile</flux:button></div>
                @endif
            </section>
        </div>
        <section class="rounded-2xl border border-zinc-700 bg-zinc-900 p-6">
            <flux:heading size="lg">Publish history</flux:heading><flux:text class="mt-2">Restoring settings always creates a new revision.</flux:text>
            <div class="mt-5 overflow-x-auto"><table class="w-full text-left text-sm"><thead class="text-zinc-400"><tr><th class="py-3">Revision</th><th>Action</th><th>Published by</th><th>Time (UTC)</th><th></th></tr></thead><tbody>
                @foreach ($history as $entry)<tr class="border-t border-zinc-800"><td class="py-4">{{ $entry->revision }}</td><td>{{ $entry->action }}</td><td>{{ $entry->actor->name }}</td><td>{{ $entry->created_at->utc()->format('Y-m-d H:i') }}</td><td>
                    @if ($entry->revision !== $app->revision && ($entry->service_id === $app->service_id || auth()->user()->role === 'owner'))
                    <form method="POST" action="{{ route('apps.rollback', [$app, $entry->revision]) }}">@csrf<input type="hidden" name="draft_version" value="{{ $app->draft_version }}"><flux:button type="submit" size="sm">Restore {{ $entry->revision }}</flux:button></form>
                    @endif
                </td></tr>@endforeach
            </tbody></table></div><div class="mt-4">{{ $history->links() }}</div>
        </section>
        @if (auth()->user()->role === 'owner')
            <details class="rounded-2xl border border-amber-500/30 bg-amber-500/5 p-6"><summary class="cursor-pointer font-medium text-amber-200">Replace with a different service</summary><p class="my-4 text-sm text-zinc-300">This publishes a new service identity and requires users to sign in again. Use this only for a different provider, not an address change.</p>
                <form method="POST" action="{{ route('apps.replace', $app) }}" class="max-w-xl space-y-5">@csrf<input type="hidden" name="draft_version" value="{{ $app->draft_version }}">@include('management.fields', ['draft' => []])<flux:input name="confirmation" label="Type REPLACE to confirm" required /><flux:button type="submit" variant="danger">Replace service and publish</flux:button></form>
            </details>
        @endif
    </div>
</x-layouts::app>
