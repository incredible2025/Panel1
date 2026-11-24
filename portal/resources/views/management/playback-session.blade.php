<x-layouts::app title="Playback timeline">
<div class="mx-auto max-w-5xl space-y-6">
    <a href="{{ route('playback.index',['app'=>$brand->id]) }}" class="text-cyan-700 dark:text-cyan-300">← Playback reports</a>
    <header><flux:heading size="xl">{{ $reference }}</flux:heading><p class="portal-muted mt-2">{{ $brand->name }} · {{ $installation }}</p></header>
    <p class="portal-muted text-sm">Events are ordered by the sequence recorded on the device. Elapsed times use its playback-session clock. Device timestamps can differ from server receipt times. Missing events leave an outcome unknown.</p>
    @foreach($events as $event)
        <article class="portal-card p-5">
            <div class="flex flex-wrap justify-between gap-3"><strong>{{ $categories[$event->category] ?? 'Playback event' }}</strong><span>{{ $event->elapsed_ms !== null ? number_format($event->elapsed_ms/1000,1).' seconds from session start' : 'Elapsed time unavailable' }}</span></div>
            <p class="portal-muted mt-2 text-sm">{{ ['native'=>'ExoPlayer','compatibility'=>'MPV','vlc'=>'VLC','none'=>'Device diagnosis'][$event->engine] ?? 'Player' }} · Version {{ $event->version }} ({{ $event->build }}) · {{ $event->device_model }} · {{ $event->os_version }}</p>
            <p class="portal-muted mt-2 text-xs">Device time {{ $event->occurred_at ?? 'Unavailable' }} · Received {{ $event->created_at }} UTC</p>
            @if(in_array($event->category,\App\Services\PlaybackReports::ERRORS,true))<div class="mt-4"><strong>{{ $event->guidance['confidence'] }}</strong><p class="mt-2">{{ $event->guidance['explanation'] }}</p><p class="portal-muted mt-2">{{ $event->guidance['action'] }}</p></div>@endif
            @if($event->category==='playing')<p class="mt-3">The player reported advancing playback for at least one second. Picture quality still depends on what was displayed.</p>@endif
            <details class="mt-4" @if($event->category==='diagnosis') open @endif><summary class="cursor-pointer font-medium text-cyan-700 dark:text-cyan-300">{{ $event->category==='diagnosis' ? 'Connection diagnosis from this device' : 'Technical evidence' }}</summary><div class="mt-4">@include('management.playback-evidence',['evidence'=>$event->evidence])</div></details>
        </article>
    @endforeach
    @if($total>200)<p class="portal-muted">Showing the first 200 of {{ $total }} events in this session.</p>@endif
</div>
</x-layouts::app>
