<p class="mb-4 rounded-lg p-3 text-sm {{ $preview['signInRequired'] ? 'bg-amber-500/10 text-amber-900 dark:text-amber-200' : 'bg-cyan-500/10 text-cyan-900 dark:text-cyan-200' }}">
    @if ($preview['signInRequired']) This replaces the service. Users will need to sign in again.
    @elseif ($preview['firstPublication']) Initial settings publication. The app can be built after these settings are published.
    @else Same service: existing sign-ins, favourites and watch history are retained. @endif
</p>
@forelse ($preview['changes'] as $change)
    <div class="border-t border-slate-200 dark:border-white/10 py-4 text-sm"><strong>{{ $change['label'] }}</strong><div class="mt-2 grid gap-3 sm:grid-cols-2"><div class="min-w-0 break-words"><p class="portal-muted text-xs">Before</p><p class="whitespace-pre-wrap">{{ $change['before'] ?: 'None' }}</p></div><div class="min-w-0 break-words"><p class="portal-muted text-xs">After</p><p class="whitespace-pre-wrap">{{ $change['after'] ?: 'None' }}</p></div></div></div>
@empty<p class="portal-muted text-sm">No setting values change.</p>@endforelse
