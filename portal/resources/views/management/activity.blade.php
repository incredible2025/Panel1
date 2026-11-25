<section class="portal-card p-5" data-activity-app="{{ $app->id }}">
    <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
        @foreach (['online' => 'Online now', 'today' => 'Active today', 'current' => 'Current settings', 'pending' => 'Awaiting settings'] as $key => $label)
            <div><p class="portal-muted text-xs">{{ $label }}</p><p class="mt-1 text-2xl font-semibold" data-count="{{ $key }}">{{ $metrics[$key] }}</p></div>
        @endforeach
    </div>
    <p class="portal-muted mt-4 text-xs">Reporting devices, not individual people. Online means seen within 3 minutes. Today uses {{ config('app.timezone') }}. <span data-stale>{{ $metrics['stale'] }}</span> not seen recently.</p>
</section>
