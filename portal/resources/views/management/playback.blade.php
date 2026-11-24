<x-layouts::app title="Playback troubleshooting">
<div class="mx-auto max-w-6xl space-y-6">
    <header><flux:heading size="xl">Playback troubleshooting</flux:heading><p class="portal-muted mt-2">Find failures, inspect the evidence and follow recovery. Reports are retained for 30 days.</p></header>
    <details class="portal-card" @if($appId !== null || $days !== 7 || collect($filters)->except(['app','days'])->filter()->isNotEmpty()) open @endif>
    <summary class="cursor-pointer p-5 font-medium">Filter reports or find a support reference</summary>
    <form method="GET" class="grid gap-4 p-5 pt-0 sm:grid-cols-2 lg:grid-cols-4">
        <label>Support reference<input name="reference" value="{{ $filters['reference']??'' }}" placeholder="D-1234ABCD" class="mt-2 w-full rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"></label>
        <label>App<select name="app" class="mt-2 w-full rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"><option value="">All apps</option>@foreach($apps as $brand)<option value="{{ $brand->id }}" @selected($appId===$brand->id)>{{ $brand->name }}</option>@endforeach</select></label>
        <label>Period<select name="days" class="mt-2 w-full rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100">@foreach([1=>'Last 24 hours',7=>'Last 7 days',30=>'Last 30 days'] as $value=>$label)<option value="{{ $value }}" @selected($days===$value)>{{ $label }}</option>@endforeach</select></label>
        <label>Player<select name="engine" class="mt-2 w-full rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"><option value="">All players</option>@foreach(['native'=>'ExoPlayer','compatibility'=>'MPV','vlc'=>'VLC'] as $value=>$label)<option value="{{ $value }}" @selected(($filters['engine']??'')===$value)>{{ $label }}</option>@endforeach</select></label>
        <label>Video codec<select name="codec" class="mt-2 w-full rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"><option value="">All codecs</option>@foreach(['h264','hevc','av1','vp8','vp9','mpeg2','mpeg4','unknown'] as $value)<option value="{{ $value }}" @selected(($filters['codec']??'')===$value)>{{ strtoupper($value) }}</option>@endforeach</select></label>
        <label>Device<select name="model" class="mt-2 w-full rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"><option value="">All devices</option>@foreach($models as $value)<option @selected(($filters['model']??'')===$value)>{{ $value }}</option>@endforeach</select></label>
        <label>Version<select name="version" class="mt-2 w-full rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"><option value="">All versions</option>@foreach($versions->unique('version') as $value)<option value="{{ $value->version }}" @selected(($filters['version']??'')===$value->version)>{{ $value->version }}</option>@endforeach</select></label>
        <label>Recovery<select name="outcome" class="mt-2 w-full rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"><option value="">All outcomes</option><option value="recovered" @selected(($filters['outcome']??'')==='recovered')>Recovery observed</option><option value="unrecovered" @selected(($filters['outcome']??'')==='unrecovered')>Recovery not reported</option></select></label>
        <div class="flex gap-3 sm:col-span-2 lg:col-span-4"><flux:button type="submit" variant="primary">Apply filters</flux:button><flux:button :href="route('playback.index')">Clear</flux:button></div>
    </form>
    </details>
    <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        @foreach(['Error reports'=>$summary['events'],'Affected installations'=>$summary['devices'],'Sessions with a start report'=>$stats['sessions'],'Recovery observed'=>$stats['recovered']] as $label=>$value)<section class="portal-card p-5"><p class="portal-muted text-sm">{{ $label }}</p><strong class="text-3xl">{{ $value }}</strong></section>@endforeach
    </div>
    <section class="portal-card p-5"><strong>Sessions reporting errors · {{ $stats['sessions'] ? round($stats['affected']/$stats['sessions']*100,1).'%' : 'No sample yet' }}</strong><p class="portal-muted mt-2 text-sm">{{ $stats['affected'] }} of {{ $stats['sessions'] }} sessions with a received start report had an error. {{ $stats['playing'] }} reported playback progress. Recovery means progress was reported after the most recent error. Picture quality needs user confirmation. Session filters include all reported player attempts and recovery events. Delivery gaps and early exits can leave an outcome unknown.</p></section>
    <section class="space-y-3"><flux:heading size="lg">Recent sessions and attached diagnoses</flux:heading>
        @forelse($recentSessions as $session)
            <a href="{{ route('playback.session',[$session->app_device_id,$session->session_id]) }}" class="portal-card block p-4 transition hover:border-cyan-400"><div class="flex flex-wrap justify-between gap-2"><strong>D-{{ strtoupper(substr($session->session_id,0,8)) }} · {{ $session->device_model }}</strong><span>{{ $session->errors ? ($session->playing_sequence > $session->error_sequence ? 'Recovery observed' : 'Recovery not reported') : ($session->playing_sequence ? 'Playback progress observed' : 'Open report') }}</span></div><p class="portal-muted mt-2 text-sm">{{ $apps->firstWhere('id',$session->managed_app_id)?->name }} · Version {{ $session->version }} · {{ $session->last_received }} UTC</p></a>
        @empty<p class="portal-muted">Linked sessions will appear after devices install the reporting update.</p>@endforelse
    </section>
    <section class="space-y-4"><flux:heading size="lg">Error reports and next steps</flux:heading>
    @forelse($entries as $entry)
        <article class="portal-card p-5">
            <div class="flex flex-wrap justify-between gap-3"><strong>{{ $categories[$entry->category] ?? 'Other playback error' }}</strong><span class="portal-muted text-sm">{{ $entry->created_at }} UTC</span></div>
            <p class="mt-2">{{ $entry->device_model }} · {{ $entry->os_version }} · {{ $entry->form_factor==='tv' ? 'TV' : 'Mobile' }}</p>
            <p class="portal-muted mt-2 text-sm">{{ $apps->firstWhere('id',$entry->managed_app_id)?->name }} · {{ ['native'=>'ExoPlayer','compatibility'=>'MPV','vlc'=>'VLC'][$entry->engine] ?? 'Player' }} · Requested {{ $entry->decoding }} decoding · Version {{ $entry->version }} ({{ $entry->build }}) · {{ $entry->installation }}</p>
            <p class="mt-4 font-semibold">{{ $entry->guidance['confidence'] }}</p><p class="mt-2">{{ $entry->guidance['explanation'] }}</p><p class="portal-muted mt-2">{{ $entry->guidance['action'] }}</p>
            <details class="mt-4"><summary class="cursor-pointer font-medium text-cyan-700 dark:text-cyan-300">Technical evidence</summary><div class="mt-3">@include('management.playback-evidence',['evidence'=>$entry->evidence])</div></details>
            @if($entry->session_id)<a class="mt-4 inline-block font-medium text-cyan-700 dark:text-cyan-300" href="{{ route('playback.session',[$entry->app_device_id,$entry->session_id]) }}">Open timeline · D-{{ strtoupper(substr($entry->session_id,0,8)) }}</a>@else<p class="portal-muted mt-4 text-sm">Legacy report. Detailed evidence and a linked timeline require the app update.</p>@endif
        </article>
    @empty<section class="portal-card p-6">No playback reports in this period match these filters.</section>@endforelse
    {{ $entries->links() }}
    </section>
</div>
</x-layouts::app>
