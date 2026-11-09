<flux:input name="primary" label="Primary service address" type="url" :value="old('primary', $draft['primary'] ?? '')" required />
<flux:input name="fallback" label="Fallback service address (optional)" type="url" :value="old('fallback', $draft['fallback'] ?? '')" />
<flux:input name="updateManifestUrl" label="HTTPS update manifest address" type="url" :value="old('updateManifestUrl', $draft['updateManifestUrl'] ?? '')" required />
