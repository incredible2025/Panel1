<x-layouts::app title="Bulk actions">
    <div class="mx-auto max-w-5xl space-y-6">
        <a href="{{ route('dashboard') }}" class="text-cyan-700 dark:text-cyan-400">← All apps</a><flux:heading size="xl">Bulk actions</flux:heading>
        <p class="portal-muted">Select the brands to change. Nothing is applied until you review and confirm. Each brand keeps its own service settings, branding and APK.</p>
        @include('management.messages')
        <form method="POST" action="{{ route('operations.bulk.prepare') }}" class="space-y-6">@csrf
            <section class="portal-card p-6 space-y-4"><flux:heading size="lg">Choose apps and packages</flux:heading>
                @foreach ($apps as $app)<div class="grid gap-3 border-t border-slate-200 dark:border-white/10 pt-4 sm:grid-cols-2"><label class="flex items-center gap-3"><input type="checkbox" name="app_ids[]" value="{{ $app->id }}"><span>{{ $app->name }}</span></label><select name="releases[{{ $app->id }}]" aria-label="Package for {{ $app->name }}" class="w-full rounded-lg border border-slate-300 bg-white p-2 text-slate-900 dark:border-white/20 dark:bg-slate-900 dark:text-white"><option value="">Choose package for release actions</option>@foreach ($releases->get($app->id, collect()) as $release)<option value="{{ $release->id }}">{{ $release->manifest['versionName'] }} ({{ $release->manifest['versionCode'] }}) · {{ $release->status }} · {{ str_replace('_', ' ', $release->test_result) }}</option>@endforeach</select></div>@endforeach
            </section>
            <section class="portal-card p-6 space-y-4"><flux:heading size="lg">Choose action</flux:heading><select name="operation" aria-label="Bulk action" class="w-full rounded-lg border border-slate-300 bg-white p-3 text-slate-900 dark:border-white/20 dark:bg-slate-900 dark:text-white"><option value="notice-draft">Save maintenance notice drafts</option><option value="notice-publish">Publish maintenance notices</option><option value="release-test">Offer selected packages to testers</option><option value="release-publish">Publish selected packages to everyone</option></select>
                <p class="portal-muted text-sm">Notice fields apply only to notice actions. Leave the title and message empty to remove a notice. Publishing notices refuses apps with unrelated unpublished settings. Package publication requires a passed test or an owner waiver for every selected package.</p>
                <flux:input name="noticeTitle" label="Notice title" maxlength="80" :value="old('noticeTitle')" />
                <flux:textarea name="noticeBody" label="Notice message" maxlength="500">{{ old('noticeBody') }}</flux:textarea>
                <flux:input name="noticeExpiresAt" label="Expiry (UTC)" type="datetime-local" :value="old('noticeExpiresAt')" />
                <flux:button type="submit" variant="primary">Review selected apps</flux:button>
            </section>
        </form>
    </div>
</x-layouts::app>
