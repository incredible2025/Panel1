<x-layouts::app title="Playback error details">
<div class="mx-auto max-w-5xl space-y-6">
    <a href="{{ route('playback.index',['app'=>$brand->id]) }}" class="text-cyan-700 dark:text-cyan-300">← Playback reports</a>
    <header><flux:heading size="xl">{{ $reference }}</flux:heading><p class="portal-muted mt-2">{{ $brand->name }} · {{ $installation }}</p></header>
    <p class="portal-muted text-sm">Only errors and user-submitted diagnoses appear here. Normal playback is not logged. Device timestamps can differ from server receipt times.</p>
    @foreach($events as $event)
        <article class="portal-card p-5">
            <div class="flex flex-wrap justify-between gap-3"><strong>{{ $categories[$event->category] ?? 'Playback event' }}</strong><span>{{ $event->elapsed_ms !== null ? number_format($event->elapsed_ms/1000,1).' seconds from session start' : 'Elapsed time unavailable' }}</span></div>
            <p class="mt-2 font-semibold">Line username: {{ $event->username ?? 'Unavailable — requires the updated app' }}</p>
            <p class="portal-muted mt-2 text-sm">{{ ['native'=>'ExoPlayer','compatibility'=>'MPV','vlc'=>'VLC','none'=>'Device diagnosis'][$event->engine] ?? 'Player' }} · Version {{ $event->version }} ({{ $event->build }}) · {{ $event->device_model }} · {{ $event->os_version }}</p>
            <p class="portal-muted mt-2 text-xs">Device time {{ $event->occurred_at ?? 'Unavailable' }} · Received {{ $event->created_at }} UTC</p>
            @if(in_array($event->category,\App\Services\PlaybackReports::ERRORS,true))<div class="mt-4"><strong>{{ $event->guidance['confidence'] }}</strong><p class="mt-2">{{ $event->guidance['explanation'] }}</p><p class="portal-muted mt-2">{{ $event->guidance['action'] }}</p></div>@endif
            <details class="mt-4" @if($event->category==='diagnosis') open @endif><summary class="cursor-pointer font-medium text-cyan-700 dark:text-cyan-300">{{ $event->category==='diagnosis' ? 'Connection diagnosis from this device' : 'Technical evidence' }}</summary><div class="mt-4">@include('management.playback-evidence',['evidence'=>$event->evidence])</div></details>
        </article>
    @endforeach
    @if($total>200)<p class="portal-muted">Showing the first 200 of {{ $total }} events in this session.</p>@endif
</div>
</x-layouts::app>
