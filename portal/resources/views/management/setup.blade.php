<x-layouts::auth title="Create owner account">
    <div class="space-y-6"><x-auth-header title="Welcome to App Manager" description="Create your private owner account. You’ll set up two-factor authentication after signing in." />
        @include('management.messages')
        <form method="POST" action="{{ route('owner.setup.store', $token) }}" class="space-y-5">@csrf
            <flux:input name="name" label="Your name" :value="old('name')" required />
            <flux:input name="email" label="Email address" type="email" :value="old('email')" autocomplete="username" required />
            <flux:input name="password" label="Password" description="At least 14 characters, including letters and numbers." type="password" autocomplete="new-password" required />
            <flux:input name="password_confirmation" label="Confirm password" type="password" autocomplete="new-password" required />
            <flux:button type="submit" variant="primary" class="w-full">Create owner account</flux:button>
        </form>
    </div>
</x-layouts::auth>
