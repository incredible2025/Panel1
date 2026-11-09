<x-layouts::app title="Staff">
    <div class="mx-auto max-w-4xl space-y-8">
        <header><flux:heading size="xl">Staff access</flux:heading><flux:text class="mt-2">Staff can edit and publish existing apps. Registering apps, replacing services and managing access are reserved for the owner.</flux:text></header>
        @include('management.messages')
        <div class="grid items-start gap-6 lg:grid-cols-2">
            <section class="portal-card p-5 sm:p-6">
                <flux:heading size="lg">Your team</flux:heading>
                <flux:text class="mt-2">{{ $staff->count() }} {{ $staff->count() === 1 ? 'account' : 'accounts' }} with portal access</flux:text>
                <ul class="mt-4 divide-y divide-slate-200 dark:divide-white/10">
                    @foreach ($staff as $member)
                        <li class="flex flex-wrap items-center justify-between gap-4 py-4">
                            <div class="min-w-0 space-y-1">
                                <p class="flex flex-wrap items-center gap-2 font-semibold">{{ $member->name }} <span class="rounded-full bg-slate-100 px-2 py-1 text-xs font-medium text-slate-600 dark:bg-white/10 dark:text-slate-300">{{ ucfirst($member->role) }}</span></p>
                                <p class="portal-muted break-all text-sm">{{ $member->email }}</p>
                                <p class="text-xs font-medium {{ $member->active ? 'text-emerald-700 dark:text-emerald-300' : 'text-slate-600 dark:text-slate-400' }}">{{ $member->active ? 'Active' : 'Disabled' }}</p>
                            </div>
                            @if ($member->role === 'staff')
                                <form method="POST" action="{{ route('staff.toggle', $member) }}">@csrf<flux:button type="submit" size="sm">{{ $member->active ? 'Disable access' : 'Enable access' }}</flux:button></form>
                            @endif
                        </li>
                    @endforeach
                </ul>
            </section>
            <form method="POST" action="{{ route('staff.create') }}" class="portal-card space-y-5 p-5 sm:p-6">
                @csrf
                <div><flux:heading size="lg">Add staff member</flux:heading><flux:text class="mt-2">Create a login for someone you trust to manage your apps.</flux:text></div>
                <flux:input name="name" label="Name" :value="old('name')" autocomplete="name" required />
                <flux:input name="email" label="Email" type="email" :value="old('email')" autocomplete="email" required />
                <flux:input name="password" label="Initial password" description="At least 14 characters, including letters and numbers." type="password" autocomplete="new-password" viewable required />
                <flux:input name="password_confirmation" label="Confirm password" type="password" autocomplete="new-password" viewable required />
                <flux:button type="submit" variant="primary" class="w-full">Create staff account</flux:button>
            </form>
        </div>
    </div>
</x-layouts::app>
