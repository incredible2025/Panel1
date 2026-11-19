<flux:input name="primary" label="Primary service address" type="url" :value="old('primary', $draft['primary'] ?? '')" required />
<flux:input name="fallback" label="Fallback service address (optional)" type="url" :value="old('fallback', $draft['fallback'] ?? '')" />
<flux:input name="updateManifestUrl" label="HTTPS update manifest address" type="url" :value="old('updateManifestUrl', $draft['updateManifestUrl'] ?? '')" required />
<details class="rounded-xl border border-slate-200 dark:border-white/10 p-4 space-y-4"><summary class="cursor-pointer font-medium">Maintenance notice &amp; support</summary>
    <p class="portal-muted text-sm">Optional. Clear the notice title and body to remove it. Notices do not interrupt playback. Save and publish these settings together.</p>
    <flux:input name="noticeTitle" label="Notice title" maxlength="80" :value="old('noticeTitle', $draft['noticeTitle'] ?? '')" />
    <flux:textarea name="noticeBody" label="Notice message" maxlength="500">{{ old('noticeBody', $draft['noticeBody'] ?? '') }}</flux:textarea>
    <flux:input name="noticeExpiresAt" label="Notice expiry (UTC)" type="datetime-local" :value="old('noticeExpiresAt', empty($draft['noticeExpiresAt']) ? '' : \Carbon\Carbon::parse($draft['noticeExpiresAt'])->utc()->format('Y-m-d\TH:i'))" />
    <flux:input name="supportEmail" label="Support email" type="email" :value="old('supportEmail', $draft['supportEmail'] ?? '')" />
    <flux:input name="supportWebsite" label="HTTPS support website" type="url" :value="old('supportWebsite', $draft['supportWebsite'] ?? '')" />
    <flux:textarea name="supportMessage" label="Support message" maxlength="500">{{ old('supportMessage', $draft['supportMessage'] ?? '') }}</flux:textarea>
</details>
