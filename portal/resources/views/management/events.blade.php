<x-layouts::app title="Activity log">
    <div class="mx-auto max-w-6xl space-y-6">
        <a href="{{ route('dashboard') }}" class="text-cyan-700 dark:text-cyan-400">← All apps</a>
        <flux:heading size="xl">Staff activity log</flux:heading>
        <form method="GET" class="flex flex-wrap gap-3"><select name="app" class="rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:bg-slate-900 dark:text-white"><option value="">All apps</option>@foreach ($apps as $app)<option value="{{ $app->id }}" @selected(request('app') == $app->id)>{{ $app->name }}</option>@endforeach</select><flux:button type="submit">Filter</flux:button></form>
        <section class="portal-card overflow-x-auto p-5"><table class="w-full text-left text-sm"><thead><tr><th class="p-3">Time (UTC)</th><th>Staff</th><th>App</th><th>Action</th></tr></thead><tbody>@forelse ($events as $event)<tr class="border-t border-slate-200 dark:border-white/10"><td class="p-3">{{ $event->created_at }}</td><td>{{ $event->actor ?? 'System' }}</td><td>{{ $event->app_name ?? 'Management' }}</td><td>{{ $event->action }}</td></tr>@empty<tr><td colspan="4" class="p-4 portal-muted">No activity recorded yet.</td></tr>@endforelse</tbody></table></section>
        {{ $events->links() }}
    </div>
</x-layouts::app>
