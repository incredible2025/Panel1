<x-layouts::app title="Review changes">
    <div class="mx-auto max-w-5xl space-y-6">
        <a href="{{ route('dashboard') }}" class="text-cyan-700 dark:text-cyan-400">← Cancel and return</a>
        <flux:heading size="xl">Review {{ count($plan['data']['items']) }} selected {{ count($plan['data']['items']) === 1 ? 'app' : 'apps' }}</flux:heading>
        <p class="portal-muted">Operation: {{ str_replace('-', ' ', $plan['kind']) }}. This review expires in 15 minutes. Changes to an app after this review require a fresh review.</p>
        @include('management.messages')
        @foreach ($plan['data']['items'] as $item)
            <section class="portal-card p-6"><flux:heading size="lg">{{ $item['name'] }}</flux:heading>
                @if (isset($item['preview']))<div class="mt-4">@include('management.config-diff', ['preview' => $item['preview']])</div>
                @else<p class="mt-3">Package {{ $item['release_version'] }}</p><p class="portal-muted text-sm">Verification: ready · Test result: {{ str_replace('_', ' ', $item['test_result']) }}</p><p class="mt-3 text-sm">{{ $plan['kind'] === 'release-test' ? 'Only paired testers will be offered this version.' : 'This package will become the public release for this brand.' }}</p>@endif
            </section>
        @endforeach
        <form method="POST" action="{{ route('operations.confirm', $ticket) }}" class="portal-card p-6 space-y-4">@csrf
            <label class="flex items-start gap-3"><input type="checkbox" name="reviewed" value="1" required class="mt-1"><span>I have reviewed every selected app and the changes above.</span></label>
            <flux:button type="submit" variant="primary">Apply reviewed changes</flux:button>
        </form>
    </div>
</x-layouts::app>
